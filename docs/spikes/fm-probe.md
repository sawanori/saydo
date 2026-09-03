# スパイク S-A / S-D: fm-probe（Foundation Models の日本語品質検証）

このファイルは `Spikes/fm-probe/main.swift` が生成する。手で編集するのは「人手採点」と「Go / No-Go」の欄だけにし、再実行するとそれ以外は上書きされる。

## 1. 実行環境

| 項目 | 値 |
|---|---|
| 実行日時 | 2026-09-04 07:15:30 (+09:00) |
| 所要（全体） | 782秒 |
| フィクスチャ | `/Users/noritakasawada/AI_P/SAYDO/.worktrees/task-003/Spikes/fm-probe/fixtures.json`（20 件 / version 1） |
| モデル呼び出し | 実行した |
| 1 呼び出しの上限時間 | 60 秒（超過は `timeout` として記録） |
| `GenerationOptions.maximumResponseTokens` | 既定（上限なし） |

ビルドと実行:

```
swiftc -O Spikes/fm-probe/main.swift -o /tmp/fm-probe && /tmp/fm-probe
```

## 2. availability と対応言語（S-D）

| 項目 | 実測値 |
|---|---|
| `SystemLanguageModel.default.availability` | `available` |
| `unavailable` の理由 | — |
| `supportsLocale(Locale(identifier: "ja_JP"))` | `true` |
| `supportedLanguages` に日本語 | あり（`ja-Jpan-JP`） |

`supportedLanguages`（23 件）: `da-Latn-DK`, `de-Latn-DE`, `en-Latn-AU`, `en-Latn-GB`, `en-Latn-US`, `es-Latn-419`, `es-Latn-ES`, `es-Latn-US`, `fr-Latn-CA`, `fr-Latn-FR`, `it-Latn-IT`, `ja-Jpan-JP`, `ko-Kore-KR`, `nb-Latn-NO`, `nl-Latn-NL`, `pt-Latn-BR`, `pt-Latn-PT`, `sv-Latn-SE`, `tr-Latn-TR`, `vi-Latn-VN`, `zh-Hans-CN`, `zh-Hant-HK`, `zh-Hant-TW`

## 3. コンパイルで実在を確認した API

以下は macOS 26.2 SDK（Xcode 26.2 / Swift 6.2.3）で実際にコンパイル・実行が通ったものだけを挙げる。

| API | 用途 |
|---|---|
| `SystemLanguageModel.default.availability` → `.available` / `.unavailable(UnavailableReason)` | Tier 判定 |
| `UnavailableReason`: `.deviceNotEligible` / `.appleIntelligenceNotEnabled` / `.modelNotReady` | 不可時の理由表示 |
| `SystemLanguageModel.supportsLocale(_ locale: Locale = .current) -> Bool` | 日本語対応判定（fix-decisions P4.4） |
| `SystemLanguageModel.supportedLanguages -> Set<Locale.Language>` | 対応言語の列挙 |
| `LanguageModelSession(model:tools:instructions: String?)` | ステップごとの新規セッション |
| `session.respond(to: String, generating: Content.Type, includeSchemaInPrompt:options:) -> Response<Content>` | 構造化生成 |
| `@Generable(description:)` / `@Guide(description:)` / `@Guide(description:_ guides:)` | スキーマ定義 |
| `GenerationGuide.range(_: ClosedRange<Int>)` / `.count(_: Int)` | 数値範囲・配列件数 |
| `LanguageModelSession.GenerationError`: `exceededContextWindowSize` / `assetsUnavailable` / `guardrailViolation` / `unsupportedGuide` / `unsupportedLanguageOrLocale` / `decodingFailure` / `rateLimited` / `concurrentRequests` / `refusal` | エラー処理（fix-decisions P4.2） |

補足: `@Guide` に文字数制約は無い（`GenerationGuide<String>` は `.constant` / `.anyOf` / `.pattern` のみ）。文字数・疑問形は後段の Guardrails 検査で強制する。実装計画 §9 の `@Guide 60 文字以内・40 文字以内` という記述はこの通りには書けない。

