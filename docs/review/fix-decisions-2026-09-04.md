# 敵対的レビュー指摘に対する採否と修正指示（2026-09-04 / 判定: Fable 5.1）

表記: [採用] そのまま反映 / [修正採用] 内容を変えて反映 / [不採用] 理由付きで見送り。
ID は plan-review（P）と harness-review（H）の生指摘番号。

## A. 技術的事実の訂正（implementation-plan.md）

- P4.1 [修正採用] §7.3: `AnalyzerInputConverter` は iOS 26.2 SDK に無い前提で書く。「`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` の形式へ `AVAudioConverter` で変換し、`AnalyzerInput(buffer:)` を生成して `AsyncStream` に流す。iOS 27 以降で `AnalyzerInputConverter` が使える場合は差し替える」と書く。task_004 の implementation_steps でも同様に修正。
- P4.3 [採用] §9: `@Guide` に文字数制約は無い。「文字数・動詞終わり・疑問形は Guardrails の後段検査で強制し、`@Guide` は description と `.anyOf` / `.range` / `.count` のみに使う」と書き換える。
- P4.2 [採用] §9 エラー処理: `LanguageModelSession.GenerationError` の `guardrailViolation`・`refusal`・`exceededContextWindowSize`・`unsupportedLanguageOrLocale` を扱う。guardrailViolation / refusal はテンプレート置換して会話を続ける。存在が未確認の case 名は書かない。
- P4.4 [採用] §0.2 対応表・§7.2: Tier A 判定は `availability == .available` かつ `SystemLanguageModel.default.supportsLocale(Locale(identifier: "ja_JP"))` の両方（後者は task_003 で実在を確認し、無ければ日本語プロンプトの試行結果で代替）。
- P4.5 [採用] §7.4: 繰り返し `UNCalendarNotificationTrigger` では当日分のスキップができない。「毎回の起動時と宣言時に、今日から 7 日分を非繰り返しトリガーで再計画する（識別子 `morning-yyyyMMdd` 等）」に変更。
- P4.6 [採用] task_007 / §7.3: 「actor 化で通す」を削除。「`installTap` のクロージャは nonisolated。クロージャ内では `AsyncStream` の continuation に yield するだけにし、状態変更は @MainActor 側で行う」と明記。
- P4.7 [採用] task_021: 通知音は Linear PCM / IMA4 / µLaw / aLaw のみ。「IMA4 の .caf に変換」に修正。
- P4.8 / P3.8 [採用] §10 と §6-4: 32 kbps × 15 秒 ≒ 60 KB/件、1 日 5 件で約 300 KB、年間約 110 MB に訂正。「iCloud バックアップが無効な場合は音声が端末のみに残る」旨を設定画面とオンボーディングに表示する（task_013、task_019）。

## B. 企画原則との整合（implementation-plan.md §7.2 会話設計）

- P2.1 [採用] M1（理由の発話）と N1（状態の発話）も `VoiceEntry(kind: reason / status)` として保存する。§10 の kind 一覧はそのまま使える。
- P2.2 [採用] §7.6: `WeeklyStats` から「宣言の結果内訳」「平均縮小回数」を除き、LLM に渡すのは分野別件数と理由別割合のみ。結果内訳は設定画面の開発者向け節にだけ表示する（retention-strategy.md §4 と整合）。振り返り文の目的は「何から、なぜ逃げるか」の理解に限定する。
- P2.4 [修正採用] 夜 E0 の前進なし分岐: 文言を「今日はそういう日。明日、もっと小さくしよう。」にし、チップは「もっと小さくする / 明日に回す」の 2 つだけ。§9 の 6 選択肢は昼 N3（再縮小）と翌朝 M0 の引き継ぎ確認で使う。
- P2.5 [採用] 昼 N1「少しやった」は前進として扱う: 「それを今日の前進として残すね。」で終了（`outcome = partial`、N2 に進まない）。
- P2.6 / P5.1 / P5.2 [採用] 昼フローの入口を定義する:
  - 当日の Commitment が無い → 昼・夜の通知タップは「短縮版の朝フロー」（M0 → M2 → M4、理由は聞かない）を開く。
  - `outcome == done` 済み → 固定の昼通知と行動時刻通知を取り消す。手動起動時は「今日はもう動けてる。」で終了。
  - 現在時刻 < `plannedAt` → 「どうだった？」を出さない。固定の昼通知は送らず、行動時刻通知だけを送る。手動起動時は「◯時の約束、まだ生きてる？」（はい / 時間を変える）。
