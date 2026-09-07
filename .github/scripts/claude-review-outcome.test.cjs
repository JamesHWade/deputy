const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { diagnostics, classify, priorReviewSkip } = require('./claude-review-outcome.cjs');
const sha = 'a'.repeat(40);
const marker = `<!-- deputy-claude-review:${sha}:123:1`;
const findingMarker = "[Review run](https://github.com/example/deputy/actions/runs/123/attempts/1)";
const comment = (outcome) => ({ user: { login: 'github-actions[bot]' },
  created_at: '2026-09-06T12:01:00Z', body: `${marker}:${outcome} -->` });
const context = () => ({ diagnostic: diagnostics([{ type: 'assistant', message: { content: [
  { type: 'tool_use', id: 'skill-1', name: 'Skill', input: { skill: 'code-review:code-review', args: 'example/deputy/pull/131 --comment' } },
  { type: 'tool_use', id: 'agent-1', name: 'Agent', input: { prompt: 'Review the current PR diff' } },
] } }, { type: 'user', message: { content: [
  { type: 'tool_result', tool_use_id: 'skill-1', content: 'Plugin instructions' },
  { type: 'tool_result', tool_use_id: 'agent-1', content: 'Review result' },
] } }, { type: 'result', subtype: 'success',
  is_error: false, permission_denials: [] }]), sha, currentSha: sha, comments: [], inline: [],
  marker, findingMarker, started: '2026-09-06T12:00:00Z', actionOutcome: 'success' });

test('SDK success alone cannot claim a clean review', () => {
  assert.equal(classify(context()).outcome, 'blocked/failed');
  assert.equal(diagnostics([]).sdk_success, false);
});

test('upstream skips remain distinct from current-head completion', () => {
  const diagnostic = { ...context().diagnostic, plugin_calls: 1, review_agent_calls: 0, review_agent_successes: 0,
    reported_outcome: 'skipped', reported_reason: 'already-reviewed' };
  const priorReview = { ...comment('without-findings'), created_at: '2026-09-05T12:00:00Z',
    body: `<!-- deputy-claude-review:${'b'.repeat(40)}:122:1:without-findings -->` };
  const prior = { ...context(), diagnostic, comments: [priorReview] };
  assert.equal(priorReviewSkip(prior).outcome, 'intentionally skipped');
  assert.equal(priorReviewSkip({ ...prior, currentSha: 'b'.repeat(40) }), undefined);
  assert.equal(priorReviewSkip({ ...prior, comments: [] }), undefined);
  assert.equal(priorReviewSkip({ ...prior, comments: [{ ...priorReview, user: { login: 'someone' } }] }), undefined);
  assert.equal(classify(prior).outcome, 'intentionally skipped');
  assert.match(classify(prior).reason, /this run did not review the current head/);
  for (const replacement of [
    { comments: [] }, { currentSha: 'b'.repeat(40) }, { actionOutcome: 'failure' },
    { diagnostic: { ...diagnostic, sdk_success: false } },
    { diagnostic: { ...diagnostic, plugin_calls: 0 } },
    { diagnostic: { ...diagnostic, permission_denials_count: 1 } },
    { comments: [{ ...priorReview, user: { login: 'someone' } }] },
    { comments: [{ ...priorReview, created_at: '2026-09-06T12:01:00Z' }] },
    { comments: [{ ...priorReview, body: 'An unrelated older bot comment' }] },
  ]) assert.equal(classify({ ...prior, ...replacement }).outcome, 'blocked/failed');
  for (const [reason, evidence] of [['draft', { draft: true }], ['closed', { state: 'closed' }], ['trivial', {}]]) {
    const skipped = { ...context(), ...evidence, diagnostic: { ...diagnostic, reported_reason: reason } };
    assert.equal(classify(skipped).outcome, 'intentionally skipped');
    if (reason !== 'trivial') assert.equal(classify({ ...skipped, draft: false, state: 'open' }).outcome, 'blocked/failed');
  }
});

