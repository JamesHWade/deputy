// Browser check for inst/examples/commons-subagents (#238). See README.md.
//
// Start the app first, then run:
//   NODE_PATH="$(npm root -g)" node dev/browser/commons-subagents.js
// APP_URL (default http://127.0.0.1:7801), CHROMIUM_PATH (a Chromium binary,
// default Playwright's) and SHOTS (screenshot directory, default the OS temp
// directory) are optional. Exits non-zero when a check fails. The reopening
// checks open the newest saved conversation, the one this script just made.
const { chromium } = require('playwright');
const os = require('os');
const APP = process.env.APP_URL || 'http://127.0.0.1:7801';
const SP = process.env.SHOTS || os.tmpdir();
const checks = [];
const check = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail }); console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail !== undefined ? ' :: ' + JSON.stringify(detail) : '')); };
const metrics = async (page) => {
  for (let i = 0; i < 40; i++) { const t = ((await page.textContent('#metrics')) || '').trim(); if (t) return t; await page.waitForTimeout(250); }
  return '';
};
const ask = async (page, text, waitText) => {
  const input = page.locator('#chat [contenteditable="true"][aria-label="Chat message"]');
  await input.waitFor();
  await input.click(); await page.keyboard.type(text); await page.keyboard.press('Enter');
  await page.getByText(waitText, { exact: false }).waitFor({ timeout: 90000 });
  await page.waitForTimeout(1500);
};
const groupLabels = async (page) => {
  const groups = page.locator('#chat button.shiny-chat-tool-group__row', { hasText: 'Ran a trusted calculation' });
  const n = await groups.count();
  for (let i = 0; i < n; i++) { if ((await groups.nth(i).getAttribute('aria-expanded')) !== 'true') await groups.nth(i).click(); }
  await page.waitForTimeout(500);
  return page.$$eval('#chat .shiny-chat-tool-call-row__label', ls => ls.map(l => l.textContent.trim()));
};
const rowTitles = (page) => page.$$eval('#chat button.shiny-chat-tool-group__row', bs => bs.map(b => b.textContent.replace(/\s+/g, ' ').trim()));
const expandAll = async (page) => {
  for (let round = 0; round < 20; round++) {
    const closed = page.locator('#chat button.shiny-chat-tool-call-row__summary[aria-expanded="false"]');
    if ((await closed.count()) === 0) break;
    await closed.first().click(); await page.waitForTimeout(300);
  }
  await page.waitForTimeout(1000);
  return page.evaluate(() => ({
    tables: document.querySelectorAll('#chat table').length,
    charts: [...document.querySelectorAll('#chat img')].filter(i => i.src.startsWith('data:image/png') && i.naturalWidth > 0).length,
    scripts: document.querySelectorAll('#chat script').length,
    contained: document.querySelectorAll('#chat .deputy-display').length,
  }));
};
(async () => {
  const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
  const errors = [];
  const watch = (page) => { page.on('pageerror', e => errors.push(e.message)); };

  // Session A: the first question, then a second delegation to sales.
  const a = await browser.newPage({ viewport: { width: 1400, height: 1500 } }); watch(a);
  await a.goto(APP);
  const m0 = await metrics(a);
  await ask(a, 'Report revenue by region and on-time delivery.', 'ROOT: Sales reported revenue by region');
  const titlesA = await rowTitles(a);
  check('A: delegations and grouped measures shown', titlesA.some(t => t.startsWith('Used ask_sales')) && titlesA.some(t => /Used ask_ops.*failed/.test(t)) && titlesA.some(t => t.startsWith('Ran a trusted calculation') && t.includes('×4')) && titlesA.some(t => /Used ask_auditor\s*:\s*sales/.test(t)), titlesA);
  const labelsA = await groupLabels(a);
  check('A: measure cards labelled by subagent', JSON.stringify([...labelsA].sort()) === JSON.stringify(['auditor (via sales)', 'ops', 'sales', 'sales']), labelsA);
  const shownA = await expandAll(a);
  check('A: Commons table and chart render, inert and contained', shownA.tables >= 1 && shownA.charts >= 1 && shownA.scripts === 0 && shownA.contained > 0, shownA);
  const trustedA = await a.$$eval('#trusted-results tbody tr', rows => rows.map(r => [...r.cells].map(c => c.textContent.trim())));
  check('A: four trusted measures, each once, with producer', trustedA.length === 4 && new Set(trustedA.map(r => r[0])).size === 4, trustedA);
  check('A: no measure card failed', !(await rowTitles(a)).some(t => t.startsWith('Ran a trusted calculation') && t.includes('failed')));
  await a.screenshot({ path: SP + '/shot-A1.png', fullPage: true });
  await ask(a, 'Ask sales again.', 'ROOT: Sales confirmed the total revenue.');
  const allLabels = await a.$$eval('#chat .shiny-chat-tool-group__row, #chat .shiny-chat-tool-call-row__label', bs => bs.map(b => b.textContent.replace(/\s+/g, ' ').trim()));
  check('A: second delegation to sales is "sales #2"', allLabels.some(t => t.includes('sales #2')), allLabels.filter(t => t.includes('sales')));
  const trustedA2 = await a.$$eval('#trusted-results tbody tr', rows => rows.length);
  check('A: fifth trusted measure recorded', trustedA2 === 5, trustedA2);
  await a.screenshot({ path: SP + '/shot-A2.png', fullPage: true });
  const mA = await metrics(a);
  await a.close();

  // Session B: a new session reopens the saved conversation.
  const b = await browser.newPage({ viewport: { width: 1400, height: 1500 } }); watch(b);
  await b.goto(APP);
  await b.locator('#chat [contenteditable="true"]').waitFor();
  await b.waitForTimeout(1000);
  check('B: counts unchanged on a new session', (await metrics(b)) === mA, [mA, await metrics(b)]);
  await b.locator('#chat button[aria-label="Conversation history"]').click();
  await b.locator('.shiny-chat-history-drawer').getByText('Report revenue by region', { exact: false }).first().click();
  await b.getByText('ROOT: Sales confirmed the total revenue.', { exact: false }).waitFor({ timeout: 30000 });
  await b.waitForTimeout(2500);
  const titlesB = await rowTitles(b);
  check('B: reopened conversation shows the same activity', titlesB.length === titlesA.length + 2 || titlesB.length >= titlesA.length, titlesB);
  const labelsB = await groupLabels(b);
  check('B: same labels after reopening', labelsB.filter(l => ['sales', 'ops', 'auditor (via sales)'].includes(l)).length >= 4, labelsB);
  const shownB = await expandAll(b);
  check('B: table and chart replayed, inert', shownB.tables >= 1 && shownB.charts >= 1 && shownB.scripts === 0, shownB);
  const allB = await b.$$eval('#chat .shiny-chat-tool-group__row, #chat .shiny-chat-tool-call-row__label', bs => bs.map(x => x.textContent.replace(/\s+/g, ' ').trim()));
  check('B: "sales #2" kept after reopening', allB.some(t => t.includes('sales #2')));
  await b.waitForTimeout(3000);
  check('B: reopening ran nothing (requests and measure runs unchanged)', (await metrics(b)) === mA, [mA, await metrics(b)]);
  check('B: no trusted result delivered in the reopening session', (await b.textContent('#trusted')).includes('No trusted measure has run'));
  const panelB = (await b.textContent('#subagents-activity').catch(() => '')) || (await b.textContent('#subagents'));
  check('B: subagent panel lists the saved subagents', /sales/.test(panelB) && /ops/.test(panelB) && /auditor/.test(panelB), panelB.replace(/\s+/g, ' ').slice(0, 300));
  const options = await b.$$eval('#subagents-choice option', os => os.map(o => ({ v: o.value, t: o.textContent.trim() })));
  const sales = options.find(o => /sales/.test(o.t) && o.v);
  if (sales) { await b.selectOption('#subagents-choice', sales.v); await b.waitForTimeout(2500); }
  const transcript = await b.evaluate(() => {
    const t = document.querySelector('#subagents-transcript');
    const visible = el => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
    return { text: t ? t.textContent.replace(/\s+/g, ' ').slice(0, 300) : '', visibleInputs: t ? [...t.querySelectorAll('[contenteditable="true"], textarea')].filter(visible).length : -1 };
  });
  check('B: a saved subagent conversation opens read-only', /call_measure|revenue|Ran a trusted calculation/i.test(transcript.text) && transcript.visibleInputs === 0, transcript);
  await b.screenshot({ path: SP + '/shot-B.png', fullPage: true });
  check('B: still nothing ran', (await metrics(b)) === mA, [mA, await metrics(b)]);
  await b.close();

  // Session C: cancel a slow subagent from the panel.
  const c = await browser.newPage({ viewport: { width: 1400, height: 1500 } }); watch(c);
  await c.goto(APP);
  const input = c.locator('#chat [contenteditable="true"][aria-label="Chat message"]');
  await input.waitFor();
  const mC0 = await metrics(c);
  await input.click(); await c.keyboard.type('Run a slow operations check.'); await c.keyboard.press('Enter');
  let opsValue = null;
  for (let i = 0; i < 40 && !opsValue; i++) {
    await c.waitForTimeout(250);
    const os = await c.$$eval('#subagents-choice option', os => os.map(o => ({ v: o.value, t: o.textContent.trim() })));
    const o = os.find(o => /ops/.test(o.t) && o.v); if (o) opsValue = o.v;
  }
  check('C: running ops appears in the panel', !!opsValue);
  await c.selectOption('#subagents-choice', opsValue);
  await c.locator('#subagents-cancel').waitFor({ timeout: 10000 });
  await c.screenshot({ path: SP + '/shot-C-running.png', fullPage: true });
  await c.locator('#subagents-cancel').click();
  await c.getByText('ROOT: The operations check stopped before it finished.', { exact: false }).waitFor({ timeout: 30000 });
  await c.waitForTimeout(1500);
  await c.locator('#chat button.shiny-chat-tool-group__row', { hasText: 'ask_ops' }).click();
  await c.waitForTimeout(800);
  const opsDetail = await c.evaluate(() => [...document.querySelectorAll('#chat .shiny-chat-tool-call-row__detail:not([hidden]), #chat .shiny-chat-tool-group .shiny-chat-tool-call-row__detail')].map(d => d.textContent.replace(/\s+/g, ' ')).join(' '));
  check('C: the root\'s call to ops reports the cancelled subagent as stopped', /"status\\?":\\?"stopped/.test(opsDetail) && /user_cancelled/.test(opsDetail), (opsDetail.match(/"status[^,]*,[^,]*/) || [''])[0]);
  const mC = await metrics(c);
  const runs = s => Number(s.match(/(\d+) measure runs/)[1]);
  check('C: no measure ran', runs(mC) === runs(mC0), [mC0, mC]);
  check('C: no trusted result', (await c.textContent('#trusted')).includes('No trusted measure has run'));
  await c.screenshot({ path: SP + '/shot-C.png', fullPage: true });
  await c.close();

  check('no page errors', errors.length === 0, errors);
  console.log('chromium', browser.version());
  await browser.close();
  const passed = checks.filter(x => x.ok).length;
  console.log(`SUMMARY ${passed}/${checks.length} passed; screenshots in ${SP}`);
  process.exit(passed === checks.length ? 0 : 1);
})().catch(e => { console.error('SCRIPT ERROR', e); process.exit(1); });
