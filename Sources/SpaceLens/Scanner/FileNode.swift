import Foundation

/// One entry in a scanned tree. Directories own their children; sizes are bytes on disk.
final class FileNode: Identifiable, @unchecked Sendable {
    let name: String
    let isDir: Bool
    weak var parent: FileNode?
    /// Bytes on disk. For directories this includes everything below it.
    var size: Int64
    /// Sub-directories plus the larger files, sorted largest first once the scan finishes.
    var children: [FileNode] = []
    /// Number of files below this directory.
    var fileCount: Int = 0
    /// Files too small to be worth a node of their own are rolled up into these two.
    var smallCount: Int = 0
    var smallSize: Int64 = 0
    /// Set on the root only: the absolute path the scan started at.
    var basePath: String?
    var unreadable = false

    init(name: String, isDir: Bool, size: Int64 = 0, parent: FileNode? = nil) {
        self.name = name
        self.isDir = isDir
        self.size = size
        self.parent = parent
    }

    var path: String {
        if let basePath { return basePath }
        guard let parent else { return name }
        let p = parent.path
        return p.hasSuffix("/") ? p + name : p + "/" + name
    }

    /// Root first, self last.
    var ancestors: [FileNode] {
        var chain: [FileNode] = []
        var n: FileNode? = self
        while let node = n {
            chain.append(node)
            n = node.parent
        }
        return chain.reversed()
    }

    func isDescendant(of other: FileNode) -> Bool {
        var n: FileNode? = self
        while let node = n {
            if node === other { return true }
            n = node.parent
        }
        return false
    }

    /// Removes this node from the tree and subtracts its size from every ancestor.
    func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        let files = isDir ? fileCount : 1
        var n: FileNode? = parent
        while let node = n {
            node.size -= size
            node.fileCount -= files
            n = node.parent
        }
        self.parent = nil
    }
}
