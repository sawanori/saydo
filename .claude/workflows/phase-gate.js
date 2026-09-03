export const meta = {
  name: 'phase-gate',
  description: 'docs/acceptance-checks.json の各チェックを 1 エージェントが pass / fail / needs-human で判定し、人間向けチェックリストを出力する',
  whenToUse: 'Phase ゲート G1〜G3。args: { checks: ["check_001", ...] }（省略時は全件）',
  phases: [
    { title: 'Load', detail: 'チェック一覧の読み込み' },
    { title: 'Judge', detail: 'チェックごとの判定' },
  ],
}

const ROOT = '/Users/noritakasawada/AI_P/SAYDO'
const wanted = args && Array.isArray(args.checks) ? args.checks : null
const SNIPPET = '\n行動規範: 結論先行。捏造禁止。証拠のない pass を出さない。ファイルを編集しない。'

phase('Load')
const LIST_SCHEMA = {
  type: 'object',
  properties: {
    checks: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' }, target: { type: 'string' }, rule: { type: 'string' },
          expected_result: { type: 'string' }, manual_or_automated: { type: 'string' }, verification_method: { type: 'string' },
        },
        required: ['id', 'target', 'rule', 'expected_result', 'manual_or_automated', 'verification_method'],
      },
    },
  },
  required: ['checks'],
}
const loaded = await agent(`${ROOT}/docs/acceptance-checks.json を Read し、checks 配列をそのまま返す（加工しない）。` + SNIPPET, { label: 'load', phase: 'Load', schema: LIST_SCHEMA, effort: 'low' })
const checks = (loaded && loaded.checks ? loaded.checks : []).filter(c => !wanted || wanted.includes(c.id))
log('Load: ' + checks.length + ' checks')

phase('Judge')
const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    verdict: { type: 'string', enum: ['pass', 'fail', 'needs-human'] },
    evidence: { type: 'string' },
    human_steps: { type: 'array', items: { type: 'string' } },
    fix_hint: { type: 'string' },
  },
  required: ['id', 'verdict', 'evidence', 'human_steps', 'fix_hint'],
}
const verdicts = await parallel(checks.map(c => () =>
  agent(`SAYDO（${ROOT}）の受け入れチェックを 1 件判定する。
- automated のチェックは verification_method のコマンドやテストを Bash / Read で実際に実行・確認し、出力を evidence に貼る。実行できなければ fail ではなく needs-human にして理由を書く。
- manual のチェックは、コード上で前提が満たされているか（該当機能の実装・テストの存在）を Read で確認し、人間が実機で行う手順を human_steps に 3〜6 行で書いて needs-human とする。コードに明らかな欠落があれば fail。
- pass は証拠がある場合のみ。
チェック:\n` + JSON.stringify(c, null, 1) + SNIPPET,
    { label: 'judge:' + c.id, phase: 'Judge', schema: VERDICT_SCHEMA, effort: 'high' })))
const results = verdicts.filter(Boolean)
const count = s => results.filter(r => r.verdict === s).length
log('Judge: ' + count('pass') + ' pass, ' + count('fail') + ' fail, ' + count('needs-human') + ' needs-human, ' + (checks.length - results.length) + ' lost')
return {
  pass: results.filter(r => r.verdict === 'pass').map(r => ({ id: r.id, evidence: r.evidence })),
  fail: results.filter(r => r.verdict === 'fail').map(r => ({ id: r.id, evidence: r.evidence, fix_hint: r.fix_hint })),
  needs_human: results.filter(r => r.verdict === 'needs-human').map(r => ({ id: r.id, steps: r.human_steps, note: r.evidence })),
}
