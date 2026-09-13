import SwiftUI

/// データベースを開けずアプリを起動できないときの画面。
/// 何が起きたかを伝え、復旧の手段を示す（黙って空のデータで起動しない）。
struct StartupFailureView: View {
    let message: String
    let retry: () -> Void
    let startFresh: () -> Void

    @State private var confirmFresh = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(TxPalette.expense)

            VStack(spacing: 8) {
                Text("データを開けませんでした")
                    .font(.title3.bold())
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("もう一度試す", action: retry)
                    .buttonStyle(.borderedProminent)
                Button("新しいデータで開始") { confirmFresh = true }
                    .buttonStyle(.bordered)
            }

            Text("「新しいデータで開始」を選んでも、開けなかったファイルは端末内に残します。"
                 + "起動できたあとに 設定 → エクスポート・バックアップ からバックアップを復元できます。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .confirmationDialog("新しいデータで開始しますか？", isPresented: $confirmFresh,
                            titleVisibility: .visible) {
            Button("新しいデータで開始", role: .destructive, action: startFresh)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("空の状態でアプリを開き直します。開けなかったファイルは残したままにします。")
        }
    }
}
