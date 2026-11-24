import SwiftUI

struct CacheCleanerView: View {
    @Environment(CacheStore.self) private var store
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.isScanning && !store.hasScanned {
                Spacer()
                ProgressView("Measuring caches…").controlSize(.large)
                Spacer()
            } else if store.entries.isEmpty {
                Spacer()
                Text("No caches found.").foregroundStyle(Theme.textDim)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let freed = store.lastFreed {
                            freedBanner(freed)
                        }
                        ForEach(CacheCategory.allCases, id: \.self) { category in
                            let items = store.entries(in: category)
                            if !items.isEmpty {
                                section(category, items)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.top, 28)
        .onAppear { if !store.hasScanned { store.scan() } }
        .confirmationDialog(
            "Delete \(Fmt.bytes(store.selectedSize)) of caches?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { store.clean() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(store.selected.count) selected items are deleted right away and do not go to the Trash. Apps rebuild what they need. Quit the apps involved first.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cache Cleaner").font(.system(size: 24, weight: .bold, design: .rounded))
                Text(store.hasScanned
                     ? "\(Fmt.bytes(store.totalCleanable)) can be cleaned"
                     : "Finds files your Mac and apps can re-create")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if store.isScanning || store.isCleaning {
                ProgressView().controlSize(.small)
            }
            Button { store.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .buttonStyle(GhostButtonStyle())
                .disabled(store.isScanning || store.isCleaning)
            Button("Select Safe") { store.selectSafe() }
                .buttonStyle(GhostButtonStyle())
                .disabled(store.entries.isEmpty || store.isCleaning)
            Button {
                confirming = true
            } label: {
                Text(store.selected.isEmpty ? "Clean" : "Clean \(Fmt.bytes(store.selectedSize))")
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(store.selected.isEmpty || store.isCleaning || store.isScanning)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func freedBanner(_ freed: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good)
            Text(store.failures > 0
                 ? "Freed \(Fmt.bytes(freed)). \(store.failures) items were in use or protected and were left alone."
                 : "Freed \(Fmt.bytes(freed)).")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button { store.lastFreed = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
        }
        .padding(12)
        .background(Theme.good.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.good.opacity(0.3)))
    }

    private func section(_ category: CacheCategory, _ items: [CacheEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: category.icon).foregroundStyle(Theme.accentA)
                Text(category.rawValue).font(.system(size: 13, weight: .semibold))
                Text(Fmt.bytes(items.reduce(0) { $0 + $1.size }))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.leading, 4)
            ForEach(items) { entry in
                CacheRow(entry: entry)
            }
        }
    }
}

private struct CacheRow: View {
    @Environment(CacheStore.self) private var store
    let entry: CacheEntry
    @State private var hovering = false

    var body: some View {
        let isOn = store.selected.contains(entry.id)
        HStack(spacing: 12) {
            if entry.safety == .review {
                Image(systemName: "eye")
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 20)
            } else {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.3)))
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(entry.safety.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.safety.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(entry.safety.color.opacity(0.14), in: Capsule())
                }
                Text(entry.note).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                Text(entry.displayPath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            if hovering || entry.safety == .review {
                Button("Show in Finder") {
                    if let first = entry.roots.first {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)])
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }
            Text(Fmt.bytes(entry.size))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isOn ? Theme.accentA.opacity(0.13) : (hovering ? Theme.cardHover : Theme.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isOn ? Theme.accentA.opacity(0.5) : Theme.stroke)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard entry.safety != .review, !store.isCleaning else { return }
            if isOn { store.selected.remove(entry.id) } else { store.selected.insert(entry.id) }
        }
    }
}
