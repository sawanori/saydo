export const meta = {
  name: 'task-review',
  description: 'タスクブランチの差分を4観点（正しさ / 企画原則 / Swift 6 並行性 / テスト充足）で並列レビューし、各指摘を反証検証して確定した問題だけを返す',
  whenToUse: 'task_xxx ブランチの PR 前。args: { base: "main", task_id: "task_007" }',
  phases: [
    { title: 'Review', detail: '4観点の並列レビュー' },
    { title: 'Verify', detail: '指摘ごとの反証検証' },
  ],
}

const ROOT = '/Users/noritakasawada/AI_P/SAYDO'
const base = (args && args.base) || 'main'
const taskId = (args && args.task_id) || '(未指定)'

const SNIPPET = `
以下は行動規範。全て命令。
- 結論先行。完全な文で書く。捏造は最悪の失敗。未検証は未検証と明言する
- ファイルを編集してはならない。読むだけ。成果物は評価であって修正ではない`

const CONTEXT = `
# 背景
SAYDO（iOS ネイティブの音声伴走アプリ）のタスクブランチをレビューする。対象タスク: ${taskId}。
1. Bash で \`cd ${ROOT} && git diff ${base}...HEAD --stat && git diff ${base}...HEAD\` を実行して差分を全て読む。
2. ${ROOT}/docs/task-list.json から ${taskId} のエントリ（scope / non_scope / done_definition）を読む。
3. ${ROOT}/docs/implementation-plan.md の関連章と、${ROOT}/voice_avoidance_companion_app_concept.md の §9・§22 を読む。
# 出力規則
指摘は最大 8 件、重要度順、日本語。severity: high = バグ / 企画原則違反 / done_definition 未達。medium = 手戻りを招く設計。low = 改善提案。
location は「ファイルパス:行」。evidence は差分から引用。proposed_fix は具体的なコード変更として書く。文体のみの指摘は出さない。`

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
          location: { type: 'string' },
          problem: { type: 'string' },
          evidence: { type: 'string' },
          proposed_fix: { type: 'string' },
        },
        required: ['title', 'severity', 'location', 'problem', 'evidence', 'proposed_fix'],
      },
    },
  },
  required: ['findings'],
}

const LENSES = [
  { key: 'correctness', prompt: 'レンズ: 正しさ。ロジックの誤り、境界条件、エラー経路、状態機械の遷移漏れ、非同期処理の競合、リソースリーク（AVAudioEngine のタップ解除、ファイルハンドル）、SwiftData のコンテキスト誤用。' },
  { key: 'principles', prompt: 'レンズ: 企画原則。差分に含まれる全ユーザー向け文字列が §9・§22 を守っているか（責めない、未達成を数えない、チャット UI 化しない、入力を面倒にしない）。文字列が DialogueCopy / NotificationCopy 以外に直書きされていないか。ネットワーク API が追加されていないか。scope 外の機能が混ざっていないか。' },
  { key: 'concurrency', prompt: 'レンズ: Swift 6 strict concurrency。@unchecked Sendable / nonisolated(unsafe) / Task.detached の乱用、@MainActor 境界の誤り、actor 内からの同期ブロック、AVAudioEngine タップのクロージャからの状態変更、AsyncStream の continuation の finish 漏れ。' },
  { key: 'tests', prompt: 'レンズ: テスト充足。done_definition の各項目に対応するテストが差分にあるか。テストがハードコードや特殊分岐で通していないか。verify_commands（scripts/test-core.sh, scripts/test-ios.sh）が本当に緑か、Bash で実行して確認する（実行できない場合は未確認と書く）。' },
]

phase('Review')
const reviews = await parallel(LENSES.map(l => () =>
  agent(CONTEXT + '\n\n' + l.prompt + '\n\n' + SNIPPET, { label: 'review:' + l.key, phase: 'Review', schema: FINDINGS_SCHEMA, effort: 'high' })))
const all = reviews.flatMap((r, i) => (r && r.findings ? r.findings : []).map((f, j) => ({ ...f, id: 'R' + (i + 1) + '-' + (j + 1), lens: LENSES[i].key })))
const toVerify = all.filter(f => f.severity !== 'low').slice(0, 16)
log('Review: ' + all.length + ' findings, verifying ' + toVerify.length)

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
const verdicts = await parallel(toVerify.map(f => () =>
  agent(CONTEXT + '\n\n# 任務: 以下の指摘を反証する\n差分と該当ファイルを読み、(a) 事実として正しいか (b) 実害があるか (c) fix が妥当か を判定する。confirmed / downgraded（refined_fix に修正版）/ refuted（reasoning に根拠を引用）。迷ったら downgraded。\n\n指摘:\n' + JSON.stringify(f, null, 1) + '\n\n' + SNIPPET,
    { label: 'verify:' + f.id, phase: 'Verify', schema: VERDICT_SCHEMA, effort: 'high' }).then(v => ({ finding: f, verdict: v }))))
const results = verdicts.filter(Boolean)
const pick = s => results.filter(r => r.verdict && r.verdict.verdict === s)
log('Verify: ' + pick('confirmed').length + ' confirmed, ' + pick('downgraded').length + ' downgraded, ' + pick('refuted').length + ' refuted')
return {
  task_id: taskId,
  confirmed: pick('confirmed').map(r => ({ id: r.finding.id, severity: r.verdict.severity, title: r.finding.title, location: r.finding.location, problem: r.finding.problem, fix: r.verdict.refined_fix })),
  downgraded: pick('downgraded').map(r => ({ id: r.finding.id, severity: r.verdict.severity, title: r.finding.title, location: r.finding.location, fix: r.verdict.refined_fix, reasoning: r.verdict.reasoning })),
  refuted: pick('refuted').map(r => ({ id: r.finding.id, title: r.finding.title, reasoning: r.verdict.reasoning })),
  low: all.filter(f => f.severity === 'low'),
}
