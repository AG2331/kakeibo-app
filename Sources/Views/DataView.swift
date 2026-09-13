import SwiftUI
import UniformTypeIdentifiers

/// データ入出力: CSVエクスポート・バックアップ・復元。
struct DataView: View {
    @EnvironmentObject private var store: AppStore
    @State private var csvURL: URL?
    @State private var showRestorePicker = false
    @State private var resultMessage: String?

    var body: some View {
        List {
            Section {
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("CSVをエクスポート", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label("CSVを準備中…", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("エクスポート")
            } footer: {
                Text("すべての取引を CSV ファイルとして書き出します。")
            }

            Section {
                ShareLink(item: store.backupFileURL) {
                    Label("バックアップを書き出す", systemImage: "externaldrive.badge.timemachine")
                }
                Button {
                    showRestorePicker = true
                } label: {
                    Label("バックアップから復元", systemImage: "arrow.uturn.backward")
                }
            } header: {
                Text("バックアップ")
            } footer: {
                Text("データベースファイル(.sqlite)を保存・復元します。復元すると現在のデータは置き換わります。")
            }
        }
        .navigationTitle("データ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            csvURL = store.makeCSVFile()
        }
        .fileImporter(
            isPresented: $showRestorePicker,
            allowedContentTypes: [UTType(filenameExtension: "sqlite") ?? .data, .database],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                resultMessage = store.restore(from: url).message
            case .failure(let error):
                resultMessage = "読み込みに失敗しました: \(error.localizedDescription)"
            }
        }
        .alert("復元", isPresented: .constant(resultMessage != nil)) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }
}
