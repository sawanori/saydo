import Foundation
import FoundationModels

/// Tier A / Tier B の判定（実装計画 §0.2 対応表・§7.2、fix-decisions P4.4）。
///
/// Tier A と見なすのは
/// `SystemLanguageModel.default.availability == .available` **かつ**
/// `SystemLanguageModel.default.supportsLocale(Locale(identifier: "ja_JP"))` が真のとき **だけ**。
/// どちらか一方でも欠ければ Tier B（テンプレート）で動かす。
///
/// 両 API とも macOS 26.2 SDK の `FoundationModels.swiftinterface` に実在し、
/// 本パッケージのビルドとテストで実際にコンパイル・実行できている。
public enum ModelAvailability {

    /// Tier B に落ちた理由。判定理由のログに使う。
    public enum TierBReason: Sendable, Equatable {
        /// この端末は Apple Intelligence 非対応。
        case deviceNotEligible
        /// 設定で Apple Intelligence が無効。
        case appleIntelligenceNotEnabled
        /// モデルのダウンロード・準備が未完了。
        case modelNotReady
        /// 将来の SDK で増えた理由。
        case unknownUnavailable(String)
        /// モデルは使えるが、この言語に対応していない。
        case localeNotSupported(String)

        /// ログ用の説明。利用者には見せない。
        public var logDescription: String {
            switch self {
            case .deviceNotEligible:
                "deviceNotEligible"
            case .appleIntelligenceNotEnabled:
                "appleIntelligenceNotEnabled"
            case .modelNotReady:
                "modelNotReady"
            case .unknownUnavailable(let raw):
                "unknownUnavailable(\(raw))"
            case .localeNotSupported(let identifier):
                "localeNotSupported(\(identifier))"
            }
        }
    }

    /// 判定結果。
    public enum Verdict: Sendable, Equatable {
        /// オンデバイス LLM を使う。
        case tierA
        /// テンプレートで動かす。
        case tierB(TierBReason)

        public var isTierA: Bool {
            self == .tierA
        }

        /// ログ用の説明。利用者には見せない。
        public var logDescription: String {
            switch self {
            case .tierA: "tierA"
            case .tierB(let reason): "tierB(\(reason.logDescription))"
            }
        }
    }

    /// 会話で使う言語。
    public static let japanese = Locale(identifier: "ja_JP")

    /// Tier を判定する。
    ///
    /// - Parameters:
    ///   - model: 判定対象。既定は `SystemLanguageModel.default`。
    ///   - locale: 対応を確かめる言語。既定は `ja_JP`。
    public static func evaluate(
        model: SystemLanguageModel = .default,
        locale: Locale = japanese
    ) -> Verdict {
        switch model.availability {
        case .available:
            guard model.supportsLocale(locale) else {
                return .tierB(.localeNotSupported(locale.identifier))
            }
            return .tierA

        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .tierB(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .tierB(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .tierB(.modelNotReady)
            @unknown default:
                return .tierB(.unknownUnavailable(String(describing: reason)))
            }

        @unknown default:
            return .tierB(.unknownUnavailable(String(describing: model.availability)))
        }
    }

    /// 判定理由のログ 1 行。`SessionLog.tier` の記録と開発者向け表示に使う。
    public static func log(
        model: SystemLanguageModel = .default,
        locale: Locale = japanese
    ) -> String {
        let verdict = evaluate(model: model, locale: locale)
        return "SaydoAI tier=\(verdict.logDescription) locale=\(locale.identifier) supported=\(model.supportsLocale(locale))"
    }
}
