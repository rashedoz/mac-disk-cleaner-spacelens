import AppKit
import Observation
import SwiftUI

struct ScanTarget: Identifiable, Hashable {
    enum Kind { case home, volume, folder }

    let path: String
    let name: String
    let kind: Kind
    var total: Int64?
    var available: Int64?

    var id: String { path }

    var icon: String {
        switch kind {
        case .home: return "house.fill"
        case .volume: return path == "/" ? "internaldrive.fill" : "externaldrive.fill"
        case .folder: return "folder.fill"
        }
    }
}

enum SidebarSelection: Hashable {
    case target(String)
    case caches
    case tips
}

@MainActor
@Observable
final class AppState {
    var targets: [ScanTarget] = []
    var selection: SidebarSelection = .target("/")

    /// Finished scans, keyed by target path.
    var results: [String: FileNode] = [:]
    var durations: [String: TimeInterval] = [:]
    /// The directory currently shown in the chart, per target.
    var focus: [String: FileNode] = [:]

    var scanningPath: String?
    var progress = ScanProgress()
    var scanStart = Date()

    var hovered: FileNode?
    var pendingTrash: FileNode?
    var errorMessage: String?
    /// Bumped whenever a tree is edited in place so views redraw.
    var treeVersion = 0
    var hasFullDiskAccess = true

    @ObservationIgnored private var scanner: DiskScanner?
    @ObservationIgnored private var timer: Timer?

    init() {
        refreshTargets()
        checkFullDiskAccess()
        openFolderFromArguments()
    }

    /// `SpaceLens --open /some/folder` starts with that folder selected.
    private func openFolderFromArguments() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--open"), i + 1 < args.count else { return }
        let path = URL(fileURLWithPath: args[i + 1]).standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        if !targets.contains(where: { $0.path == path }) {
            targets.append(ScanTarget(path: path, name: (path as NSString).lastPathComponent, kind: .folder))
        }
        selection = .target(path)
    }

    var selectedTarget: ScanTarget? {
        if case let .target(path) = selection { return targets.first { $0.path == path } }
        return nil
    }

    // MARK: - Targets

    func refreshTargets() {
        var list: [ScanTarget] = []
        let home = NSHomeDirectory()
        list.append(ScanTarget(path: home, name: NSUserName(), kind: .home))

        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            list.append(ScanTarget(
                path: url.path,
                name: v.volumeName ?? url.lastPathComponent,
                kind: .volume,
                total: v.volumeTotalCapacity.map(Int64.init),
                available: v.volumeAvailableCapacityForImportantUsage
            ))
        }
        // Keep folders the user added earlier.
        list.append(contentsOf: targets.filter { $0.kind == .folder })
        targets = list
        if selectedTarget == nil, case .target = selection, let first = list.first {
            selection = .target(list.first { $0.path == "/" }?.path ?? first.path)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        if !targets.contains(where: { $0.path == path }) {
            targets.append(ScanTarget(path: path, name: url.lastPathComponent, kind: .folder))
        }
        selection = .target(path)
    }

    func removeFolder(_ target: ScanTarget) {
        guard target.kind == .folder, scanningPath != target.path else { return }
        drop(results.removeValue(forKey: target.path))
        focus[target.path] = nil
        targets.removeAll { $0.path == target.path }
        if selection == .target(target.path) { selection = .target(targets.first?.path ?? "/") }
    }

    // MARK: - Scanning

    func startScan(_ target: ScanTarget) {
        guard scanningPath == nil else { return }
        hovered = nil
        focus[target.path] = nil
        drop(results.removeValue(forKey: target.path))

        let scanner = DiskScanner()
        self.scanner = scanner
        scanningPath = target.path
        progress = ScanProgress()
        scanStart = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let scanner = self.scanner else { return }
                self.progress = scanner.snapshot()
            }
        }

        let path = target.path
        let name = target.name
        Task.detached(priority: .userInitiated) {
            let root = scanner.scan(path: path, name: name)
            await MainActor.run { self.finishScan(path: path, root: root, cancelled: scanner.isCancelled) }
        }
    }

    func cancelScan() {
        scanner?.cancel()
    }

    private func finishScan(path: String, root: FileNode?, cancelled: Bool) {
        timer?.invalidate()
        timer = nil
        scanner = nil
        scanningPath = nil
        durations[path] = Date().timeIntervalSince(scanStart)
        if let root {
            withAnimation(.spring(duration: 0.5)) { results[path] = root }
        } else if !cancelled {
            errorMessage = "Could not read \(path)."
        }
        refreshTargets()
        checkFullDiskAccess()
    }

    /// Frees a large tree off the main thread so the UI does not hitch.
    private func drop(_ node: FileNode?) {
        guard let node else { return }
        DispatchQueue.global(qos: .utility).async { _ = node }
    }

    // MARK: - Navigation

    func focusNode(for target: ScanTarget) -> FileNode? {
        focus[target.path] ?? results[target.path]
    }

    func setFocus(_ node: FileNode, in target: ScanTarget) {
        guard node.isDir else { return }
        hovered = nil
        withAnimation(.spring(duration: 0.4)) { focus[target.path] = node }
    }

    // MARK: - File actions

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }

    func trash(_ node: FileNode) {
        guard node.parent != nil else { return }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: node.path), resultingItemURL: nil)
        } catch {
            errorMessage = "Could not move “\(node.name)” to the Trash.\n\(error.localizedDescription)"
            return
        }
        for (path, current) in focus where current.isDescendant(of: node) {
            focus[path] = node.parent
        }
        hovered = nil
        node.detach()
        treeVersion += 1
        refreshTargets()
    }

    // MARK: - Permissions

    func checkFullDiskAccess() {
        // Readable only with Full Disk Access; probing it never shows a prompt.
        let probe = NSHomeDirectory() + "/Library/Safari"
        hasFullDiskAccess = (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
