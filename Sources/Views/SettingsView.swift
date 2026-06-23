import SwiftUI

/// 設定画面。管理画面への入口と、通貨/テーマ/月開始日の設定。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("管理") {
                NavigationLink {
                    CategoryListView()
                } label: {
                    Label("カテゴリ", systemImage: "tag")
                }
                NavigationLink {
                    RecurringListView()
                } label: {
                    Label("定期取引", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section("データ") {
                NavigationLink {
                    DataView()
                } label: {
                    Label("エクスポート・バックアップ", systemImage: "tray.and.arrow.up")
                }
            }

            Section("表示") {
                Picker(selection: Binding(
                    get: { store.settings.currency },
                    set: { store.setCurrency($0) }
                )) {
                    ForEach(Currency.allCases) { Text($0.label).tag($0) }
                } label: {
                    Label("通貨", systemImage: "yensign.circle")
                }

                Picker(selection: Binding(
                    get: { store.settings.theme },
                    set: { store.setTheme($0) }
                )) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                } label: {
                    Label("テーマ", systemImage: "circle.lefthalf.filled")
                }
            }

            Section {
                Picker(selection: Binding(
                    get: { store.settings.monthStartDay },
                    set: { store.setMonthStartDay($0) }
                )) {
                    ForEach(1...28, id: \.self) { day in
                        Text(day == 1 ? "1日（暦月）" : "\(day)日").tag(day)
                    }
                } label: {
                    Label("月の開始日", systemImage: "calendar")
                }
            } header: {
                Text("集計")
            } footer: {
                Text("給料日などを起点に月を区切れます。例: 25日にすると「25日〜翌24日」で集計します。")
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
