import SwiftUI

@main
struct VideoResumeApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task { await model.load() }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 520, minHeight: 560)
        }
        #endif
    }
}
