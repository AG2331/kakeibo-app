import SwiftUI

@main
struct KakeiboApp: App {
    @StateObject private var store = AppStore.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(TxPalette.accent)
                .preferredColorScheme(store.settings.theme.colorScheme)
        }
    }
}
