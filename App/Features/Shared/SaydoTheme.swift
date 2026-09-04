import SwiftUI

/// 画面デザインのトークン（`docs/design/design-notes.md`）。
///
/// ダーク固定・アクセント 1 色・書体 1 ファミリー。赤・警告色・達成マーク・連続日数は
/// 全画面で使わない（企画原則 §22-1 / §22-8）。各画面はここにある値だけを使い、
/// 色や文字サイズを画面ファイルに直書きしない。
enum SaydoTheme {

    // MARK: 色

    enum Palette {
        /// 背景の縦グラデーション（深い群青）。
        static let groundTop = Color(hex: 0x131E35)
        static let groundMid = Color(hex: 0x101A2E)
        static let groundBottom = Color(hex: 0x0C1424)
        /// 宣言カードなどの面。
        static let surfaceTop = Color(hex: 0x1B2842)
        static let surfaceBottom = Color(hex: 0x151F36)
        /// 枠線・区切り（rgba(255,255,255,.055–.10)）。
        static let hairline = Color.white.opacity(0.08)
        /// 朝の光。波形の芯・行動時刻・再生。
        static let accent = Color(hex: 0xEDA96F)
        /// 「逃げる理由」帯の 1〜4 段（単一色相・明度のみ変化）。
        static let accentRamp: [Color] = [
            Color(hex: 0xEDA96F), Color(hex: 0xC08A5C), Color(hex: 0x96694A), Color(hex: 0x6C4B38),
        ]
        /// 再生位置の縦線など、アクセントより明るい強調。
        static let accentHighlight = Color(hex: 0xF6C79E)
        /// 本文〜微小ラベル。ink3 = 5.6:1、ink4 = 4.3:1（装飾専用）。
        static let ink1 = Color(hex: 0xE8ECF4)
        static let ink2 = Color(hex: 0xC3CDE0)
        static let ink3 = Color(hex: 0x8494B4)
        static let ink4 = Color(hex: 0x6B7EA6)
        /// 未再生の波形・静かな線。
        static let waveformIdle = Color(hex: 0x6E7FA6)
        /// 横長の帯として敷く光（球体状の光は禁止）。
        static let glow = Color(hex: 0xEDA96F).opacity(0.14)
        /// チップの塗り（高さ 46・角丸 15）。
        static let chipFill = Color.white.opacity(0.045)
    }

    /// 背景。全画面で `ignoresSafeArea()` して敷く。
    static var ground: LinearGradient {
        LinearGradient(
            colors: [Palette.groundTop, Palette.groundMid, Palette.groundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 宣言カードの面（168deg 相当）。
    static var surface: LinearGradient {
        LinearGradient(
            colors: [Palette.surfaceTop, Palette.surfaceBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: 寸法

    enum Metric {
        static let chipHeight: CGFloat = 46
        static let chipCornerRadius: CGFloat = 15
        static let primaryButtonHeight: CGFloat = 64
        static let keyboardButtonSize: CGFloat = 44
        static let cardCornerRadius: CGFloat = 22
    }

    // MARK: 文字（1 ファミリー。weight・size・字間・行間だけで階層を作る）

    /// design-notes の size / weight / letter-spacing / line-height を、Dynamic Type に追従する
    /// text style を土台に写したもの。字間は em を pt に換算した値、行間は追加分。
    enum TextRole {
        /// 質問 28 / 500 / .02em / 1.5
        case question
        /// 前置き（N0 の「朝のあなたからです。」）22 / 400 / .06em
        case preface
        /// 画面タイトル 20 / 500 / .04em
        case screenTitle
        /// 宣言本文 17 / 400 / 1.9
        case declaration
        /// 振り返り 1 文 16 / 400 / 2.0
        case reflection
        /// リスト・チップ 15–16 / 400 / 1.75
        case list
        /// 状態行 14 / 400 / .20em
        case status
        /// 時刻・日付 12–13 + tabular-nums
        case time
        /// セクションラベル 11 / 500 / .24em
        case sectionLabel
        /// ロゴ SAYDO 11 / 500 / .38em / ink4
        case logo

        var font: Font {
            switch self {
            case .question: .title.weight(.medium)
            case .preface: .title2
            case .screenTitle: .title3.weight(.medium)
            case .declaration: .body
            case .reflection, .list: .callout
            case .status: .footnote
            case .time: .caption.monospacedDigit()
            case .sectionLabel, .logo: .caption2.weight(.medium)
            }
        }

        var tracking: CGFloat {
            switch self {
            case .question: 0.56
            case .preface: 1.32
            case .screenTitle: 0.8
            case .declaration, .reflection, .list, .time: 0
            case .status: 2.8
            case .sectionLabel: 2.64
            case .logo: 4.18
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .question: 8
            case .preface: 6
            case .screenTitle, .status, .time, .sectionLabel, .logo: 0
            case .declaration: 10
            case .reflection: 11
            case .list: 7
            }
        }

        var color: Color {
            switch self {
            case .question, .screenTitle, .declaration, .reflection: Palette.ink1
            case .preface, .list: Palette.ink2
            case .status, .time: Palette.ink3
            case .sectionLabel, .logo: Palette.ink4
            }
        }
    }
}

extension Color {
    /// `0xRRGGBB` から sRGB の色を作る。
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

private struct SaydoTextStyle: ViewModifier {
    let role: SaydoTheme.TextRole

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
            .foregroundStyle(role.color)
    }
}

extension View {
    /// design-notes の文字階層を当てる。`Text("…").saydoText(.question)` のように使う。
    func saydoText(_ role: SaydoTheme.TextRole) -> some View {
        modifier(SaydoTextStyle(role: role))
    }

    /// 全画面の背景。`ZStack` の最背面に置く。
    func saydoGround() -> some View {
        background(SaydoTheme.ground.ignoresSafeArea())
    }
}
