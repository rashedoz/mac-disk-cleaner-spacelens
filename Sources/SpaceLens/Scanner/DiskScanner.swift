import Darwin
import Foundation

struct ScanProgress: Sendable {
    struct Top: Sendable, Identifiable {
        let id: Int
        let name: String
        var bytes: Int64
    }

    var files = 0
    var dirs = 0
    var bytes: Int64 = 0
    /// Running totals for the items directly inside the scan root.
    var top: [Top] = []
    var currentPath = ""
}

/// Scans a directory tree with `getattrlistbulk` (one syscall per directory batch)
/// on a pool of worker threads. One instance performs one scan.
final class DiskScanner: @unchecked Sendable {
    /// Files at least this big always get their own node.
    static let bigFile: Int64 = 1 << 20
    /// Smaller files are kept only near the top of the tree, and only this many per directory.
    static let smallKeepPerDir = 50
    static let smallKeepDepth = 6

    private struct Job {
        let node: FileNode
        let path: String
        let top: Int
        let depth: Int
    }

    private struct LinkKey: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private struct Outcome {
        var jobs: [Job] = []
        var files = 0
        var bytes: Int64 = 0
        var newTop: [ScanProgress.Top] = []
    }

    private let cond = NSCondition()
    private var stack: [Job] = []
    private var active = 0
    private var cancelled = false
    private var progress = ScanProgress()

    private let linkLock = NSLock()
    private var seenLinks = Set<LinkKey>()

    private var allowedDevs = Set<Int32>()
    private var skipPaths = Set<String>()

    var isCancelled: Bool {
        cond.lock()
        defer { cond.unlock() }
        return cancelled
    }

    func cancel() {
        cond.lock()
        cancelled = true
        cond.broadcast()
        cond.unlock()
    }

    func snapshot() -> ScanProgress {
        cond.lock()
        defer { cond.unlock() }
        return progress
    }

    /// Blocks until the scan finishes. Returns nil if the path is not a readable directory
    /// or the scan was cancelled.
    func scan(path rawPath: String, name: String? = nil) -> FileNode? {
        let path = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().path
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return nil }

        allowedDevs = [st.st_dev]
        if path == "/" {
            // The boot disk is two APFS volumes: the sealed system volume and the Data
            // volume, stitched together with firmlinks. Count both, and skip the raw
            // mount point so the Data volume is not counted twice.
            var data = stat()
            if lstat("/System/Volumes/Data", &data) == 0 { allowedDevs.insert(data.st_dev) }
            skipPaths = ["/System/Volumes", "/Volumes", "/dev"]
        }

        let root = FileNode(name: name ?? (path as NSString).lastPathComponent, isDir: true)
        root.basePath = path
        stack = [Job(node: root, path: path, top: -1, depth: 0)]

        let workers = min(max(ProcessInfo.processInfo.activeProcessorCount, 2), 12)
        DispatchQueue.concurrentPerform(iterations: workers) { _ in worker() }