Apple 側のセーフティも観測できた。指示文を削って `入力の「逃げたいこと」を personReply, money, ... のどれか 1 つに分類します。` だけにして「確定申告」を投げると、25 回中 25 回とも `refusal`（`debugDescription: "May contain sensitive content"`）で拒否された。同じ入力でも本スパイクの伴走者向け指示文では拒否されない。**指示文の書き方でセーフティの発火が変わるため、プロンプトを変更したら必ずこのスパイクを再実行すること。**

## 4. 指示文（各 600 文字以内）

| 呼び出し | 文字数 |
|---|---|
| 理由分類 + 追加質問 | 351 |
| 行動 3 案 | 303 |
| 分野分類 | 192 |

## 5. 自動判定の規則

- 禁止句（生成文にのみ適用）: 「未達成」、「連続」、「サボ」、「怠け」、「言い訳」、「甘え」、「なぜやらない」、「また逃げ」
- 追加質問: 60 文字以内、かつ「？」で終わる
- 行動文: 40 文字以内、`estimatedMinutes` が 1〜5
- 「動詞で終わる」は形態素解析が要るため自動判定に含めない。人手採点で見る。

## 6. 理由分類と追加質問

| # | 逃げたいこと | 本人の答え | category | followUp | ms | 質問長 | ≤60 | ？終わり | 禁止句 | エラー |
|---|---|---|---|---|---|---|---|---|---|---|
| F01 | クライアントへの返信 | 怒られそうで怖いです。 | anxious（不安・怖い） | 怒られる前に、どんな気持ちで対応しようと考えていますか？ | 1282 | 28 | OK | OK | 0 | — |
| F02 | 上司へのSlackの返信 | 気まずいです。返事が遅れてしまって。 | awkward（気まずい） | 上司に返信する頻度はある？ | 605 | 13 | OK | OK | 0 | — |
| F03 | 取引先へのお詫びメール | 何て書けばいいか分からないです。 | — | — | 110467 | — | — | — | — | `exceededContextWindowSize` |
| F04 | 確定申告 | 量が多そうで、どこから手をつけるか分からないです。 | unclearStart（何から始めるかわからない） | 具体的に何から始めればいいか教えてください。 | 54757 | 22 | OK | NG | 0 | — |
| F05 | クレジットカードの明細のチェック | 数字を見るのが嫌です。 | — | — | 109784 | — | — | — | — | `exceededContextWindowSize` |
| F06 | 経費精算 | 面倒です。レシートを探すところからなので。 | tedious（面倒） | レシートはどれくらいありますか？ | 57312 | 16 | OK | OK | 0 | — |
| F07 | 新サービスの企画書づくり | 完璧に作りたくて、手が止まります。 | perfectionism（完璧にやりたい） | どんな基準で完璧に作るつもりですか？ | 59000 | 18 | OK | OK | 0 | — |
| F08 | サイトのリニューアル作業 | 量が多くて、終わる気がしないです。 | tooMuch（量が多い） | 毎日何時間を費やしていますか？ | 58928 | 15 | OK | OK | 0 | — |
| F09 | 引っ越しの荷造り | 何から始めればいいか分からないです。 | unclearStart（何から始めるかわからない） | まずは、どこから始めて良いかわからないですか？ | 674 | 23 | OK | OK | 0 | — |
| F10 | 新規のお客さんへの営業電話 | 断られるのが怖いです。 | anxious（不安・怖い） | そのとき、どんな気持ちになりますか？ | 56747 | 18 | OK | OK | 0 | — |
| F11 | 見積書 | 金額を決めるのが不安です。 | anxious（不安・怖い） | 具体的にどんな見積書ですか？ | 676 | 14 | OK | OK | 0 | — |
| F12 | 展示会で名刺交換した人へのフォロー連絡 | 今さら連絡するのは気まずいです。 | awkward（気まずい） | なぜ気まずいのか教えてほしいです。 | 811 | 17 | OK | NG | 0 | — |
| F13 | 契約書のリーガルチェック | 期限が近くて怖いです。 | — | — | 61163 | — | — | — | — | `timeout` |
| F14 | 保険の住所変更の手続き | 面倒です。 | — | — | 63434 | — | — | — | — | `timeout` |
| F15 | 業務委託の請求書を出すこと | 期限が怖いです。もう過ぎているので。 | deadlineFear（期限が怖い） | いつまでに提出したいですか？ | 60561 | 14 | OK | OK | 0 | — |
| F16 | 歯医者の予約 | 怖いです。長く行ってないので怒られそうで。 | anxious（不安・怖い） | 不安で歯医者に行くのが怖い？ | 655 | 14 | OK | OK | 0 | — |
| F17 | 健康診断の再検査 | 結果を知るのが不安です。 | anxious（不安・怖い） | 検査はいつですか？ | 519 | 9 | OK | OK | 0 | — |
| F18 | ジムに行くこと | 面倒です。 | tedious（面倒） | 時間がかかるの？ | 498 | 8 | OK | OK | 0 | — |
| F19 | 部屋の片づけ | 量が多くて、どこからやるか分からないです。 | unclearStart（何から始めるかわからない） | いつ始める？ | 575 | 6 | OK | OK | 0 | — |
| F20 | 免許の更新に行くこと | 面倒です。待ち時間が長いので。 | tedious（面倒） | 何時に行く予定ですか？ | 59409 | 11 | OK | OK | 0 | — |

