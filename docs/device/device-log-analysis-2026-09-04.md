# 実機ログ解析（2026-09-04、初回インストール版 = 60bf18c より前のビルド）

対象: `build/devicelogs/syslog-1.txt`（14:41〜14:56）と `syslog-2.txt`（14:48〜15:08）。リポジトリ外。
抽出方法: `grep -aE " Saydo(\([A-Za-z.]+\))?\[[0-9]+\]"` で Saydo プロセスの行だけを取り、
`Saydo(TextToSpeech)` の `Will speak` / `Speech finished`、`Saydo(AudioToolbox)` の
`AURemoteIO: constructing`（= AVAudioEngine 入力の開始）と `Stopping AURemoteIO` の連続 3 行（= 停止）、
`Saydo(AudioSession)` の `Activated session` を時系列に並べた。

## 1. プロセス

| pid | 起動 | 内容 |
|---|---|---|
| 17377 | 14:41:24 | 初回起動。オンボーディング → 朝フロー（14:42:08〜14:43:12）。当日の Commitment が作られた |
| 17422 | 14:48:51 | 2 回目の起動。14:51:25〜33 に録音の再生を 6 回。15:00:36 に adhoc セッション「16:00の約束、まだ生きてる？」 |

## 2. 朝フローの時系列（pid 17377）

TTS は全て正常に鳴っている（`Speech finished: 1 (null)`、各 2.1〜6.1 秒）。
「読み上げが 0.2 秒未満」という前セッションの所見は誤りで、正しくは
**「聞き取りが読み上げと同時に始まっている」**。

| # | 読み上げ（Will speak → finished） | 聞き取り（engine 起動 → 停止） | 長さ | 読み上げと重なる | 結果 |
|---|---|---|---|---|---|
| T1 | 14:42:09.4 → 11.96（最初の問いかけ） | 12.07 → 16.40 | 4.3 s | **重ならない** | 認識あり → チップ提示 |
| T2 | 16.58 → 18.65「いちばんしっくりくるのはどれ？」 | 16.62 → 20.46 | 3.8 s | 重なる（TTS 開始 30 ms 後に起動） | 空 → 再質問が予約される |
| T3 | 19.17 → 22.02「最初の5分だけなら、何ができる？」 | 20.60 → 29.72 | 9.1 s | 重なる | 22.02〜24.30 に「もう一度、ゆっくりで大丈夫。」が挿入される（聞き取り中） |
| T4 | 29.84 → 31.77「何時に、どこでやろうか？」 | 29.87 → 49.98 | 20.1 s | 重なる | 認識あり（上限 20 秒で終了した可能性） |
| T5 | 50.10 → 54.38「最後にひとつ。今日やることを、自分の声で言ってみて。」 | 50.13 → 54.08 | 3.9 s | **聞き取り全体が読み上げの中** | 空 → 54.39〜56.69「もう一度、ゆっくりで大丈夫。」 |
| T6 | （上の再質問の間） | 54.21 → 14:43:05.63 | 11.4 s | 前半が重なる | 認識あり → 14:43:05.74「受け取りました。16時から 16時から。に、朝のあなたから届きます。」 |

観測される定数（実測値、コードは要確認）: 無音での打ち切り ≈ 3.8〜4.3 秒、聞き取りの上限 ≈ 20 秒。

## 3. 解釈

1. **T1 だけは読み上げを待ってから聞き取りが始まる**。T2 以降は「Will speak」の 30 ms 後に engine が起動しており、読み上げの完了を待っていない。
2. 無音打ち切りが約 4 秒なので、4 秒を超える問いかけ（T5 は 4.3 秒）は**本人が話す前に聞き取りが終わり**「もう一度、ゆっくりで大丈夫。」が出る。本人には「言い終わる前に聞き直された」ように聞こえる。
3. T2 → T3 では、チップ提示中の聞き取り（T2）が走ったまま次の問いかけ（T3）が始まり、T2 の空結果に対する再質問が T3 の読み上げの直後に挿入されている。段階が進んだ後の古い聞き取り結果が再質問を出している可能性がある（コードで確認）。
4. 最後の読み上げ「16時から 16時から。に、朝のあなたから届きます。」は文言の組み立て不良（時刻句の二重化と句点直後の「に」）。DialogueCopy 側の要修正。
5. 2 回目の起動（pid 17422）では本人が 14:51:25〜33 に録音再生を 6 回連続で押している（AAC 48 kHz の AudioQueueNewOutput が 6 回、各 0.8〜4.4 秒で停止）。TTS はこの間 1 度も作られていない（`Synthesizer created` は 15:00:36 が最初）。再生される音声が短い・聞こえないと感じて押し直した可能性が高い。録音ファイルの長さは端末上でしか確認できない（未検証）。
6. 15:00:37〜41 の adhoc セッションの TTS（4.1 秒）は正常。

