import SwiftUI

@main
struct KakeiboApp: App {
    @StateObject private var launcher = AppLauncher()

    var body: some Scene {
        WindowGroup {
            switch launcher.phase {
            case .ready(let store):
                RootView()
                    .environmentObject(store)
            case .failed(let message):
                StartupFailureView(message: message,
                                   retry: { launcher.open() },
                                   startFresh: { launcher.startFresh() })
                    .tint(TxPalette.accent)
            }
        }
    }
}