## 7. 行動 3 案（5 分以下への細分化）

| # | 案 1 | 案 2 | 案 3 | ms | 最長文字数 | ≤40 | 分 1〜5 | 禁止句 | エラー |
|---|---|---|---|---|---|---|---|---|---|
| F01 | 画面を軽く押す（1分） | 深呼吸をする（1分） | 返信を始める（1分） | 799 | 7 | OK | OK | 0 | — |
| F02 | Slackを開く（2分） | 返信の件名を入力する（1分） | 返信を打つ（1分） | 822 | 10 | OK | OK | 0 | — |
| F03 | メールアドレス入力（1分） | 件名入力（1分） | メッセージ作成（2分） | 933 | 9 | OK | OK | 0 | — |
| F04 | 確定申告書を開く（2分） | 必要書類を机に置く（1分） | 確定申告の例を確認する（1分） | 893 | 11 | OK | OK | 0 | — |
| F05 | — | — | — | 224 | — | — | — | — | `guardrailViolation` |
| F06 | 経費明細を一つずつ確認する（1分） | 明細に数字を入れる（1分） | 明細を保存する（1分） | 1102 | 13 | OK | OK | 0 | — |
| F07 | スプレッドシートにタイトルを書く（1分） | ターゲット市場をリストアップする（2分） | サービスのメリットを記述する（2分） | 1123 | 16 | OK | OK | 0 | — |
| F08 | リストを10項目に区切る（1分） | 1つの項目に集中する（1分） | 作業を完了する（1分） | 1073 | 12 | OK | OK | 0 | — |
| F09 | 箱を分類する（1分） | 必要な書類をリストする（1分） | 荷造りを優先順位付ける（1分） | 887 | 11 | OK | OK | 0 | — |
| F10 | 呼吸をする（2分） | 短い休憩を取る（1分） | リストを確認する（2分） | 1041 | 8 | OK | OK | 0 | — |
| F11 | 見積書を印刷する（1分） | 印刷した見積書を机に置く（1分） | 見積書を机に置く（1分） | 1297 | 12 | OK | OK | 0 | — |
| F12 | 名前をスマホで検索する（1分） | メッセージを送る（1分） | すぐに返信する（1分） | 1093 | 11 | OK | OK | 0 | — |
| F13 | 契約書を開く（1分） | リーガルチェックをする（1分） | リーガルチェック結果を確認する（1分） | 1453 | 15 | OK | OK | 0 | — |
| F14 | 保険会社のウェブサイトにアクセスする（2分） | 住所変更の手続きを検索する（1分） | 必要書類を準備する（1分） | 1569 | 18 | OK | OK | 0 | — |
| F15 | 請求書の件名を確認する（2分） | 必要な書類を確認する（2分） | メールを開く（1分） | 991 | 11 | OK | OK | 0 | — |
| F16 | 歯医者の予約を調べる（2分） | 予約を予約するアプリを開く（1分） | 予約を完了する（1分） | 903 | 13 | OK | OK | 0 | — |
| F17 | スマホを確認する（1分） | 今日のスケジュールを確認する（1分） | 医師の予約を思い出そうとする（1分） | 1019 | 14 | OK | OK | 0 | — |
| F18 | 着替えをする（2分） | ジムに着く（1分） | トレーニングをする（3分） | 858 | 9 | OK | OK | 0 | — |
| F19 | 片付ける場所を決める（1分） | 片付ける順番を決める（1分） | 片付ける（2分） | 898 | 10 | OK | OK | 0 | — |
| F20 | 免許の更新日を確認する（2分） | 必要な書類を準備する（3分） | 服を着る（1分） | 937 | 11 | OK | OK | 0 | — |

