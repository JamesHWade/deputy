// Publish only allowlisted diagnostics; never serialize SDK messages or tool inputs.
const fs = require('node:fs');

const knownTools = new Set([
  'Agent', 'Task', 'TaskOutput', 'TaskCreate', 'TaskUpdate', 'TaskList',
  'TodoWrite', 'Skill', 'Read', 'Glob', 'Grep', 'Bash',
  'mcp__github_inline_comment__create_inline_comment',
]);
const commands = [
  'gh pr view', 'gh pr diff', 'gh pr list', 'gh pr comment',
  'gh issue view', 'gh issue list', 'gh search', 'gh api',
  'git diff', 'git show', 'git log', 'git rev-parse',
];

function diagnostics(messages) {
  const result = Array.isArray(messages)
    ? messages.findLast((message) => message.type === 'result') : undefined;
  const denials = Array.isArray(result?.permission_denials) ? result.permission_denials : [];
  return {
    sdk_success: result?.subtype === 'success' && result?.is_error === false,
    permission_denials_count: denials.length,
    denied_operations: [...new Set(denials.map((denial) => {
      const tool = knownTools.has(denial.tool_name) ? denial.tool_name : 'other-tool';
      if (tool !== 'Bash') return tool;
      const command = denial.tool_input?.command;
      const prefix = typeof command === 'string' && commands.find((candidate) =>
        command === candidate || command.startsWith(candidate + ' '));
      return prefix ? `Bash(${prefix})` : 'Bash(other-command)';
    }))].sort(),
  };
}

function classify({ diagnostic, sha, currentSha, comments, inline, marker, started, actionOutcome }) {
  const blocked = (reason) => ({ outcome: 'blocked/failed', reason });
  if (sha !== currentSha) return blocked('PR head changed during review');
  if (actionOutcome !== 'success' || !diagnostic.sdk_success) return blocked('Claude did not complete successfully');
  if (diagnostic.permission_denials_count) return blocked('Claude tool permission denied');
  const fresh = (comment) => comment.user?.login === 'claude[bot]' &&
    Date.parse(comment.created_at) >= Date.parse(started);
  const summaries = comments.filter(fresh);
  const findings = inline.filter((comment) => fresh(comment) && comment.commit_id === sha);
  const withFindings = summaries.some((comment) => comment.body?.includes(`${marker}:with-findings -->`));
  const withoutFindings = summaries.some((comment) => comment.body?.includes(`${marker}:without-findings -->`));
  if (withFindings && !withoutFindings && findings.length) {
    return { outcome: 'completed with findings', reason: 'Current-run summary and exact-commit inline findings verified' };
  }
  if (withoutFindings && !withFindings && !findings.length) {
    return { outcome: 'completed without findings', reason: 'Current-run exact-commit clean summary verified' };
  }
  return blocked('No consistent current-run exact-commit review evidence');
}

async function main() {
  const env = process.env;
  const sha = env.REVIEW_SHA;
  if (!/^[a-f0-9]{40}$/.test(sha || '')) throw new Error('Invalid review SHA');
  let diagnostic = diagnostics([]);
  let result = { outcome: 'blocked/failed', reason: 'Review evidence unavailable' };
  try {
    const execution = env.EXECUTION_FILE || `${env.RUNNER_TEMP}/claude-execution-output.json`;
    diagnostic = diagnostics(JSON.parse(fs.readFileSync(execution, 'utf8')));
    async function get(path) {
      const response = await fetch(`https://api.github.com/repos/${env.GITHUB_REPOSITORY}/${path}`, {
        headers: { Authorization: `Bearer ${env.GH_TOKEN}`, Accept: 'application/vnd.github+json' },
      });
      if (!response.ok) throw new Error('GitHub evidence request failed');
      return response.json();
    }
    async function pages(path) {
      const values = [];
      for (let page = 1; ; page++) {
        const batch = await get(`${path}?per_page=100&page=${page}`);
        values.push(...batch);
        if (batch.length < 100) return values;
      }
    }
    const [pr, comments, inline] = await Promise.all([
      get(`pulls/${env.PR_NUMBER}`), pages(`issues/${env.PR_NUMBER}/comments`),
      pages(`pulls/${env.PR_NUMBER}/comments`),
    ]);
    result = classify({ diagnostic, sha, currentSha: pr.head.sha, comments, inline,
      marker: `<!-- deputy-claude-review:${sha}:${env.GITHUB_RUN_ID}:${env.GITHUB_RUN_ATTEMPT}`,
      started: env.REVIEW_STARTED, actionOutcome: env.ACTION_OUTCOME });
  } catch {
    // Errors can include server responses, file contents, or token-bearing URLs.
    // Keep the public failure categorical; never print the caught value.
  }
  const safe = { ...result, reviewed_sha: sha, ...diagnostic };
  fs.writeFileSync(`${env.RUNNER_TEMP}/claude-review-outcome.json`, JSON.stringify(safe, null, 2));
  fs.appendFileSync(env.GITHUB_STEP_SUMMARY,
    `### Claude review: ${safe.outcome}\n\nCommit: \`${sha}\`\n\n${safe.reason}.\n\n` +
    `Permission denials: ${safe.permission_denials_count}. ` +
    `Operations: ${safe.denied_operations.join(', ') || 'none'}.\n`);
  console.log(JSON.stringify(safe));
  if (safe.outcome === 'blocked/failed') process.exitCode = 1;
}

module.exports = { diagnostics, classify };
if (require.main === module) main().catch(() => {
  console.error('Claude review outcome verification failed');
  process.exitCode = 1;
});