## 4. 前セッションの所見の訂正

- 「聞き取り区間が 4〜20 秒 × 6 回連続で始まり直し」→ 6 回の聞き取りは各段階 1 回ずつで、始まり直しではない。問題は読み上げとの同時進行。
- 「間の読み上げが 0.2 秒未満（鳴っていない疑い）」→ 全て 2 秒以上鳴っている。0.2 秒は読み上げ開始から聞き取り開始までの間隔。

## 5. 未検証

- 上記の各段階に対応するコードの箇所と定数（サブエージェントの調査結果を §6 に追記する）。
- 録音ファイルの実際の長さ、再生時に音が出ていたか。
- 再インストール版（60bf18c、OSLog 付き）のログは端末ロックで起動に失敗し未取得（`docs/logs/device-7-reinstall-clean.txt`）。

## 6. コードとの照合（integration eb157f5 時点）

### 6.1 実行経路は直列（設計どおり）
- `SessionViewModel.apply()` は `FlowTransition.commands` を順に `await run()` し、`.speak` は `synthesizer.speak` を await してから `.listen` に進む（App/Features/Session/SessionViewModel.swift:590-608, 645-688）。
- したがって §2 の「読み上げ開始 30 ms 後に聞き取り開始」は、**`SpeechSynthesisService.speak()` が発話完了を待たずに返っている**ことを意味する（T2・T4・T5 は他の経路と重ならない単独の遷移で、いずれも 30 ms 台）。

### 6.2 `speak()` が早く返り得る構造（App/Audio/SpeechSynthesisService.swift:120-161, 56-85）
- 完了待ちは `AsyncStream` で、`SynthesizerDelegate` が `didFinish` / `didCancel` を受けると **どの utterance の通知かを確認せずに** `finish()` する（:70-84）。
- `speak()` は呼び出しごとに `synthesizer.delegate` を差し替え、`isSpeaking` の確認や直列化をしない（:126-128）。発話中に再度呼ばれると、前の待ち手は永遠に返らず、後の待ち手は前の utterance の `didFinish` で返る。
- `didStart` が来ないまま終わった場合も error ログを出すだけで再試行しない（:157-160）。
- 各 `Will speak` と同時刻に `Activated session` が出ている（`applyOutputRoute` → セッション有効化。:123）。T1 だけ有効化から AudioQueue 開始まで 1.0 秒かかり、T2 以降は 50 ms 以内。T1 は正しく待てて T2 以降が待てない差の候補だが、**OS 側でどの通知が即時に届いているかは静的には決められない**。
- **決め手になるログ**（60bf18c の OSLog 付きビルド）: `category=tts` の `utterance chars=… end=finished|cancelled elapsed=…`。T2 相当の行で `elapsed` が 0.1 秒未満なら早期通知が確定。`category=session` の `speak done … elapsed=` と `listen begin …` の順序も同時に見る。

### 6.3 チップ選択が進行中の聞き取りを止めない（第 2 の不具合、静的に確認済み）
- `select()` は `cancelSilenceWatch()` と `handle(.choice)` だけで `stopListening()` を呼ばない（SessionViewModel.swift:492-497）。`skip()` も同様（:500-503）。
- M1 はチップ提示と聞き取りを同時に行うので、タップで段階が進んだ後に古い聞き取りが無音で終わると、`finishListening` → `handle(.transcript(""))` が **次の段階に** 届き、`FlowMachine.retryOrFallback` が「もう一度、ゆっくりで大丈夫。」を出す（Packages/SaydoCore/.../FlowMachine.swift:630-645、`isUsable` は 2 文字未満を不可 :648-650）。§2 の T2 → T3 はこの経路。
- `finishListening` にも二重起動のガードは無い（:782-794）。

