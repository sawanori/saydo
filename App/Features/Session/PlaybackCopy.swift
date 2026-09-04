import Foundation

/// 昼 N0（朝の宣言を本人に返す画面）だけで使う文言。
///
/// 会話の発話は `DialogueCopy` が持つ。ここにあるのはボタンの言葉だけで、
/// 読み上げには使わない。責める語は置かない（企画原則 §22-1）。
enum PlaybackCopy {
    /// 宣言音声をそのまま鳴らす。
    static let listenAloud = "聞く"
    /// 受話口に切り替えて鳴らす（近接センサー併用）。
    static let listenAtEar = "耳に当てて聞く"
    /// 再生前の確認（retention R8）: イヤホンをつないで聞く。
    static let listenWithEarphones = "イヤホンで聞く"
    /// 再生前の確認（retention R8）: 音を出さず、宣言テキストを読む。
    static let readAsText = "文字で読む"
}
