const { test } = require('node:test');
const assert = require('node:assert/strict');
const { diagnostics, classify } = require('./claude-review-outcome.cjs');
const sha = 'a'.repeat(40);
const marker = `<!-- deputy-claude-review:${sha}:123:1`;
const comment = (outcome) => ({ user: { login: 'github-actions[bot]' },
  created_at: '2026-09-06T12:01:00Z', body: `${marker}:${outcome} -->` });
const context = () => ({ diagnostic: diagnostics([{ type: 'result', subtype: 'success',
  is_error: false, permission_denials: [] }]), sha, currentSha: sha, comments: [], inline: [],
  marker, started: '2026-09-06T12:00:00Z', actionOutcome: 'success' });

test('SDK success alone cannot claim a clean review', () => {
  assert.equal(classify(context()).outcome, 'blocked/failed');
  assert.equal(diagnostics([]).sdk_success, false);
});

test('clean and findings outcomes require current-run bot evidence', () => {
  const clean = { ...context(), comments: [comment('without-findings')] };
  assert.equal(classify(clean).outcome, 'completed without findings');
  assert.equal(classify({ ...clean, comments: [{ ...clean.comments[0], created_at: '2026-09-06T11:59:58Z' }] }).outcome, 'completed without findings');
  const findings = { ...context(), comments: [comment('with-findings')],
    inline: [{ ...comment('finding'), commit_id: sha }] };
  assert.equal(classify(findings).outcome, 'completed with findings');
  assert.equal(classify({ ...findings, inline: [] }).outcome, 'blocked/failed');
  assert.equal(classify({ ...findings, inline: [{ ...findings.inline[0], body: 'Unrelated concurrent bot finding' }] }).outcome, 'blocked/failed');
  assert.equal(classify({ ...findings, inline: [{ ...findings.inline[0], commit_id: 'b'.repeat(40) }] }).outcome, 'blocked/failed');
  for (const replacement of [
    { user: { login: 'someone' } }, { created_at: '2026-09-05T00:00:00Z' },
    { body: '<!-- deputy-claude-review:old -->' },
  ]) assert.equal(classify({ ...clean, comments: [{ ...clean.comments[0], ...replacement }] }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, currentSha: 'b'.repeat(40) }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, actionOutcome: 'failure' }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, inline: findings.inline }).outcome, 'blocked/failed');
});

test('diagnostics never emit free-form names, command arguments, or SDK text', () => {
  const secret = 'CANARY_PRIVATE_VALUE';
  const diagnostic = diagnostics([{ type: 'result', subtype: 'success', is_error: false,
    result: secret, permission_denials: [
      { tool_name: 'Bash', tool_input: { command: `gh pr comment 123 --body ${secret} | head -10 > ${secret}` } },
      { tool_name: secret, tool_input: { command: secret } },
      { tool_name: 'Skill', tool_input: { skill: secret } },
      { tool_name: 'Bash', tool_input: { command: `env ${secret}` } },
    ] }]);
  assert.equal(JSON.stringify(diagnostic).includes(secret), false);
  assert.deepEqual(diagnostic.denied_operations, ['Bash(gh pr comment)', 'Bash(head)', 'Bash(other-command)', 'Bash(shell-redirection)', 'Skill(other-skill)', 'other-tool']);
  assert.equal(classify({ ...context(), diagnostic, comments: [comment('without-findings')] }).outcome, 'blocked/failed');
});
