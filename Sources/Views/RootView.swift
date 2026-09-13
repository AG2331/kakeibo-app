import SwiftUI

/// アプリのルート。ホーム / レポート / 口座 / 設定 のタブ構成。
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "list.bullet.rectangle") }

            ReportsView()
                .tabItem { Label("レポート", systemImage: "chart.pie") }

            AccountsOverviewView()
                .tabItem { Label("口座", systemImage: "banknote") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(TxPalette.accent)
        .preferredColorScheme(store.settings.theme.colorScheme)
    }
}