- P2.7 [修正採用] チップは M1（理由）・N1（状態）・E0 の前進なし分岐のみに出す。M0・M3・M4 はチップ無し。無音 5 秒で出すのは「10 秒で答えて」の一言だけで、キーボードは常時右下の小ボタンにとどめ自動表示しない。check_001 の「チップの任意タップは除く」は「M1 と N1 のチップ以外のタップがゼロ」に書き換える。
- P2.8 / P5.3 [採用] Tier B の M2 / N3 は自由発話から名詞を切り出さない。「最初の 5 分でできる、いちばん小さいことは？」と本人に言わせ、本人の言葉をそのまま行動文にする。例示チップは「開くだけ / 1 行だけ書く / 必要なものを机に置く / 相手の名前を検索する」の 4 つ（分野に依らない一般形）。`ShrinkLadder` は「一般形の段階表（開く → 一部だけ → 1 行だけ → 置くだけ）」に限定し、メール専用にしない。
- P2.3 [修正採用] マイク拒否時: テキストで完走はできるが、Commitment には「声なし」フラグを付け、昼 N0 は本人の宣言テキストを画面に大きく表示して「朝のあなたからです。」と読む（TTS で読み上げない。本人の言葉を本人に見せる）。同時に設定アプリへの導線を出す。
- P3.1 / P5.4 [採用] retention-strategy.md R1・R8 を §7.2 と §7.3 に取り込む: 「話せない時」モード（M0〜M3 を選択肢 + 短文入力で完走、M4 の宣言だけ後回しにでき 1 回だけ通知）。通知タップ時にイヤホン未接続かつ消音スイッチ ON なら、TTS と再生を始める前に「イヤホンで聞く / 文字で読む」を出す。AVAudioSession の設定表に「消音スイッチを尊重する（`.ambient` 相当の挙動は使わず、再生前に確認する）」を明記。
- P5.7 [採用] §7.5: 禁止語は単語の部分一致ではなく句パターン（「未達成」「N 日連続」「サボ」「怠け」「言い訳」「甘え」「なぜやらない」「また逃げ」）にし、生成文にのみ適用する。ユーザーの文字起こしには適用しない。「失敗」「ダメ」は「失敗です」「ダメです」など断定形のみ対象。
- P5.8 [採用] §7.2 タイムボックス: TTS 音声は enhanced/premium がインストール済みならそれを使い、無ければ既定音声で開始しつつオンボーディングでダウンロードを案内。沈黙は最大 5 秒で催促、さらに 10 秒でその質問をスキップして次へ。タイムボックス超過時は「続きは昼に聞くね」で保存して終了。
- P3.6 [採用] `FlowMachine` の入力イベントに `interrupted`（着信・Siri・経路変更）を追加し、途中状態を保存して再開可能にする。check に追加。
- retention-strategy.md R2〜R6・R9・R11 [採用] §7.2 / §7.4 / §8 に取り込む（既定通知 = 朝 + 行動時刻、通知アクション「今日は休む」、空白後の再入場文言、文言バリエーション 5 種、「特にない」分岐、3 件目でのインサイト、M3 は「何時に、どこで？」）。

## C. 計画の実行可能性（task-list.json）

