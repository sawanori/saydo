export const meta = {
  name: 'saydo-plan-adversarial-review',
  description: 'SAYDO 実装計画書を5つの敵対的レンズで並列レビューし、統合後に指摘ごとの反証検証を行って確定した問題だけを返す',
  phases: [
    { title: 'Review', detail: '5レンズ（企画整合 / iOS技術妥当性 / 実行可能性 / リスク・審査 / プレモータム）' },
    { title: 'Merge', detail: '重複統合と重要度の再順位付け' },
    { title: 'Verify', detail: '指摘ごとの反証検証（high / medium のみ）' },
  ],
}

const ROOT = '/Users/noritakasawada/AI_P/SAYDO'
const FILES = [
  ROOT + '/voice_avoidance_companion_app_concept.md',
  ROOT + '/docs/implementation-plan.md',
  ROOT + '/docs/task-list.json',
  ROOT + '/docs/acceptance-checks.json',
]

const SNIPPET = `
以下は行動規範。全て命令。
- 結論先行: 報告の最初の一文で「何が起きたか/見つかったか」に答える。断片・矢印チェーン・自作ラベルで圧縮しない。完全な文で書く
- 即行動: 行動に足る情報が揃ったら行動。確定済み事実の再導出・決定済み事項の再審議・採らない選択肢の陳列をしない。迷ったら推奨を1つ
- 進捗の実証: 報告前に各主張をツール結果と突合。未検証は未検証と明言。捏造は最悪の失敗
- スコープ規律: 要求以上のことをしない
- ターン終了規律: 「これから X します」で終わらない。実行してから終える
- 境界: ファイルを編集してはならない。読むだけ。成果物は評価であって修正ではない`

const CONTEXT = `
# 背景
SAYDO は「逃げていることを自分の声で認めて一歩だけ動く」iOS ネイティブアプリの計画。開発者は 1 人（Claude Code 主導）。
ユーザーの制約: ネイティブ実装、サーバーやストレージは「機種依存」（自前サーバー・クラウドを持たず OS 標準機能で完結）。
今日は 2026-09-04。開発機は macOS 26.5 / Xcode 26.2 / iOS 26.2 SDK / Swift 6.2.3 / Apple M4。iOS 26 系シミュレータ未導入（18.5 のみ）、xcodegen 未導入 — これらは計画書に既に記載済みなので指摘不要。
計画は以下 4 ファイル。必ず Read ツールで全文を読むこと（省略しない）:
1. ${FILES[0]}（企画メモ。原則は §9・§18・§22）
2. ${FILES[1]}（実装計画書。戦略は §0）
3. ${FILES[2]}（タスク 21 件）
4. ${FILES[3]}（受け入れチェック 25 件）

# 出力規則
- 指摘は最大 8 件。重要度順。文体は日本語。
- severity の定義: high = 実装すると企画の原則を破る / 技術的に成立しない / 実行者が着手できない。medium = 手戻り・期間超過・品質低下を高確率で招く。low = 改善提案。
- location は「ファイル名 + 章番号 or task_id or check id」で特定する。
- evidence には計画書やドキュメントの該当文を引用する。裏取りできなかった主張は evidence に「未確認」と明記する。
- proposed_fix は計画書をどう書き換えるかを具体的に書く（「見直す」「検討する」は禁止）。
- 文体や表記のみの指摘は出さない。`

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          category: { type: 'string' },
          location: { type: 'string' },
          problem: { type: 'string' },
          evidence: { type: 'string' },
          proposed_fix: { type: 'string' },
        },
        required: ['title', 'severity', 'category', 'location', 'problem', 'evidence', 'proposed_fix'],
      },
    },
  },
  required: ['findings'],
}

