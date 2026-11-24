import SwiftUI

struct AnalyzerView: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget

    var body: some View {
        VStack(spacing: 0) {
            if !state.hasFullDiskAccess {
                FullDiskAccessBanner()
            }
            if state.scanningPath == target.path {
                ScanningView(target: target)
                    .transition(.opacity)
            } else if let root = state.results[target.path] {
                ResultsView(target: target, root: root, focus: state.focusNode(for: target) ?? root)
                    .transition(.opacity)
            } else {
                IdleView(target: target)
                    .transition(.opacity)
            }
        }
        .padding(.top, 28)
    }
}

private struct FullDiskAccessBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Theme.warn)
            Text("Without Full Disk Access, protected folders such as Mail, Safari and other apps’ data are skipped, so totals come out low.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button("Open Settings") { state.openFullDiskAccessSettings() }
                .buttonStyle(GhostButtonStyle())
            Button("Check Again") { state.checkFullDiskAccess() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warn.opacity(0.25)))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Idle

private struct IdleView: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18)).frame(width: 150, height: 150).blur(radius: 30)
                Image(systemName: target.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 6) {
                Text(target.name).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(target.path).font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            if let total = target.total, let available = target.available, total > 0 {
                VStack(spacing: 8) {
                    UsageBar(fraction: Double(total - available) / Double(total), height: 8)
                        .frame(width: 320)
                    HStack {
                        Text("\(Fmt.bytes(total - available)) used")
                        Spacer()
                        Text("\(Fmt.bytes(available)) free of \(Fmt.bytes(total))")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 320)
                }
            }
            Button {
                state.startScan(target)
            } label: {
                Label("Scan", systemImage: "play.fill")
            }
            .buttonStyle(AccentButtonStyle(large: true))
            .disabled(state.scanningPath != nil)
            .keyboardShortcut(.defaultAction)
            if state.scanningPath != nil {
                Text("Another scan is running.").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Scanning

private struct ScanningView: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget

    var body: some View {
        let progress = state.progress
        let segments = SunburstLayout.segments(for: progress.top)
        HStack(spacing: 30) {
            ZStack {
                SunburstCanvas(segments: segments, rings: 1)
                    .animation(.linear(duration: 0.1), value: progress.bytes)
                VStack(spacing: 4) {
                    Text("Scanning").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textDim)
                    Text(Fmt.bytes(progress.bytes))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                    Text("\(Fmt.count(progress.files)) files")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                        .monospacedDigit()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 420)
            .padding(20)

            VStack(alignment: .leading, spacing: 10) {
                Text(target.name).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(progress.currentPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 14)
                VStack(spacing: 4) {
                    ForEach(segments.prefix(9)) { s in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 10, height: 10)
                            Text(s.label).font(.system(size: 12.5)).lineLimit(1)
                            Spacer()
                            if s.size > 0 {
                                Text(Fmt.bytes(s.size))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textDim)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.top, 6)
                Button("Cancel") { state.cancelScan() }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, 8)
            }
            .frame(width: 320, alignment: .leading)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Results

private struct ResultsView: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget
    let root: FileNode
    let focus: FileNode

    var body: some View {
        let _ = state.treeVersion
        let segments = SunburstLayout.segments(for: focus)
        var colors: [ObjectIdentifier: Color] = [:]
        for s in segments where s.depth == 1 {
            if let node = s.node { colors[ObjectIdentifier(node)] = s.color }
        }

        return VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                SunburstView(target: target, focus: focus, segments: segments)
                    .id(ObjectIdentifier(focus))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FileListView(target: target, focus: focus, colors: colors)
                    .frame(width: 370)
            }
            StatusBar()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let chain = focus.ancestors
                    ForEach(Array(chain.enumerated()), id: \.offset) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                        }
                        Button(node.name) { state.setFocus(node, in: target) }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: node === focus ? .semibold : .regular))
                            .foregroundStyle(node === focus ? .white : Theme.textDim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(node === focus ? Theme.card : .clear, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 10)
            if let seconds = state.durations[target.path] {
                Text("\(Fmt.count(root.fileCount)) files in \(String(format: "%.1f", seconds)) s")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize()
            }
            Button {
                state.startScan(target)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(state.scanningPath != nil)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

private struct StatusBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            if let node = state.hovered {
                Image(systemName: node.isDir ? "folder.fill" : "doc.fill")
                    .foregroundStyle(Theme.accentA)
                Text(node.path).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Fmt.bytes(node.size)).fontWeight(.semibold)
            } else {
                Text("Click a slice to open it. Click the centre to go back up. Right-click an item for more.")
                Spacer()
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 20)
        .frame(height: 30)
        .background(Color.black.opacity(0.22))
    }
}

// MARK: - List

private struct FileListView: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget
    let focus: FileNode
    let colors: [ObjectIdentifier: Color]

    private static let pageSize = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(focus.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer()
                Text(Fmt.bytes(focus.size))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(focus.children.prefix(Self.pageSize)) { node in
                        FileRow(target: target, node: node, parentSize: focus.size,
                                color: colors[ObjectIdentifier(node)] ?? SunburstLayout.otherColor)
                    }
                    let hidden = focus.children.count - Self.pageSize
                    if hidden > 0 {
                        note("\(Fmt.count(hidden)) more items, each smaller than the ones above")
                    }
                    if focus.smallCount > 0 {
                        note("\(Fmt.count(focus.smallCount)) small files · \(Fmt.bytes(focus.smallSize))")
                    }
                    if focus.children.isEmpty && focus.smallCount == 0 {
                        note(focus.unreadable ? "This folder could not be read." : "This folder is empty.")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .id(ObjectIdentifier(focus))
        }
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

private struct FileRow: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget
    let node: FileNode
    let parentSize: Int64
    let color: Color
    @State private var hovering = false

    var body: some View {
        let fraction = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 4, height: 28)
            Image(systemName: node.isDir ? "folder.fill" : "doc.fill")
                .font(.system(size: 13))
                .foregroundStyle(node.isDir ? Theme.accentA : Color.white.opacity(0.55))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                UsageBarPlain(fraction: fraction, color: color)
            }
            Spacer(minLength: 6)
            if hovering {
                Button { state.reveal(node) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
                    .help("Reveal in Finder")
                Button { state.pendingTrash = node } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.bad)
                    .help("Move to Trash")
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.bytes(node.size)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                Text(Fmt.percent(node.size, of: parentSize)).font(.system(size: 10.5)).foregroundStyle(Theme.textDim)
            }
            .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering || state.hovered === node ? Theme.cardHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { state.hovered = node } else if state.hovered === node { state.hovered = nil }
        }
        .onTapGesture(count: 2) {
            if node.isDir { state.setFocus(node, in: target) } else { state.reveal(node) }
        }
        .contextMenu {
            if node.isDir {
                Button("Open in Chart") { state.setFocus(node, in: target) }
            }
            Button("Reveal in Finder") { state.reveal(node) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
            Divider()
            Button("Move to Trash…", role: .destructive) { state.pendingTrash = node }
        }
    }
}

private struct UsageBarPlain: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color.opacity(0.9))
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}