## 8. 分野分類

`参考分類` は fixtures.json に人が付けた値であり、正解の断定ではない。判定の傾向を見るための参考。

| # | 逃げたいこと | 判定 | 参考分類 | 一致 | ms | エラー |
|---|---|---|---|---|---|---|
| F01 | クライアントへの返信 | personReply（人への返信） | personReply（人への返信） | OK | 202 | — |
| F02 | 上司へのSlackの返信 | personReply（人への返信） | personReply（人への返信） | OK | 199 | — |
| F03 | 取引先へのお詫びメール | personReply（人への返信） | personReply（人への返信） | OK | 204 | — |
| F04 | 確定申告 | money（お金） | money（お金） | OK | 203 | — |
| F05 | クレジットカードの明細のチェック | money（お金） | money（お金） | OK | 239 | — |
| F06 | 経費精算 | money（お金） | money（お金） | OK | 234 | — |
| F07 | 新サービスの企画書づくり | bigTask（大きなタスク） | bigTask（大きなタスク） | OK | 248 | — |
| F08 | サイトのリニューアル作業 | bigTask（大きなタスク） | bigTask（大きなタスク） | OK | 251 | — |
| F09 | 引っ越しの荷造り | bigTask（大きなタスク） | bigTask（大きなタスク） | OK | 246 | — |
| F10 | 新規のお客さんへの営業電話 | sales（営業） | sales（営業） | OK | 249 | — |
| F11 | 見積書 | money（お金） | sales（営業） | NG | 306 | — |
| F12 | 展示会で名刺交換した人へのフォロー連絡 | personReply（人への返信） | sales（営業） | NG | 270 | — |
| F13 | 契約書のリーガルチェック | bigTask（大きなタスク） | paperwork（書類） | NG | 371 | — |
| F14 | 保険の住所変更の手続き | paperwork（書類） | paperwork（書類） | OK | 325 | — |
| F15 | 業務委託の請求書を出すこと | paperwork（書類） | paperwork（書類） | OK | 239 | — |
| F16 | 歯医者の予約 | personReply（人への返信） | health（健康） | NG | 229 | — |
| F17 | 健康診断の再検査 | health（健康） | health（健康） | OK | 266 | — |
| F18 | ジムに行くこと | bigTask（大きなタスク） | health（健康） | NG | 234 | — |
| F19 | 部屋の片づけ | personReply（人への返信） | other（その他） | NG | 241 | — |
| F20 | 免許の更新に行くこと | bigTask（大きなタスク） | other（その他） | NG | 227 | — |

