const assert = require("node:assert/strict");
const { pathToFileURL } = require("node:url");
const { existsSync } = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright");
(async () => {
  const file = process.argv[2];
  if (!file) throw new Error("Supply the generated artifact page path.");
  const executablePath = process.env.CHROMIUM_PATH ??
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  const browser = await chromium.launch({
    executablePath: existsSync(executablePath) ? executablePath : undefined
  });
  try {
    const page = await browser.newPage();
    const external = [];
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.route(/^https?:/, async route => {
      external.push(route.request().url());
      await route.abort();
    });
    await page.goto(pathToFileURL(path.resolve(file)).href);
    assert.equal(await page.locator('iframe[sandbox="allow-scripts"]').count(), 5);
    const frames = page.frames().slice(1);
    assert.equal(frames.length, 5);
    const [dt, plotly, leaflet, gt, flextable] = frames;
    const table = dt.locator("table.dataTable");
    await table.waitFor();
    assert.match(await table.locator("tbody tr").first().textContent(), /zeta/);
    await table.locator("thead th").first().click();
    await dt.waitForFunction(() => document.querySelector("tbody tr").textContent.includes("alpha"));
    const search = dt.locator('input[type="search"]').first();
    await search.fill("alpha");
    await dt.waitForFunction(() => document.querySelectorAll("tbody tr").length === 1);
    console.log("DT sorting and filtering passed");
    await plotly.waitForFunction(() => document.querySelector(".plotly")?.data?.some(trace => trace.type === "scatter" && trace.mode.includes("markers")));
    console.log("Plotly marker trace passed");
    await leaflet.locator(".leaflet-interactive").first().click();
    assert.match(await leaflet.locator(".leaflet-popup-content").textContent(), /Local station/);
    console.log("Leaflet marker popup passed");
    for (const frame of [gt, flextable]) {
      assert.match(await frame.locator("table").first().textContent(), /A/);
    }
    console.log("gt and flextable display passed");
    for (const frame of frames) {
      assert.equal(await frame.evaluate(() => {
        try { return window.top.document.title; } catch (error) { return error.name; }
      }), "SecurityError");
    }
    assert.deepEqual(external, []);
    assert.deepEqual(errors, []);
    console.log("Opaque origin, offline resources, and zero page errors verified in Chrome", browser.version());
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
