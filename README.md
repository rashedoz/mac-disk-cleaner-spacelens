# SpaceLens

A fast, native disk space analyzer and cache cleaner for macOS.

**[Download and landing page](https://rashedoz.github.io/mac-disk-cleaner-spacelens/)**

- **Analyzer:** scans a volume or folder and draws it as an interactive sunburst chart next to a size-sorted list. Click a slice to open it, click the centre to go back up.
- **Cache Cleaner:** finds and sizes known cache locations (app caches, Xcode, npm, Gradle, Homebrew, logs, Trash and more), labels each as safe or re-downloadable, and deletes only what you select.
- **Tips:** copy-ready commands for the clean-ups an app should not do for you (Docker, simulators, Time Machine snapshots).

## Install

1. Download `SpaceLens.zip` from the landing page, unzip it and move SpaceLens to Applications.
2. The app is not notarised, so macOS blocks the first launch. Open System Settings › Privacy & Security and click **Open Anyway**.
3. Grant Full Disk Access when the app asks. Without it, protected folders are skipped and totals come out low.

Requires macOS 14 or later. Runs on Apple silicon and Intel.

## Build from source

Requires Xcode 15 or later.

```bash
./build.sh                # builds build/SpaceLens.app
open build/SpaceLens.app
swift test                # scanner unit tests
./build.sh --zip          # also refreshes docs/download/SpaceLens.zip
```

## How it works

- `Sources/SpaceLens/Scanner` reads directories with `getattrlistbulk` on a pool of worker threads. It reports allocated size, counts hard links once and stays on the volume being scanned.
- `Sources/SpaceLens/Models/CacheStore.swift` holds the list of cache locations and the deletion rules. It only ever deletes inside the home folder.
- `Sources/SpaceLens/Views` is the SwiftUI interface.
- `docs/` is the landing page, served by GitHub Pages.

## Safety

- Files removed from the analyzer go to the Trash.
- Caches are deleted permanently, after a confirmation that shows the total size.
- The app makes no network connections.
