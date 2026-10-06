import AppIntents
import Foundation

/// アラームの「開く」から答える画面へ進むための受け口（実装計画 §17.3「答える」）。
///
/// `OpenFollowUpIntent` はアプリ本体のプロセスで走る。コールドスタートでは画面より先に走ることが
/// あるので、合図を 1 件だけ持っておき、画面側が準備できた時点で `consume()` で引き取る。
/// すでに画面が出ているときのために、同時に `didRequest` も通知する。
///
/// 使い方（配線は task_056）:
/// - 起動時と前面に戻ったとき: `if FollowUpOpenRequest.consume() { 答える画面を出す }`
/// - 起動中: `NotificationCenter.default.notifications(named: FollowUpOpenRequest.didRequest)` を待ち、
///   届いたら `consume()` して答える画面を出す。
@MainActor
enum FollowUpOpenRequest {
    /// 「開く」が押されたときに `NotificationCenter.default` へ流す通知の名前。
    nonisolated static let didRequest = Notification.Name("com.nonturn.saydo.followUp.openRequested")

    private static var pending = false

    /// まだ引き取られていない合図があるか。
    static var isPending: Bool { pending }

    /// 「開く」が押された。合図を立てて通知する。
    static func post() {
        pending = true
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    /// 合図を引き取る。あれば true を返して下ろす。
    @discardableResult
    static func consume() -> Bool {
        defer { pending = false }
        return pending
    }
}

/// アラームの「開く」。アプリを前面に出すだけで、**連鎖は取り消さない**
/// （取り消すのは、答える画面で 3 つのどれかを押したときだけ。実装計画 §17.1-6）。
///
/// `supportedModes` は必ず `.foreground`（static var 形式）と書く。`.foreground(.immediate)` と書くと
/// メタデータ抽出が黙って `.background` と同じ値を書き出し、押してもアプリが前面に出ない
/// （docs/spikes/alarm-spike.md §3）。
///
/// `title` は AppIntents のメタデータ抽出が文字列リテラルを要求するので `PromiseCopy` から引けない。
/// アプリ名だけを置き、ショートカットの一覧には出さない（`isDiscoverable = false`）。
struct OpenFollowUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "SAYDO"
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await FollowUpOpenRequest.post()
        return .result()
    }
}
