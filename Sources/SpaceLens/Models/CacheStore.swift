import AppKit
import Observation
import SwiftUI

enum CacheSafety {
    /// Rebuilt automatically; deleting costs nothing but time.
    case safe
    /// Deletable, but something will need re-downloading or re-building.
    case caution
    /// Not cleaned by the app; the user should look at it first.
    case review

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Re-downloads"
        case .review: return "Review first"
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.good
        case .caution: return Theme.warn
        case .review: return Theme.accentA
        }
    }
}

enum CacheCategory: String, CaseIterable {
    case apps = "App Caches"
    case developer = "Developer"
    case system = "Logs & Trash"
    case review = "Worth a Look"

    var icon: String {
        switch self {
        case .apps: return "square.stack.3d.up.fill"
        case .developer: return "hammer.fill"
        case .system: return "trash.fill"
        case .review: return "eye.fill"
        }
    }
}

struct CacheEntry: Identifiable {
    let id: String
    let title: String
    let category: CacheCategory
    let safety: CacheSafety
    let note: String
    /// Directories whose contents get removed.
    let roots: [String]
    var size: Int64

    var displayPath: String {
        guard let first = roots.first else { return "" }
        let short = first.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return roots.count > 1 ? "\(short) and \(roots.count - 1) more" : short
    }
}

/// A fixed, known cache location.
private struct CacheDef {
    let title: String
    let path: String
    let category: CacheCategory
    let safety: CacheSafety
    let note: String
}

private let cacheDefs: [CacheDef] = [
    // Developer
    .init(title: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData", category: .developer, safety: .safe,
          note: "Build products and indexes. Xcode rebuilds them the next time you open a project."),
    .init(title: "Xcode iOS Device Support", path: "~/Library/Developer/Xcode/iOS DeviceSupport", category: .developer, safety: .safe,
          note: "Debug symbols copied from devices you plugged in. Re-created when you connect the device again."),
    .init(title: "Simulator caches", path: "~/Library/Developer/CoreSimulator/Caches", category: .developer, safety: .safe,
          note: "Simulator runtime caches. Rebuilt on the next simulator launch."),
    .init(title: "Xcode Previews", path: "~/Library/Developer/Xcode/UserData/Previews", category: .developer, safety: .safe,
          note: "SwiftUI preview simulators. Rebuilt when you open a preview."),
    .init(title: "npm cache", path: "~/.npm/_cacache", category: .developer, safety: .safe,
          note: "Downloaded package tarballs. npm fetches them again when needed."),
    .init(title: "Bun cache", path: "~/.bun/install/cache", category: .developer, safety: .safe,
          note: "Downloaded packages. Bun fetches them again when needed."),
    .init(title: "pnpm store", path: "~/Library/pnpm/store", category: .developer, safety: .caution,
          note: "Shared package store. Projects re-download their packages on the next install."),
    .init(title: "Gradle caches", path: "~/.gradle/caches", category: .developer, safety: .caution,
          note: "Dependencies and build caches. The next Android or Gradle build downloads them again."),
    .init(title: "Maven repository", path: "~/.m2/repository", category: .developer, safety: .caution,
          note: "Downloaded Java dependencies. Re-downloaded on the next build."),
    .init(title: "CocoaPods specs", path: "~/.cocoapods/repos", category: .developer, safety: .caution,
          note: "Local copy of the pod spec repos. `pod install` clones them again."),
    .init(title: "Cargo registry", path: "~/.cargo/registry", category: .developer, safety: .caution,
          note: "Downloaded Rust crates. Cargo fetches them again on the next build."),
    .init(title: "Dart & Flutter pub cache", path: "~/.pub-cache", category: .developer, safety: .caution,
          note: "Downloaded Dart packages. `pub get` restores them."),
    .init(title: "VS Code cache", path: "~/Library/Application Support/Code/Cache", category: .developer, safety: .safe,
          note: "Web cache used by VS Code. Quit VS Code first."),
    .init(title: "VS Code cached data", path: "~/Library/Application Support/Code/CachedData", category: .developer, safety: .safe,
          note: "Compiled script cache. Quit VS Code first."),
    .init(title: "Cursor cache", path: "~/Library/Application Support/Cursor/Cache", category: .developer, safety: .safe,
          note: "Web cache used by Cursor. Quit Cursor first."),
    .init(title: "Cursor cached data", path: "~/Library/Application Support/Cursor/CachedData", category: .developer, safety: .safe,
          note: "Compiled script cache. Quit Cursor first."),
    // Logs & Trash
    .init(title: "Trash", path: "~/.Trash", category: .system, safety: .caution,
          note: "Everything in the Trash is deleted for good."),
    .init(title: "User logs", path: "~/Library/Logs", category: .system, safety: .safe,
          note: "Diagnostic logs written by apps. Only useful when you are debugging a crash."),
    // Review only
    .init(title: "Xcode Archives", path: "~/Library/Developer/Xcode/Archives", category: .review, safety: .review,
          note: "Archived app builds. Keep the ones you may need to symbolicate crashes for; delete old ones in Xcode’s Organizer."),
    .init(title: "Simulator devices", path: "~/Library/Developer/CoreSimulator/Devices", category: .review, safety: .review,
          note: "Simulator disks, including installed apps and their data. See Tips for the command that removes unused ones."),
    .init(title: "iPhone & iPad backups", path: "~/Library/Application Support/MobileSync/Backup", category: .review, safety: .review,
          note: "Local device backups. Remove old ones in Finder: select the device, then Manage Backups."),
    .init(title: "Docker disk image", path: "~/Library/Containers/com.docker.docker/Data/vms", category: .review, safety: .review,
          note: "Docker’s virtual disk. Shrink it with `docker system prune`, not by deleting the file."),
    .init(title: "Android emulators", path: "~/.android/avd", category: .review, safety: .review,
          note: "Android virtual devices. Delete unused ones from Android Studio’s Device Manager."),
]