### 6.4 聞き取りの終了条件（実測 ≈ 4 秒の正体）
- `SilenceDetector(duration: .standard)` = 発話（RMS > 0.015）を聞いた後の無音 1.5 秒で終了、発話前の無音は数えない（App/Audio/SilenceDetector.swift:4-8, 27, 47）。
- 沈黙の見張りは 5 秒（催促後 10 秒、FlowMachine.swift:449-451）、録音上限は `VoiceCaptureLimit.utterance` 20 秒 / `.declaration` 30 秒（App/Audio/VoiceCapture.swift:12-22）。T4 の 20.1 秒は上限で切れている。
- T2・T5 が 3.8〜3.9 秒で「空」で終わったのは、見張りの 5 秒より短い。**本体の読み上げがマイクに入り検出器が「発話あり」と判定し、読み上げの切れ目 1.5 秒で終了した**と考えると辻褄が合う（推定。`listen end reason=silence … peakRMS=` のログで確認できる）。同じ理由で transcript に本体の声が混ざり得る。
- 設定画面の `silenceThresholdSeconds`（1.2 / 1.5 / 2.0）は ViewModel に配線されておらず `.standard` 固定（AppSettings.swift:180-192、SessionViewModel.swift:301, 698）。

### 6.5 文言の二重化
- `morningDeclarationReceipt` の `{{time}}` に、M4「何時に、どこでやろうか？」への**生の発話** `plannedAnswer` をそのまま入れている（MorningFlow.swift:362-364、DialogueCopy.swift:211, 318）。「16時から 16時から。」は発話（または本体の声の混入）がそのまま入った結果で、末尾の句点と「から」+「に」の衝突は正規化が無いため。

### 6.6 プッシュ・トゥ・トークにした場合の影響範囲（サブエージェント調査、未実装）
- `SessionView` にマイクボタンは無く、聞き取りは TTS 後に自動開始（SessionView.swift:41-59, 256-296）。
- 変更は `SessionViewModel`（`beginListening` を「待機」に分け `pressToTalk()` / `releaseToTalk()` を追加、`observe()` の自動停止を外す、`SessionPhase` に待機を 1 つ追加。80〜120 行）と `SessionView`（押下中だけ有効な大ボタン、40〜60 行）。明示停止の経路は `capture.stop()` → `TranscriptionService.finish()`（`finalizeAndFinishThroughEndOfInput`）として既にある。
- `SilenceDetector` / `VoiceCapture` / `FlowMachine`（SaydoCore）は変更不要。`Tests/SaydoTests/SessionViewModelTests.swift` の `MockVoiceCapture` 依存テスト（約 7 件）は press/release 呼び出しへ変更。合計 5〜6 ファイル、250〜350 行。
- 3 秒以内の反応には `prepareTranscriber()`（毎回 `SpeechTranscriber` と `SpeechAnalyzer` を再生成、TranscriptionService.swift:76-113, 149-152）をセッション開始時 1 回に寄せる改修が併せて必要。
- 既存の `ListenMode` / `ListenModeSheet` は出力経路（スピーカー / 受話口 / 文字）の選択で、入力方式ではない。自動 / 押して話すの切替を置くなら `AppSettings` と `SettingsView.voiceSection`（SettingsView.swift:177-205）。

## 7. 結論

1. 「使い方が分からない」の主因は、2 回目以降の読み上げと同時に聞き取りが始まり、本体の声で検出器が終わって「もう一度、ゆっくりで大丈夫。」が本人の発話前に出ること（6.1〜6.4）。
2. 修正は 2 段: (a) `SpeechSynthesisService.speak()` を utterance 単位で待つ（`didFinish(utterance)` の同一性確認、発話中の再入は直列化）、(b) `select()` / `skip()` で `stopListening()` を呼び、`finishListening` に段階の一致ガードを入れる。
3. プッシュ・トゥ・トークは (a)(b) の代替ではなく、本人が話す区間を本人が決められるようにする UX 側の対策。無音打ち切りと本体の声の混入を構造的に無くせるので、採用を推奨する。
4. 決め手のログ（6.2）は端末を接続・ロック解除した状態でしか取れない。
