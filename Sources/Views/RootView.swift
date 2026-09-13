import SwiftUI

/// アプリのルート。ホーム / 口座 / 履歴 / レポート / 設定 のタブ構成。
struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "list.bullet.rectangle") }

            AccountsOverviewView()
                .tabItem { Label("口座", systemImage: "banknote") }

            HistoryView()
                .tabItem { Label("履歴", systemImage: "calendar") }

            ReportsView()
                .tabItem { Label("レポート", systemImage: "chart.pie") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(TxPalette.accent)
        .preferredColorScheme(store.settings.theme.colorScheme)
    }
}
