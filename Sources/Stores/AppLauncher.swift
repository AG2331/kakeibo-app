import Foundation
import SwiftUI

/// 起動時に DB を開き、失敗したら理由を保持する。
/// 開けないまま空のデータで起動してしまわないよう、状態を明示的に分ける。
@MainActor
final class AppLauncher: ObservableObject {
    enum Phase {
        case ready(AppStore)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .failed("")

    init() { open() }

    func open() {
        do {
            phase = .ready(try AppStore.makeDefault())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 開けなかったファイルを退避し、新しいデータで開き直す。
    /// 退避したファイルは残すので、あとからバックアップとして復元できる。
    func startFresh() {
        if let path = try? AppStore.defaultDatabasePath(),
           FileManager.default.fileExists(atPath: path) {
            let stamp = Self.stampFormatter.string(from: Date())
            try? FileManager.default.moveItem(atPath: path, toPath: "\(path).broken-\(stamp)")
        }
        open()
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