test('preflight skips SDK only with prior-review evidence and fails closed on API errors', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'deputy-review-preflight-'));
  try {
    const preload = path.join(directory, 'fetch.cjs');
    fs.writeFileSync(preload, `global.fetch = async (url) => ({
      ok: process.env.TEST_API_FAIL !== 'true',
      json: async () => url.endsWith('/pulls/131')
        ? { head: { sha: process.env.TEST_CURRENT_SHA } }
        : JSON.parse(process.env.TEST_COMMENTS),
    });`);
    const prior = { ...comment('without-findings'), created_at: '2026-09-05T12:00:00Z' };
    for (const [scenario, overrides, expected] of [
      ['prior', {}, 'intentionally skipped'],
      ['new', { TEST_COMMENTS: '[]' }, undefined],
      ['changed', { TEST_CURRENT_SHA: 'b'.repeat(40) }, 'blocked/failed'],
      ['api-error', { TEST_API_FAIL: 'true' }, 'blocked/failed'],
    ]) {
      const runDirectory = path.join(directory, scenario);
      fs.mkdirSync(runDirectory);
      const output = path.join(runDirectory, 'output');
      const result = spawnSync(process.execPath, ['--require', preload, path.join(__dirname, 'claude-review-outcome.cjs')], {
        encoding: 'utf8', env: { ...process.env, REVIEW_PREFLIGHT: 'true', REVIEW_SHA: sha,
          REVIEW_STARTED: context().started, PR_NUMBER: '131', GITHUB_REPOSITORY: 'example/deputy',
          GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: path.join(runDirectory, 'summary'), RUNNER_TEMP: runDirectory,
          TEST_CURRENT_SHA: sha, TEST_COMMENTS: JSON.stringify([prior]), ...overrides },
      });
      assert.equal(result.status, expected === 'blocked/failed' ? 1 : 0);
      const artifact = path.join(runDirectory, 'claude-review-outcome.json');
      if (expected) {
        const outcome = JSON.parse(fs.readFileSync(artifact, 'utf8'));
        assert.equal(outcome.outcome, expected);
        assert.equal(outcome.stage, 'eligibility');
        assert.equal(outcome.sdk_success, false);
        assert.equal(fs.existsSync(output) && fs.readFileSync(output, 'utf8').includes('should_review=true'), false);
      } else {
        assert.equal(fs.readFileSync(output, 'utf8'), 'should_review=true\n');
        assert.equal(fs.existsSync(artifact), false);
      }
    }
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('clean and findings outcomes require current-run bot evidence', () => {
  const clean = { ...context(), comments: [comment('without-findings')] };
  assert.equal(classify(clean).outcome, 'completed without findings');
  assert.equal(classify({ ...clean, diagnostic: { ...clean.diagnostic, plugin_calls: 0 } }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, diagnostic: { ...clean.diagnostic, plugin_comment_argument_seen: false } }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, diagnostic: { ...clean.diagnostic, review_agent_calls: 0 } }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, diagnostic: { ...clean.diagnostic, review_agent_successes: 0 } }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, diagnostic: { ...clean.diagnostic, plugin_successes: 0 } }).outcome, 'blocked/failed');
  assert.equal(classify({ ...clean, comments: [{ ...clean.comments[0], created_at: '2026-09-06T11:59:58Z' }] }).outcome, 'completed without findings');
  const findings = { ...context(), comments: [comment('with-findings')],
    inline: [{ ...comment('finding'), body: findingMarker, commit_id: sha }] };
  assert.equal(classify(findings).outcome, 'completed with findings');
  assert.equal(classify({ ...findings, diagnostic: { ...findings.diagnostic, plugin_calls: 0 } }).outcome, 'blocked/failed');
  assert.equal(classify({ ...findings, diagnostic: { ...findings.diagnostic, review_agent_calls: 0 } }).outcome, 'blocked/failed');
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
  const diagnostic = diagnostics([{ type: 'assistant', message: { content: [
    { type: 'tool_use', id: 'skill-1', name: 'Skill', input: { skill: 'code-review:code-review', args: `${secret} --comment` } },
    { type: 'tool_use', id: 'agent-1', name: 'Agent', input: { prompt: secret } },
  ] } }, { type: 'user', message: { content: [
    { type: 'tool_result', tool_use_id: 'skill-1', content: secret },
    { type: 'tool_result', tool_use_id: 'agent-1', content: secret },
  ] } }, { type: 'result', subtype: 'success', is_error: false,
    result: secret, structured_output: { outcome: secret, reason: secret }, permission_denials: [
      { tool_name: 'Bash', tool_input: { command: `gh pr comment 123 --body ${secret} | head -10 > ${secret}` } },
      { tool_name: secret, tool_input: { command: secret } },
      { tool_name: 'Skill', tool_input: { skill: secret } },
      { tool_name: 'Bash', tool_input: { command: `env ${secret}` } },
    ] }]);
  assert.equal(JSON.stringify(diagnostic).includes(secret), false);
  assert.equal(diagnostic.plugin_calls, 1);
  assert.equal(diagnostic.plugin_successes, 1);
  assert.equal(diagnostic.plugin_comment_argument_seen, true);
  assert.equal(diagnostic.review_agent_calls, 1);
  assert.equal(diagnostic.review_agent_successes, 1);
  assert.deepEqual(diagnostic.denied_operations, ['Bash(gh pr comment)', 'Bash(head)', 'Bash(other-command)', 'Bash(shell-redirection)', 'Skill(other-skill)', 'other-tool']);
  assert.equal(classify({ ...context(), diagnostic }).outcome, 'blocked/failed');
  assert.equal(classify({ ...context(), diagnostic, comments: [comment('without-findings')] }).outcome, 'completed without findings');
});

test('denied and failed tool attempts do not count as upstream execution', () => {
  for (const name of ['Skill', 'Agent', 'Task']) {
    const call = { type: 'tool_use', id: 'attempt-1', name,
      input: name === 'Skill' ? { skill: 'code-review:code-review', args: '--comment' } : {} };
    const attempt = [{ type: 'assistant', message: { content: [call] } }];
    const successResult = { type: 'result', subtype: 'success', is_error: false, permission_denials: [] };
    const failed = { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: call.id, is_error: true }] } };
    const successful = { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: call.id, is_error: false }] } };
    for (const messages of [
      [...attempt, successResult], [...attempt, failed, successResult],
      [...attempt, successful, { ...successResult, permission_denials: [{ tool_name: name, tool_use_id: call.id }] }],
    ]) {
      const diagnostic = diagnostics(messages);
      assert.equal(diagnostic.plugin_successes, 0);
      assert.equal(diagnostic.review_agent_successes, 0);
      assert.equal(diagnostic.plugin_comment_argument_seen, false);
    }
    const diagnostic = diagnostics([...attempt, successful, successResult]);
    assert.equal(name === 'Skill' ? diagnostic.plugin_successes : diagnostic.review_agent_successes, 1);
    if (name !== 'Skill') {
      const background = diagnostics([{ type: 'assistant', message: { content: [
        { ...call, input: { run_in_background: true } },
      ] } }, successful, successResult]);
      assert.equal(background.review_agent_successes, 0);
    }
  }
});
