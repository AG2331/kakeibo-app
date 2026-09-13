import Foundation
import XCTest
@testable import Kakeibo

/// テスト用の一時DB。テストごとに独立したファイルを使う。
/// （restore など dbPath を見る処理があるため :memory: ではなくファイルで作る）
final class TempDatabase {
    let path: String
    private(set) var db: Database

    init(migrate: Bool = true) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kakeibo-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("kakeibo.sqlite").path
        db = try Database(path: path, migrate: migrate)
    }

    deinit {
        db.closeConnection()
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }
}

extension XCTestCase {
    /// 一時ディレクトリにファイルを作る（バックアップ復元テスト用）。
    func makeTempFile(name: String, contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kakeibo-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }

    /// 一時ディレクトリのパスを用意する（中身は呼び出し側で作る）。
    func makeTempPath(name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kakeibo-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent(name).path
    }
}

/// テスト用のカレンダー（タイムゾーン差で落ちないよう固定する）。
let testCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    return cal
}()