/// Friendly names and notes for well-known folders inside ~/Library/Caches.
private let knownCacheFolders: [String: (title: String, note: String)] = [
    "Homebrew": ("Homebrew downloads", "Downloaded bottles and source archives. Homebrew fetches them again when needed."),
    "pip": ("pip cache", "Downloaded Python wheels. pip fetches them again when needed."),
    "Yarn": ("Yarn cache", "Downloaded packages. Yarn fetches them again when needed."),
    "pnpm": ("pnpm cache", "Package metadata cache. Rebuilt automatically."),
    "CocoaPods": ("CocoaPods cache", "Downloaded pods. Fetched again on the next `pod install`."),
    "go-build": ("Go build cache", "Compiled Go packages. Rebuilt on the next build."),
    "ms-playwright": ("Playwright browsers", "Test browsers. Re-installed with `npx playwright install`."),
    "Google": ("Google Chrome cache", "Web cache. Pages reload a little slower the first time."),
    "com.apple.Safari": ("Safari cache", "Web cache. Pages reload a little slower the first time."),
    "Firefox": ("Firefox cache", "Web cache. Pages reload a little slower the first time."),
    "BraveSoftware": ("Brave cache", "Web cache. Pages reload a little slower the first time."),
    "com.spotify.client": ("Spotify cache", "Streamed music cache. Downloaded songs stay untouched."),
    "node-gyp": ("node-gyp cache", "Node headers for native builds. Downloaded again when needed."),
    "typescript": ("TypeScript cache", "Type definitions cache. Rebuilt automatically."),
]

@MainActor
@Observable
final class CacheStore {
    var entries: [CacheEntry] = []
    var selected = Set<String>()
    var isScanning = false
    var isCleaning = false
    var hasScanned = false
    var lastFreed: Int64?
    var failures = 0