分野分類は最も速い（0.2 秒台）が、最も外れる。実装計画 §7.6 の Insight（「何から、なぜ逃げるか」の可視化）はこの分類の精度に直接乗るため、一致率が低い場合は Tier A でもキーワード辞書を先に当て、LLM は辞書で決まらないものだけに使う方が良い。

## 9. 集計

| 指標 | 値 |
|---|---|
| 呼び出し総数 | 60 |
| p50 | 811 ms |
| p90 | 59000 ms |
| 最大 | 110467 ms |
| 6 秒（アプリのタイムアウト）超過 | 11 / 60 |
| 禁止句を含んだ件数 | 0 |
| 自動判定 全項目合格 | 14 / 20 |
| 分野分類が参考分類と一致 | 13 / 20 |
| エラー `exceededContextWindowSize` | 2 |
| エラー `guardrailViolation` | 1 |
| エラー `timeout` | 2 |

### 9.1 追加質問の暴走（このスパイクで特定した最大の問題）と、その回避策

`ReasonClassification` は `category: ReasonCategory`（列挙）と `followUp: String`（自由文）を 1 つの `@Generable` 構造体にまとめた型で、実装計画 §9 の定義どおりである。この型を使うと、一定の割合でモデルが `followUp` を書き終えずに生成し続ける。上限を掛けないと約 53 秒かけて 4,096 トークンの文脈窓を使い切り、`exceededContextWindowSize` で失敗する。所要時間が 0.5 秒と 50 秒超に二極化するのはこれが原因で、スケジューリングの問題ではない。

2026-09-04 に同一プロンプト・同一型で反復して切り分けた結果:

| 条件 | 反復 | 成功 | 失敗の内容 | 失敗時の所要時間 |
|---|---|---|---|---|
| `maximumResponseTokens` 指定なし | 10 | 8 | `exceededContextWindowSize` | 53.6 秒 |
| `maximumResponseTokens: 100` | 14 | 9 | `decodingFailure`（JSON が途中で切れる） | 1.3〜2.1 秒 |
| `maximumResponseTokens: 200` | 16 | 8 | `decodingFailure` | 最大 3.6 秒 |
| `maximumResponseTokens: 320` | 16 | 8 | `decodingFailure` | 最大 5.4 秒 |
| `maximumResponseTokens: 512` | 16 | 10 | `decodingFailure` | 最大 6.6 秒 |

効かなかった手: `session.prewarm()`（30 回中 4 回が 46〜57 秒）、`__info_plist` を埋め込んだ ad-hoc 署名、`sampling: .greedy`（成功時の出力は毎回同一だったので、暴走しない回の生成は正常）。

`@Guide` の正規表現（`GenerationGuide<String>.pattern`）も試した。コンパイルは通り `#/.{1,40}？/#` なら 4 回中 4 回とも「？」で終わる正しい質問を返したが、1 回 117〜179 秒かかって実用にならない。文字クラスを使った `#/[^？]{1,59}？/#` `#/[^?]{1,40}\?/#` `#/[a-zA-Z ]{1,30}/#` はいずれも実行時に `GenerativeError Code=1020000` で全滅した（`GenerationError` のどの case にもならない NSError として返る）。fix-decisions P4.3 の「`@Guide` は description と `.anyOf` / `.range` / `.count` のみに使う」は正しい。

#### 効いた回避策: 呼び出しを 2 つに割る

`ReasonCategory` だけを生成する呼び出しと、追加質問を素の `String`（構造化なし）で生成する呼び出しに分けると、どちらも暴走しなくなる。同じ 4 入力 × 3 回で計測:

| 呼び出し | 反復 | 成功 | p50 | 最大 |
|---|---|---|---|---|
| `respond(to:generating: ReasonCategory.self)`（列挙のみ） | 12 | 12 | 207 ms | 819 ms |
| `respond(to:)` で追加質問を素の String（`maximumResponseTokens: 60`） | 12 | 12 | 772 ms | 1,427 ms |

