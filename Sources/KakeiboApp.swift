import SwiftUI

@main
struct KakeiboApp: App {
    @StateObject private var store = AppStore.makeDefault()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .tint(TxPalette.accent)
                .preferredColorScheme(store.settings.theme.colorScheme)
        }
    }
}
