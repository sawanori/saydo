import Foundation
import OSLog
import SaydoCore

/// 文言バリエーションの使用履歴（retention R5「3 日以内に同じ文言を繰り返さない」）の保存先。
///
/// `CopyPicker` は履歴を渡されて初めて重複を避けられる。履歴がセッションの中だけで消えると
/// 朝・昼・夜をまたいだ日に必ず同じ言い換えが出るので、端末に残す（統合判断 D2）。
/// `AppSettings` には入れない（task_013 が同じファイルを触るため）。
@MainActor
protocol CopyHistoryStoring: Sendable {
    /// 保存済みの履歴。`currentDay` から数えて 3 日より古い記録は捨てて返す。
    func load(currentDay: Int) -> [CopyPicker.Use]
    /// 履歴を丸ごと書き直す。`load` で刈り込んだ後の配列に積むので、際限なく増えない。
    func save(_ uses: [CopyPicker.Use])
}

/// `UserDefaults` に JSON で置く実装。
///
/// `@MainActor` にしているのは `UserDefaults` が iOS 26.2 SDK で明示的に非 Sendable だから
/// （`AppSettings` と同じ理由）。検査を外す属性で警告を黙らせず、隔離で解決する。
@MainActor
final class UserDefaultsCopyHistoryStore: CopyHistoryStoring {

    private static let key = "saydo.dialogue.copyHistory"
    private static let logger = Logger(subsystem: "com.nonturn.saydo", category: "copyHistory")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(currentDay: Int) -> [CopyPicker.Use] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        do {
            let stored = try JSONDecoder().decode([CopyPicker.Use].self, from: data)
            return Self.pruned(stored, currentDay: currentDay)
        } catch {
            // 読めない履歴は捨てる。文言が 1 回重なるだけで、会話は止めない。
            Self.logger.error("copy history unreadable: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.key)
            return []
        }
    }

    func save(_ uses: [CopyPicker.Use]) {
        guard !uses.isEmpty else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(uses), forKey: Self.key)
        } catch {
            Self.logger.error("copy history not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 3 日より古い記録を落とす。`CopyPicker` の判定境界と同じ式を使う。
    static func pruned(_ uses: [CopyPicker.Use], currentDay: Int) -> [CopyPicker.Use] {
        let horizon = currentDay - DialogueCopy.repeatAvoidanceDays
        return uses.filter { $0.day >= horizon }
    }
}
