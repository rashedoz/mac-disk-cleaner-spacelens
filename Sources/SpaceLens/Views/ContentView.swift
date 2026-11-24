import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 232)
            ZStack {
                Theme.background
                switch state.selection {
                case .target:
                    if let target = state.selectedTarget {
                        AnalyzerView(target: target)
                    }
                case .caches:
                    CacheCleanerView()
                case .tips:
                    TipsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .alert("Move to Trash?", isPresented: Binding(
            get: { state.pendingTrash != nil },
            set: { if !$0 { state.pendingTrash = nil } }
        ), presenting: state.pendingTrash) { node in
            Button("Move to Trash", role: .destructive) { state.trash(node) }
            Button("Cancel", role: .cancel) {}
        } message: { node in
            Text("“\(node.name)” (\(Fmt.bytes(node.size))) will be moved to the Trash. Space is freed once you empty the Trash.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                Text("SpaceLens")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.top, 46)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    header("Locations")
                    ForEach(state.targets) { target in
                        SidebarRow(
                            icon: target.icon,
                            title: target.name,
                            fraction: usage(target),
                            busy: state.scanningPath == target.path,
                            selected: state.selection == .target(target.path)
                        ) { state.selection = .target(target.path) }
                        .contextMenu {
                            if target.kind == .folder {
                                Button("Remove from Sidebar") { state.removeFolder(target) }
                            }
                        }
                    }
                    Button { state.chooseFolder() } label: {
                        Label("Choose Folder…", systemImage: "plus.circle")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }

            // Pinned below the list so a long list of volumes never hides it.
            VStack(alignment: .leading, spacing: 2) {
                Rectangle().fill(Theme.stroke).frame(height: 1).padding(.bottom, 10)
                header("Clean Up")
                SidebarRow(icon: "sparkles", title: "Cache Cleaner", selected: state.selection == .caches) {
                    state.selection = .caches
                }
                SidebarRow(icon: "lightbulb.fill", title: "Tips", selected: state.selection == .tips) {
                    state.selection = .tips
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func usage(_ target: ScanTarget) -> Double? {
        guard let total = target.total, let available = target.available, total > 0 else { return nil }
        return Double(total - available) / Double(total)
    }
}

private struct SidebarRow: View {
    let icon: String
    let title: String
    var fraction: Double?
    var busy = false
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.accentA))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    if let fraction {
                        UsageBar(fraction: fraction, height: 3)
                    }
                }
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accent.opacity(0.85)) : AnyShapeStyle(hovering ? Theme.cardHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