const LENSES = [
  {
    key: 'product',
    prompt: `あなたはこの企画の原案者の立場に立つ敵対的レビュアー。計画書が企画メモの思想を裏切っている箇所を探す。
観点: §22 の 10 原則（責めない / 入力を面倒にしない / 開いた瞬間に会話 / できない時はタスクでなく設計を疑う / 極端に小さく / AI より本人の言葉 / 未達成より少し進んだを評価 / タスク管理アプリにしない / 音声を単なる入力にしない / 自分の声を自分に返す）、§13（チャット UI にしない）、§14（会話時間）、§9（責めない）、§18（入れないもの）。
特に: 会話フロー（計画書 §7.2）の各ステップの文言と分岐が原則を守っているか、選択肢チップやテキスト補助が「入力の面倒」や「TODO アプリ化」に逆戻りしていないか、Tier B（AI なし）で体験が原則を破っていないか、通知設計が §15 に忠実か、Insight が「達成率で追い込む」表示になっていないか。`,
  },
  {
    key: 'ios-tech',
    prompt: `あなたは iOS 26 の音声・オンデバイス AI に精通したシニア iOS エンジニアで、計画書の技術的主張の誤りと成立しない設計を探す敵対的レビュアー。
対象: 計画書 §0.2 の対応表、§7.3 音声パイプライン、§7.4 通知、§7.5、§9 API Plan、§10 Database Plan、§11、task_003 / 004 / 006 / 007 / 009 / 014 / 021。
必ず Apple 公式ドキュメントで裏を取る: ToolSearch で mcp__context7__query-docs と mcp__context7__resolve-library-id を読み込み、libraryId '/websites/developer_apple_foundationmodels'（Foundation Models）と '/websites/developer_apple_speech'（SpeechAnalyzer / SpeechTranscriber / AssetInventory）を query-docs で確認する。AVFoundation（AVAudioEngine タップから AVAudioFile への AAC 書き込み、AVAudioSession の iOS 26 でのオプション名）、UserNotifications（Library/Sounds のカスタムサウンド制約、UNCalendarNotificationTrigger）、SwiftData（#Index、VersionedSchema、@ModelActor）は resolve-library-id で探して確認する。
検証すべき主張の例: 1 つの入力タップから録音と SpeechAnalyzer へ同時供給できるか / SpeechAnalyzer は本当に音声認識権限が不要か / Foundation Models のコンテキスト 4,096 トークンと日本語 1 文字 1 トークンの記述 / @Guide の制約種類（文字数制約は存在するか）/ ファイル保護 completeUntilFirstUserAuthentication とロック中の通知タップ再生 / AAC 32kbps モノラルを AVAudioFile で書けるか / 通知サウンドの 30 秒制限と形式 / Swift 6 strict concurrency と AVAudioEngine タップの並行性 / Foundation Models のシミュレータ動作条件。
確認できた事実と計画書の記述が食い違う場合のみ high。確認できなかった主張は「未確認」として medium 以下にする。`,
  },
  {
    key: 'executability',
    prompt: `あなたは「別の Claude Code セッションがこの計画だけを渡されて実装できるか」を判定する敵対的レビュアー。
観点: (1) task-list.json の dependencies が正しいか（循環、抜け、順序の矛盾。例: task_007 が Domain 型を使うのに task_002 に依存していない等）、(2) 各タスクが 1 セッションで終わる粒度か（大きすぎるタスクを分割案付きで指摘）、(3) done_definition が客観的に判定できるか、(4) verify_commands が存在しないコマンドを前提にしていないか（scripts/*.sh は task_001 が作る前提。それ以前のタスクで使っていないか）、(5) 3 文書間の不整合（implementation-plan.md §11 のファイル表と task-list.json の files_to_create / files_to_modify、acceptance-checks.json の verification_method が指すテストファイル名が task-list に存在するか）、(6) 必要なのに存在しないタスク（例: Info.plist の権限文言、アプリアイコン、Localizable、SessionLog の記録、TabView、AppSettings の依存など）、(7) Tests/SaydoTests ターゲットの作成タスクがどこにあるか、(8) XcodeGen の project.yml に必要な設定が各タスクで追記されるか。
不整合は具体的なファイル名・task_id・check id を挙げて指摘する。`,
  },
  {
    key: 'risk-review',
    prompt: `あなたはリスク・スケジュール・プライバシー・App Store 審査の敵対的レビュアー。
観点: (1) 見積もり（計画書 §0.3）の妥当性と、1 人 + Claude Code 体制で見落とされがちな工数（実機テスト、TestFlight 手続き、権限周りの試行錯誤）、(2) App Store 審査リスク: アプリ起動と同時にマイクを自動で開く設計、通知タップからの自動録音、録音データの扱い、プライバシー表示「データを収集しない」の妥当性（オンデバイスでも録音を端末に保存する場合の表示）、Apple Intelligence 非対応機での機能差の説明義務、(3) 実運用リスク: ロック画面で通知をタップした場合の Face ID 解除とオーディオセッションの順序、無音環境ではない場所（電車・職場）で音声必須の体験が破綻しないか、AirPods や Bluetooth 経路、電話着信・Siri による割り込み、通知の到達性（集中モード、通知許可の失効）、iCloud バックアップが無効なユーザーの音声消失、端末容量、(4) Foundation Models の日本語品質が不十分だった場合に Phase 2 が空振りするリスクと、その時の計画上の受け皿が十分か、(5) 「機種依存」方針の弱点（Apple Intelligence 対応機の普及率、iOS 26 必須による対象端末の狭さ）を計画書が定量的に扱っているか。
各指摘には計画書のどこをどう書き換えるかを書く。`,
  },
  {
    key: 'premortem',
    prompt: `あなたはプレモータム（事前検死）を行う敵対的レビュアー。前提: 「この計画どおりに 6 週間進めたが、SAYDO は App Store に出せなかった / 出せたが開発者本人ですら 1 週間で使わなくなった」という未来が確定したとする。
その未来を最ももっともらしく説明する原因を、計画書の記述に根拠を置いて特定する。
観点の例: 状態機械 + 穴埋め LLM という設計が会話を機械的にして「相棒」感を失う / 音声認識の誤認識でフローが詰まる経路が計画に無い / 毎朝 3 分が実際は 5 分になる要因 / 通知が来ても開かない日の設計が無い（再エンゲージ）/ Voice Timeline の価値が薄い / スパイクの Go / No-Go 基準が曖昧で判断できない / タスクの順序が「価値の検証」より「基盤づくり」に偏っていて TestFlight 到達が遅い / 音声を聞き返す体験が実は恥ずかしくて再生しない、など。
各原因について、計画書のどのタスク・章を、どう変えれば防げるかを具体的に書く。推測だけでなく、企画メモや計画書の文言を引用して根拠を示す。`,
  },
]