暴走が起きるのは「列挙 + 自由文」を 1 つの `@Generable` 構造体にまとめた場合だけだった。ただし素の String で受けた追加質問は複数文・長文・疑問文でないものが混ざるため、後段の Guardrails での棄却率は上がる。

#### アプリへの含意

1. **実装計画 §9 の `ReasonClassification` を 2 呼び出しに分割する。** M1 の理由分類は `@Generable enum ReasonCategory` 単独で行い、追加質問は別の `respond(to:)` で取り、Guardrails を通す。分割後はどちらも 1 秒前後で安定する。
2. **`GenerationOptions(maximumResponseTokens:)` を必ず指定する。** 指定しないと 1 回の失敗に 53 秒かかる。§7.2 のタイムアウト 6 秒で打ち切れば体験は守れるが、打ち切った後もモデル側の生成は走り続ける。
3. **§9 の「`exceededContextWindowSize` は新しいセッションで 1 回だけ再試行」はこの暴走には効かない。** 同じ指示と入力で再試行すると同じ確率で再び暴走する。再試行 1 回で駄目ならテンプレートに落とす、と明記する必要がある。
4. **行動 3 案と分野分類は分割しなくてよい。** `MicroActionProposal`（`@Guide(.count(3))` の固定長配列）も `TaskDomain`（列挙）も暴走せず、上の表と §7・§8 のとおり 1 秒前後で安定して返る。

この実行の設定は §1 の表にある。`--max-response-tokens <n>` と `--timeout <秒>` で条件を変えて再計測できる。

### 9.2 自動判定で落ちた生成文

| # | 落ちた項目 | 生成文 |
|---|---|---|
| F03 | 追加質問: `exceededContextWindowSize` で結果なし | — |
| F04 | 追加質問: 「？」で終わっていない | 具体的に何から始めればいいか教えてください。 |
| F05 | 追加質問: `exceededContextWindowSize` で結果なし | — |
| F05 | 行動 3 案: `guardrailViolation` で結果なし | — |
| F12 | 追加質問: 「？」で終わっていない | なぜ気まずいのか教えてほしいです。 |
| F13 | 追加質問: `timeout` で結果なし | — |
| F14 | 追加質問: `timeout` で結果なし | — |

実装計画 §7.5 の後段検査（文字数・疑問形・禁止句）とテンプレート置換が無ければ、上の生成文はそのままユーザーに読み上げられる。この表が空でない限り、Tier A でも Guardrails は必須である。

## 10. 人手採点（空欄。人間が埋める）

判定は 3 段階。採用可 = そのままアプリの発話に使える / 要修正 = 文言調整で使える / 不可 = 使えない。
見る観点: 追加質問が責めていないか、行動が本当に 5 分以下か、行動文が動詞で終わっているか、日本語として自然か。

| # | 逃げたいこと | 追加質問 | 行動 3 案 | 分野分類 | 総合（採用可 / 要修正 / 不可） | メモ |
|---|---|---|---|---|---|---|
| F01 | クライアントへの返信 |  |  |  |  |  |
| F02 | 上司へのSlackの返信 |  |  |  |  |  |
| F03 | 取引先へのお詫びメール |  |  |  |  |  |
| F04 | 確定申告 |  |  |  |  |  |
| F05 | クレジットカードの明細のチェック |  |  |  |  |  |
| F06 | 経費精算 |  |  |  |  |  |
| F07 | 新サービスの企画書づくり |  |  |  |  |  |
| F08 | サイトのリニューアル作業 |  |  |  |  |  |
| F09 | 引っ越しの荷造り |  |  |  |  |  |
| F10 | 新規のお客さんへの営業電話 |  |  |  |  |  |
| F11 | 見積書 |  |  |  |  |  |
| F12 | 展示会で名刺交換した人へのフォロー連絡 |  |  |  |  |  |
| F13 | 契約書のリーガルチェック |  |  |  |  |  |
| F14 | 保険の住所変更の手続き |  |  |  |  |  |
| F15 | 業務委託の請求書を出すこと |  |  |  |  |  |
| F16 | 歯医者の予約 |  |  |  |  |  |
| F17 | 健康診断の再検査 |  |  |  |  |  |
| F18 | ジムに行くこと |  |  |  |  |  |
| F19 | 部屋の片づけ |  |  |  |  |  |
| F20 | 免許の更新に行くこと |  |  |  |  |  |

