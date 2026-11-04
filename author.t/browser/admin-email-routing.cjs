const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const [port, directory, apiPort, scenario] = process.argv.slice(2);
const base = `http://127.0.0.1:${port}`;
(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ ignoreHTTPSErrors: true });
    const { session } = JSON.parse(fs.readFileSync(path.join(directory, 'input.json')));
    await context.addCookies([{ name: 'session_id', value: session, url: base }]);
    const page = await context.newPage();
    // Wing ships separate web and REST PSGI apps; preserve the public authority.
    await page.route(`${base}/api/**`, async route => {
      const response = await route.fetch({
        url: route.request().url().replace(`:${port}/`, `:${apiPort}/`),
        headers: { ...route.request().headers(), host: `127.0.0.1:${port}` },
      });
      await route.fulfill({ response });
    });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const documentResponse = await page.goto(`${base}/admin/wingman/tubes/admin.viewed`);
    assert.equal(documentResponse.status(), 200, await documentResponse.text());
    await page.waitForFunction(() => document.querySelector('#app')?.__vue__).catch(error => { throw new Error(errors.join('\n') || error.message); });
    await page.locator('[name=arguments]').fill('{}');
    const jobs = [];
    const emailPhases = scenario === 'aliases' ? ['AdminMailAlias', 'MailAlias'] : ['EmailAllAdmins', 'SendTemplatedEmail'];
    for (const phase of [...emailPhases, 'howdy', emailPhases[0], 'howdy']) {
      await page.locator('[name=phase]').fill(phase);
      const responsePromise = page.waitForResponse(r => r.url() === `${base}/api/wingman/jobs` && r.request().method() === 'POST');
      await page.getByRole('button', { name: 'Add Job', exact: true }).click();
      const response = await responsePromise;
      assert.equal(response.status(), 200, await response.text());
      const sent = response.request().postDataJSON();
      const email = emailPhases.includes(phase);
      assert.equal(sent.tube, email ? undefined : 'admin.viewed', `${phase}: submission tube`);
      const { result } = await response.json();
      const tube = email ? (scenario.startsWith('legacy') ? 'wingman_test' : 'wingman.email') : 'admin.viewed';
      jobs.push({ id: result.id, tube, phase });
      await page.evaluate(() => Vue.nextTick());
      assert.equal(await page.locator(`#app a[href='/admin/wingman/jobs/${result.id}']`).count(), email ? 0 : 1,
        'email routed elsewhere must not appear in the viewed tube');
    }
    fs.writeFileSync(path.join(directory, 'jobs.json'), JSON.stringify(jobs));
    if (process.env.ADMIN_EMAIL_ARTIFACTS && scenario === 'configured') {
      const loaded = page.waitForResponse(r => r.url() === `${base}/api/wingman/tubes/admin.viewed/jobs`);
      await page.reload();
      await loaded;
      await page.waitForFunction(() => document.querySelector('#app')?.__vue__);
      fs.mkdirSync(process.env.ADMIN_EMAIL_ARTIFACTS, { recursive: true });
      for (const width of [1440, 390]) for (const colorScheme of ['light', 'dark']) {
        await page.setViewportSize({ width, height: 1000 });
        await page.emulateMedia({ colorScheme });
        await page.screenshot({ path: path.join(process.env.ADMIN_EMAIL_ARTIFACTS, `admin-email-${width}-${colorScheme}.png`), fullPage: true });
      }
    }
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