phase('Review')
const reviews = await parallel(LENSES.map(l => () =>
  agent(CONTEXT + '\n\n# あなたのレンズ\n' + l.prompt + '\n\n' + SNIPPET,
        { label: 'review:' + l.key, phase: 'Review', schema: FINDINGS_SCHEMA, effort: 'high' })))
const all = reviews.flatMap((r, i) => (r && r.findings ? r.findings : []).map(f => ({ ...f, lens: LENSES[i].key })))
log('Review: ' + all.length + ' findings from ' + reviews.filter(Boolean).length + '/' + LENSES.length + ' lenses')

phase('Merge')
const MERGED_SCHEMA = {
  type: 'object',
  properties: {
    merged: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium'] },
          category: { type: 'string' },
          location: { type: 'string' },
          problem: { type: 'string' },
          evidence: { type: 'string' },
          proposed_fix: { type: 'string' },
          sources: { type: 'array', items: { type: 'string' } },
        },
        required: ['id', 'title', 'severity', 'category', 'location', 'problem', 'evidence', 'proposed_fix', 'sources'],
      },
    },
    low: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          location: { type: 'string' },
          proposed_fix: { type: 'string' },
        },
        required: ['title', 'location', 'proposed_fix'],
      },
    },
  },
  required: ['merged', 'low'],
}
const mergePrompt = `5 人のレビュアーが SAYDO 実装計画書に出した指摘を統合する。
やること: (1) 同じ問題を指す指摘を 1 件に統合し、最も具体的な evidence と proposed_fix を残す（複数の fix が補完的なら合成する）、(2) 統合後に severity を付け直す（high / medium は merged へ、low は low へ）、(3) merged は重要度順に並べ、id を F01, F02, ... と振る、(4) sources に元のレンズ名（lens）を全て入れる。
指摘の内容を発明・拡張してはならない。統合と順位付けだけを行う。
ファイルを読む必要はない。以下が全指摘の JSON:
` + JSON.stringify(all, null, 1) + '\n\n' + SNIPPET
const merged = await agent(mergePrompt, { label: 'merge', phase: 'Merge', schema: MERGED_SCHEMA, model: 'opus', effort: 'high' })
const mergedList = merged && merged.merged ? merged.merged : []
const lowList = merged && merged.low ? merged.low : []
const CAP = 16
const toVerify = mergedList.slice(0, CAP)
if (mergedList.length > CAP) log('Verify cap: ' + (mergedList.length - CAP) + ' merged findings beyond ' + CAP + ' are returned unverified')
log('Merge: ' + mergedList.length + ' high/medium, ' + lowList.length + ' low')