    var cleanable: [CacheEntry] { entries.filter { $0.safety != .review } }
    var totalCleanable: Int64 { cleanable.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { entries.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func entries(in category: CacheCategory) -> [CacheEntry] {
        entries.filter { $0.category == category }.sorted { $0.size > $1.size }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let found = CacheStore.findEntries()
            await MainActor.run {
                withAnimation(.spring(duration: 0.4)) {
                    self.entries = found
                    self.selected = self.selected.intersection(found.map(\.id))
                    self.isScanning = false
                    self.hasScanned = true
                }
            }
        }
    }

    func selectSafe() {
        selected = Set(entries.filter { $0.safety == .safe }.map(\.id))
    }

    func clean() {
        let targets = entries.filter { selected.contains($0.id) && $0.safety != .review }
        guard !targets.isEmpty, !isCleaning else { return }
        let before = targets.reduce(0) { $0 + $1.size }
        isCleaning = true
        Task.detached(priority: .userInitiated) {
            var failed = 0
            for entry in targets {
                for root in entry.roots { failed += CacheStore.removeContents(of: root) }
            }
            let found = CacheStore.findEntries()
            let ids = Set(targets.map(\.id))
            let after = found.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.size }
            let failures = failed
            await MainActor.run {
                withAnimation(.spring(duration: 0.4)) {
                    self.entries = found
                    self.selected = []
                    self.isCleaning = false
                    self.lastFreed = max(before - after, 0)
                    self.failures = failures
                }
            }
        }
    }

    // MARK: - Work done off the main thread

    nonisolated private static func expand(_ path: String) -> String {
        path.hasPrefix("~") ? NSHomeDirectory() + path.dropFirst() : path
    }

    nonisolated static func findEntries() -> [CacheEntry] {
        var result: [CacheEntry] = []

        for def in cacheDefs {
            let path = expand(def.path)
            guard let node = DiskScanner().scan(path: path), node.size > 0 else { continue }
            result.append(CacheEntry(id: path, title: def.title, category: def.category, safety: def.safety,
                                     note: def.note, roots: [path], size: node.size))
        }

        // ~/Library/Caches: one entry per sizeable app, the rest lumped together.
        let cachesPath = expand("~/Library/Caches")
        if let caches = DiskScanner().scan(path: cachesPath) {
            let minSize: Int64 = 20 << 20
            var otherRoots: [String] = []
            var otherSize: Int64 = 0
            for child in caches.children where child.isDir && child.size > 0 {
                if child.size >= minSize {
                    let known = knownCacheFolders[child.name]
                    result.append(CacheEntry(
                        id: child.path,
                        title: known?.title ?? appName(forCacheFolder: child.name),
                        category: .apps,
                        safety: .safe,
                        note: known?.note ?? "Temporary files this app can re-create. Quit the app first for a clean result.",
                        roots: [child.path],
                        size: child.size
                    ))
                } else {
                    otherRoots.append(child.path)
                    otherSize += child.size
                }
            }
            if otherSize > 0 {
                result.append(CacheEntry(id: cachesPath + "#other", title: "Other app caches (\(otherRoots.count) apps)",
                                         category: .apps, safety: .safe,
                                         note: "Small caches from the rest of your apps.",
                                         roots: otherRoots, size: otherSize))
            }
        }
        return result
    }

    nonisolated private static func appName(forCacheFolder folder: String) -> String {
        if folder.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folder) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return folder
    }

    /// Only ever delete inside the user's home folder, and never the home folder
    /// or one of its top-level folders themselves.
    nonisolated static func isSafeToEmpty(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        guard resolved.hasPrefix(home + "/") else { return false }
        let depth = resolved.dropFirst(home.count).split(separator: "/").count
        return depth >= 2 || resolved == home + "/.Trash"
    }

    /// Deletes everything inside `root`, keeping the folder. Returns how many items failed.
    nonisolated static func removeContents(of root: String) -> Int {
        guard isSafeToEmpty(root) else { return 1 }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: root) else { return 1 }
        var failed = 0
        for item in items {
            do { try fm.removeItem(atPath: root + "/" + item) } catch { failed += 1 }
        }
        return failed
    }
}
