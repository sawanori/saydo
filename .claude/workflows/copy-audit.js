export const meta = {
  name: 'copy-audit',
  description: 'アプリ内の全ユーザー向け日本語文字列を抽出し、Guardrails（責めない）とトーンを並列監査して違反候補を反証検証する',
  whenToUse: '文言を追加・変更したタスクの後、および Phase ゲート前',
  phases: [
    { title: 'Extract', detail: '日本語文字列の抽出' },
    { title: 'Audit', detail: '40 件ずつ並列監査' },
    { title: 'Verify', detail: '違反候補の反証検証' },
  ],
}

const ROOT = '/Users/noritakasawada/AI_P/SAYDO'
const SNIPPET = '\n行動規範: 結論先行。捏造禁止。ファイルを編集しない。読むだけ。'

phase('Extract')
const EXTRACT_SCHEMA = {
  type: 'object',
  properties: {
    strings: {
      type: 'array',
      items: {
        type: 'object',
        properties: { text: { type: 'string' }, location: { type: 'string' } },
        required: ['text', 'location'],
      },
    },
  },
  required: ['strings'],
}
const extracted = await agent(`Bash で ${ROOT} 配下の Packages/SaydoCore/Sources と App 配下の .swift ファイルから、ひらがな・カタカナ・漢字を含む文字列リテラル（"..." および """...""" 内）を全て抽出する。例: grep -rnoE '"[^"]*[ぁ-んァ-ン一-龥][^"]*"' Packages/SaydoCore/Sources App。各文字列を text と location（ファイルパス:行）で返す。テストファイルとコメントは除外する。` + SNIPPET,
  { label: 'extract', phase: 'Extract', schema: EXTRACT_SCHEMA, effort: 'low' })
const strings = extracted && extracted.strings ? extracted.strings : []
log('Extract: ' + strings.length + ' strings')

phase('Audit')
const chunks = []
for (let i = 0; i < strings.length; i += 40) chunks.push(strings.slice(i, i + 40))
const AUDIT_SCHEMA = {
  type: 'object',
  properties: {
    flagged: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          text: { type: 'string' },
          location: { type: 'string' },
          rule: { type: 'string' },
          reason: { type: 'string' },
          rewrite: { type: 'string' },
        },
        required: ['text', 'location', 'rule', 'reason', 'rewrite'],
      },
    },
  },
  required: ['flagged'],
}
const RULES = `監査規則（企画メモ §9・§14・§22）:
1. 禁止語: 未達成、連続、サボ、怠、ダメ、なぜやらない、失敗、遅い、甘え、言い訳、また逃げ、頑張れ
2. 未完了を数えたり比較したりする表現（「3 日連続」「達成率」「あと N 件」）を禁止
3. 命令・説教・上司口調を禁止。伴走者の口調（短く、対等、責めない）
4. 質問は 60 文字以内で「？」で終わる。行動文は 40 文字以内で動詞で終わる
5. 長考を促す表現を禁止（「じっくり考えて」）。短く答えられる問いにする
6. TODO アプリ用語（タスク、完了、管理、進捗率）を避け、企画メモの語彙（逃げたいこと、前進、宣言）を使う`
const audits = await parallel(chunks.map((c, i) => () =>
  agent(RULES + '\n\n以下の文字列を監査し、違反または要検討のものだけ flagged に入れる（rule に違反番号、rewrite に書き換え案）。問題なしは含めない。\n' + JSON.stringify(c, null, 1) + SNIPPET,
    { label: 'audit:' + (i + 1), phase: 'Audit', schema: AUDIT_SCHEMA, effort: 'medium' })))
const flagged = audits.flatMap(a => (a && a.flagged ? a.flagged : []))
log('Audit: ' + flagged.length + ' flagged')

phase('Verify')
const VERDICT_SCHEMA = {
  type: 'object',
  properties: { verdict: { type: 'string', enum: ['confirmed', 'refuted'] }, reasoning: { type: 'string' }, rewrite: { type: 'string' } },
  required: ['verdict', 'reasoning', 'rewrite'],
}
const verdicts = await parallel(flagged.map((f, i) => () =>
  agent(RULES + '\n\n懐疑的に検証する: 以下の指摘は本当に規則違反か。文脈（location のファイルを Read）を確認し、誤検出なら refuted、違反なら confirmed と最終的な書き換え案を返す。\n' + JSON.stringify(f, null, 1) + SNIPPET,
    { label: 'verify:' + (i + 1), phase: 'Verify', schema: VERDICT_SCHEMA, effort: 'medium' }).then(v => ({ f, v }))))
const results = verdicts.filter(Boolean)
const confirmed = results.filter(r => r.v && r.v.verdict === 'confirmed').map(r => ({ text: r.f.text, location: r.f.location, rule: r.f.rule, rewrite: r.v.rewrite, reasoning: r.v.reasoning }))
log('Verify: ' + confirmed.length + ' confirmed of ' + flagged.length)
return { total_strings: strings.length, confirmed, refuted: results.filter(r => r.v && r.v.verdict === 'refuted').map(r => ({ text: r.f.text, reasoning: r.v.reasoning })) }