phase('Verify')
const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'downgraded', 'refuted'] },
    severity: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' },
    refined_fix: { type: 'string' },
  },
  required: ['verdict', 'severity', 'reasoning', 'refined_fix'],
}
const verifyPrompt = f => CONTEXT + `

# 任務: 以下の指摘を反証する
あなたは懐疑的な検証者。指摘が (a) 計画書の記述について事実として正しいか、(b) 実害があるか（直さないと何が起きるか）、(c) proposed_fix が妥当で副作用がないか、を計画書の該当箇所（location）と企画メモを Read して確かめる。API 仕様に関する指摘は ToolSearch で mcp__context7__query-docs を読み込み、'/websites/developer_apple_foundationmodels' または '/websites/developer_apple_speech'（他は resolve-library-id）で裏を取る。
判定: confirmed = 事実として正しく実害があり fix も妥当。downgraded = 正しいが実害が小さい、または fix に修正が必要（refined_fix に修正版を書く）。refuted = 計画書の誤読、事実誤認、または計画書が既に対処済み（reasoning に該当箇所を引用）。
迷ったら refuted ではなく downgraded にし、理由を書く。refined_fix は計画書を書き換える具体的な文で書く。

指摘:
` + JSON.stringify(f, null, 1) + '\n\n' + SNIPPET

const verdicts = await parallel(toVerify.map((f, i) => () =>
  agent(verifyPrompt(f), { label: 'verify:' + f.id, phase: 'Verify', schema: VERDICT_SCHEMA, model: 'opus', effort: 'max' })
    .then(v => ({ finding: f, verdict: v }))))

const results = verdicts.filter(Boolean)
const confirmed = results.filter(r => r.verdict && r.verdict.verdict === 'confirmed')
const downgraded = results.filter(r => r.verdict && r.verdict.verdict === 'downgraded')
const refuted = results.filter(r => r.verdict && r.verdict.verdict === 'refuted')
log('Verify: ' + confirmed.length + ' confirmed, ' + downgraded.length + ' downgraded, ' + refuted.length + ' refuted, ' + (toVerify.length - results.length) + ' lost')

return {
  stats: { raw: all.length, merged: mergedList.length, verified: results.length, confirmed: confirmed.length, downgraded: downgraded.length, refuted: refuted.length },
  confirmed: confirmed.map(r => ({ id: r.finding.id, severity: r.verdict.severity, title: r.finding.title, location: r.finding.location, problem: r.finding.problem, evidence: r.finding.evidence, fix: r.verdict.refined_fix, reasoning: r.verdict.reasoning, sources: r.finding.sources })),
  downgraded: downgraded.map(r => ({ id: r.finding.id, severity: r.verdict.severity, title: r.finding.title, location: r.finding.location, problem: r.finding.problem, fix: r.verdict.refined_fix, reasoning: r.verdict.reasoning })),
  refuted: refuted.map(r => ({ id: r.finding.id, title: r.finding.title, reasoning: r.verdict.reasoning })),
  unverified: mergedList.slice(CAP),
  low: lowList,
}