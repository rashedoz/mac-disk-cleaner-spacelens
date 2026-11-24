import SwiftUI

@main
struct SpaceLensApp: App {
    @State private var state = AppState()
    @State private var caches = CacheStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .environment(caches)
                .frame(minWidth: 1000, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