- P1.1 [採用] task_001 の project.yml は「Saydo(iOS 26.0)・SaydoTests・SpeechSpike・fm-probe の 4 ターゲットをプレースホルダのソース付きで作成し、packages は書かない」。SaydoCore の登録は task_002、SaydoAI の登録は task_014 で行う。task_001 から「git init」を外し、「GitHub の sawanori/saydo に初回コミット済み」を前提にする。verify_commands は build-ios.sh と test-ios.sh。files_to_create に Tests/SaydoTests/SmokeTests.swift を追加。
- P1.2 [採用] task_001 に「App/Resources/Assets.xcassets（仮 AppIcon 1024px + AccentColor）」「project.yml の info に NSMicrophoneUsageDescription / UILaunchScreen / ITSAppUsesNonExemptEncryption=false」を追加。
- P1.3 [採用] task_008 の scope に「SessionLog の記録（開始・終了・完走・tier・lastStep）」を追加。
- P1.4 [採用] AppSettings（UserDefaults の既定値: 時刻 8:00/13:00/21:00、無音 1.5 秒、音声 ID）は task_006 で作成し、task_013 は UI のみ。
- P1.5 [採用] task_005 を 2 分割: task_005（Flow 3 種 + FlowMachine + DialogueCopy + Guardrails + テスト）と task_005b（TemplateDialogueEngine + ShrinkLadder + JapaneseTimeParser + テスト。依存 task_005）。task_013 を 2 分割: task_013（Onboarding + Settings + AppSettings UI）と task_013b（TestFlight 内部配布と docs/dogfood/week1.md 作成。人間の作業を含む）。既存の dependencies で task_005 / task_013 を参照している箇所は、必要に応じて task_005b / task_013b に付け替える（task_008 は 005b に、task_014 は 005 に、task_015 は 013b に依存）。
- P1.6 [採用] scripts/build-ios.sh と test-ios.sh はスキーム引数を取る（既定 Saydo）。scripts/build-mac.sh（fm-probe 用）を task_001 で追加。task_003 の verify_commands は build-mac.sh fm-probe、task_004 は build-ios.sh SpeechSpike。
- P1.7 [修正採用] implementation-plan.md §11 の表に「担当タスク」列を追加し、task-list.json の files_to_create と一致させる（Opus 側で両方を突き合わせて修正）。
- P1.8 [採用] task_008 done_definition[0] を「通知タップまたは起動から 1.5 秒以内に TTS が開始され、ユーザーのタップ 0 回で M4 まで到達する（画面録画で確認）」に、task_012 の「滑らか」を「7 日分 30 件のデータで一覧のスクロール時にフレーム落ちの警告が Instruments で 0 件」に、check_011 は測定方法を「画面録画のフレーム数」に統一、check_025 は「`-warnings-as-errors` 相当で concurrency 警告 0 件（grep -c "warning:" の結果を記録）」にする。
- P3.2 [採用] task_016 の dependencies を task_013b（Tier B 経路で成立）にし、task_015 は「あれば使う」。task_017 は S-A が No-Go の場合スキップ可（optional: true）。
- P5.5 [採用] 早期 TestFlight を追加: task_010 の完了時点で「TestFlight 内部配布 #1（本人のみ、オンボーディングは権限要求のみ）」を task_010 の scope と done_definition に入れる。task_013b が配布 #2。
- P5.6 [採用] スパイクの数値基準を task_003 / task_004 の done_definition と §0.4 に入れる: S-A = 20 件中 16 件以上が採用可、禁止句 0 件、1 呼び出し p50 4 秒以内。S-B = 10 文中 8 文が意味の通る文字起こし、無音停止の誤作動 10 回中 1 回以下、通知タップ → TTS 開始 1.5 秒以内（5 回中 4 回）。
- P3.3 [採用] §0.3: 合計を 7〜8 週に改め、Phase 3 に「外部 TestFlight 審査待ち（1〜2 日）と App Review（1〜3 日、リジェクト 1 回分の再提出）」「実機の確保（Apple Intelligence 対応機が無い場合の購入判断）」を明記。
- P3.4 [採用] task_020 に「プライバシーポリシー URL（non-turn.com 配下の静的ページ、録音は端末内のみと明記）」「非対応機での機能差（Tier B）の説明文」「マイク自動開始の仕様: 通知タップ経由または本人がセッションを開始した時のみ、質問の読み上げ後に開始し、聞き取り中は波形で常時表示」を追加。
- P3.5 [採用] task_009 に「起動ごとに通知許可状態と pending 一覧を確認し、拒否・失効時は Today 画面に再許可の導線を出す」「行動時刻通知は Time Sensitive エンタイトルメントを追加して `.timeSensitive` にする」を追加（non_scope から Time Sensitive を外す）。
- P3.7 [採用] §0.1 と §6-1: 「Apple Intelligence 対応機は iPhone 15 Pro 以降に限られ、iOS 26 対応機の過半が Tier B になる前提で Tier B を主戦場として設計する」と明記。
- H1.1 / H2.1 [採用] task_001 の files_to_create に docs/PROGRESS.md、scripts/lint-principles.sh（URLSession / import Network / @unchecked Sendable / nonisolated(unsafe) / Copy ファイル外の日本語リテラルを検出）、.claude/settings.json の任意フックを追加。.claude/workflows/{plan-review,task-review,copy-audit,phase-gate}.js は作成済みなので task_005 と task_013 に「copy-audit / phase-gate の実行と修正」を scope として追加する。
- H2.5 [採用] scripts/test-core.sh と test-ios.sh の末尾で lint-principles.sh を実行する（task_001）。check_016・check_025 は毎タスクの task-review で走る旨を acceptance-checks に書く。

## D. ハーネス設計（harness-design.md）

- H1.2 [採用] G1 の合格条件を check_001〜004・008〜013・015・024 に変更（005 はテンプレート文言のみ）。G2 に 005〜007・014 を置く。
- H1.3 [採用] §1 の「risk_level で決める」記述を削除（全実装 Opus）。
- H1.4 / H2.6 [採用] P0 は「task_001 が 4 ターゲットを先に作る」ことで project.yml の衝突を解消。P3 の task_019（復元テスト）はドッグフーディング 7 日間の後に行うと明記。worktree では `.xcodeproj` を再生成せず、project.yml を変えたタスクだけが main で `xcodegen generate` する。
- H1.5 [採用] G3 を「task_020 の外部テスト完了後、提出前」に修正。G2 の 90% を task_017 の done_definition に追加。
- H2.2 [採用] 同時セッションは「Executor 2 + Reviewer 1（短時間）」。人間の実機作業はセッションの合間に行う。
- H2.3 [採用] Fable の時間枠が 2 日以内に来ない場合、ゲートレビューは Opus で plan-review.js / phase-gate.js を実行して仮承認し、次の Fable 枠で再確認する。blocked タスクは investigator → verifier → solver（Opus）を 2 回試してから Fable に回す。
- H2.4 [採用] PROGRESS.md には「exit code + 末尾 30 行」だけを貼り、全文は docs/logs/<task_id>-<n>.txt に保存する。
- H1.6 / H2.5 [採用] copy-audit は task_005 完了直後から毎回の task-review に組み込む。

## E. 不採用

- 特になし（全指摘を採用または修正採用）。反証検証（Opus）で refuted となった項目は、この文書の末尾に追記して差し戻す。