## 11. Go / No-Go

判定基準（fix-decisions §C P5.6）: 20 件中 16 件以上が採用可、禁止句 0 件、1 呼び出し p50 4 秒以内。

| 基準 | 実測 | 自動判定 |
|---|---|---|
| 20 件中 16 件以上が採用可 | 人手採点が未記入 | 判定不能（人手採点が要る）。参考: 自動判定 全項目合格 14 / 20 |
| 禁止句 0 件 | 0 件 | 合格 |
| 1 呼び出し p50 4 秒以内 | 811 ms | 合格 |

p50 は成功・失敗を問わず全 60 呼び出しの中央値である。§9.1 のとおり追加質問の暴走が長い尾を作るため、p50 だけを見て判断せず、§9 の「6 秒超過」「エラー」の行と併せて読むこと。

判定にあたっての注意: §9.1 の分割（理由分類を列挙単独にし、追加質問を別呼び出しにする）を採れば、追加質問の失敗は Guardrails での棄却に置き換わる。**「Tier A を諦めるか」ではなく「§9 の型定義を分割するか」を先に決めるべきである。** 3 つの呼び出しのうち、行動 3 案と分野分類は現状のままで安定している。

**Go / No-Go 判定**: （人間が記入する）

**判定者 / 日付**: （人間が記入する）

No-Go の場合の代替（実装計画 §0.4 S-A）:

1. Tier B（テンプレート）固定で出荷する。Phase 2 の LLM 層は入れない。
2. Phase 4 で iOS 27 の `PrivateCloudComputeLanguageModel` を再評価する。
3. Claude API + 薄いプロキシ（Cloudflare Workers）を検討する。ただし「機種依存で完結」という原則を崩すため、最後の選択肢とする。

## 12. 再実行手順

`availability` が `unavailable` だった場合は、次の手順で有効化してから再実行する。

1. Apple メニュー → システム設定 → Apple Intelligence と Siri を開く。
2. 「Apple Intelligence」をオンにし、待機リストの承認とモデルのダウンロード完了を待つ（`modelNotReady` はダウンロード中を表す）。
3. システム設定 → 一般 → 言語と地域 で、Apple Intelligence が対応する言語になっていることを確認する。
4. `swiftc -O Spikes/fm-probe/main.swift -o /tmp/fm-probe && /tmp/fm-probe` を再実行し、このファイルを上書きする。
5. `deviceNotEligible` の場合はこの Mac では検証できない。Apple Intelligence 対応の実機（iPhone 15 Pro 以降）で S-A をやり直す。

モデルを呼ばずに自動判定コードとフィクスチャだけを検証する場合は `/tmp/fm-probe --dry-run` を使う。

既定（`maximumResponseTokens` 指定なし・上限 60 秒）は §9.1 の暴走 1 回につき最大 2 分かかるため、全 20 件で 20〜30 分を要する。短時間で回したい場合は `/tmp/fm-probe --max-response-tokens 512 --timeout 20` を使う（3〜4 分。ただし暴走が `decodingFailure` に化けるので、失敗の内訳は既定の実行と比べられない）。

## 13. S-D: iOS 26 シミュレータでの可否

| 環境 | availability | 備考 |
|---|---|---|
| macOS 26.5 / Apple M4（本 CLI） | `available` | — |
| iOS 26.2 シミュレータ | 未検証 | Xcode プロジェクト（`project.yml`）が別ブランチで作成中のため、このスパイクでは実行していない。task_004 の SpeechSpike ターゲットが揃った時点で確認する。 |
| Apple Intelligence 対応 iPhone 実機 | 未検証 | 実機確保後に確認する。 |
