import Foundation

/// 画面に出す 1 文。文言はすべて `*Copy` に集約し、View と ViewModel に直書きしない。
///
/// `Guardrails` の形式規則をどれで検査するかを、文言といっしょに持つ。
public struct CopyLine: Sendable, Equatable, Hashable, Codable {
    /// 文言。
    public let text: String
    /// Guardrails の形式規則をどれで検査するか。
    public let form: Guardrails.Form

    public init(_ text: String, _ form: Guardrails.Form) {
        self.text = text
        self.form = form
    }
}