        if isCancelled { return nil }
        finalize(root)
        return root
    }

    // MARK: - Workers

    private func worker() {
        let bufSize = 256 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }

        while true {
            cond.lock()
            while stack.isEmpty && active > 0 && !cancelled { cond.wait() }
            if stack.isEmpty || cancelled {
                cond.broadcast()
                cond.unlock()
                return
            }
            let job = stack.removeLast()
            active += 1
            cond.unlock()

            let out = process(job, buf, bufSize)

            cond.lock()
            stack.append(contentsOf: out.jobs)
            active -= 1
            progress.files += out.files
            progress.dirs += 1
            progress.bytes += out.bytes
            progress.currentPath = job.path
            if job.top < 0 {
                progress.top = out.newTop
            } else if job.top < progress.top.count {
                progress.top[job.top].bytes += out.bytes
            }
            cond.broadcast()
            cond.unlock()
        }
    }

    // Attribute bits, in the order the kernel packs them.
    private static let cmnReturned: UInt32 = 0x8000_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnDevID: UInt32 = 0x0000_0002
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let typeDir: UInt32 = 2
    /// Set on cloud placeholders; listing one would make the provider download it.
    private static let flagDataless: UInt32 = 0x4000_0000

    private func process(_ job: Job, _ buf: UnsafeMutableRawPointer, _ bufSize: Int) -> Outcome {
        typealias S = DiskScanner
        var out = Outcome()
        let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else {
            job.node.unreadable = true
            return out
        }
        defer { close(fd) }

        var al = attrlist()
        al.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        al.commonattr = S.cmnReturned | S.cmnError | S.cmnName | S.cmnDevID | S.cmnObjType | S.cmnFlags | S.cmnFileID
        al.fileattr = S.fileLinkCount | S.fileAllocSize

        let prefix = job.path == "/" ? "/" : job.path + "/"
        var dirs: [(node: FileNode, path: String)] = []
        var files: [(name: String, size: Int64)] = []
        var fileBytes: Int64 = 0

        while true {
            let count = getattrlistbulk(fd, &al, buf, bufSize, 0)
            if count <= 0 { break }
            var entry = buf
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var f = entry + 4
                let returned = f.loadUnaligned(as: attribute_set_t.self)
                f += MemoryLayout<attribute_set_t>.size
                entry += length

                if returned.commonattr & S.cmnError != 0 { f += 4 }
                var name = ""
                if returned.commonattr & S.cmnName != 0 {
                    let ref = f.loadUnaligned(as: attrreference_t.self)
                    name = String(cString: (f + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    f += MemoryLayout<attrreference_t>.size
                }
                var dev: Int32 = 0
                if returned.commonattr & S.cmnDevID != 0 {
                    dev = f.loadUnaligned(as: Int32.self)
                    f += 4
                }
                var type: UInt32 = 0
                if returned.commonattr & S.cmnObjType != 0 {
                    type = f.loadUnaligned(as: UInt32.self)
                    f += 4
                }
                var flags: UInt32 = 0
                if returned.commonattr & S.cmnFlags != 0 {
                    flags = f.loadUnaligned(as: UInt32.self)
                    f += 4
                }
                var fileID: UInt64 = 0
                if returned.commonattr & S.cmnFileID != 0 {
                    fileID = f.loadUnaligned(as: UInt64.self)
                    f += 8
                }
                if name.isEmpty { continue }

                if type == S.typeDir {
                    if !allowedDevs.contains(dev) { continue } // another volume mounted here
                    if flags & S.flagDataless != 0 { continue }
                    let childPath = prefix + name
                    if !skipPaths.isEmpty && skipPaths.contains(childPath) { continue }
                    dirs.append((FileNode(name: name, isDir: true, parent: job.node), childPath))
                    continue
                }

                var links: UInt32 = 1
                if returned.fileattr & S.fileLinkCount != 0 {
                    links = f.loadUnaligned(as: UInt32.self)
                    f += 4
                }
                var size: Int64 = 0
                if returned.fileattr & S.fileAllocSize != 0 {
                    size = f.loadUnaligned(as: Int64.self)
                }
                if links > 1 && size > 0 {
                    // Count a hard-linked file once, wherever it is first seen.
                    linkLock.lock()
                    let first = seenLinks.insert(LinkKey(dev: dev, ino: fileID)).inserted
                    linkLock.unlock()
                    if !first { size = 0 }
                }
                files.append((name, size))
                fileBytes += size
            }
        }

        // Decide which files get their own node.
        let keepSmall = job.depth <= S.smallKeepDepth
        if files.count > S.smallKeepPerDir || !keepSmall {
            files.sort { $0.size > $1.size }
        }
        var children: [FileNode] = []
        children.reserveCapacity(dirs.count + min(files.count, S.smallKeepPerDir))
        for d in dirs { children.append(d.node) }
        var smallCount = 0
        var smallSize: Int64 = 0
        for (i, file) in files.enumerated() {
            if file.size >= S.bigFile || (keepSmall && i < S.smallKeepPerDir) {
                children.append(FileNode(name: file.name, isDir: false, size: file.size, parent: job.node))
            } else {
                smallCount += 1
                smallSize += file.size
            }
        }

        let node = job.node
        node.children = children
        node.size = fileBytes
        node.fileCount = files.count
        node.smallCount = smallCount
        node.smallSize = smallSize

        out.files = files.count
        out.bytes = fileBytes
        if job.top < 0 {
            // Root: every direct child becomes a live progress entry.
            out.newTop = children.enumerated().map { i, child in
                ScanProgress.Top(id: i, name: child.name, bytes: child.isDir ? 0 : child.size)
            }
            out.jobs = dirs.enumerated().map { i, d in
                Job(node: d.node, path: d.path, top: i, depth: 1)
            }
        } else {
            out.jobs = dirs.map { Job(node: $0.node, path: $0.path, top: job.top, depth: job.depth + 1) }
        }
        return out
    }

    /// Rolls sizes up from the leaves and sorts every directory largest-first.
    private func finalize(_ root: FileNode) {
        var order: [FileNode] = [root]
        var i = 0
        while i < order.count {
            let n = order[i]
            i += 1
            for c in n.children where c.isDir { order.append(c) }
        }
        for n in order.reversed() {
            var size = n.size
            var count = n.fileCount
            for c in n.children where c.isDir {
                size += c.size
                count += c.fileCount
            }
            n.size = size
            n.fileCount = count
            if n.children.count > 1 { n.children.sort { $0.size > $1.size } }
        }
    }
}
