const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const [webPort, apiPort, directory] = process.argv.slice(2);
const base = `http://127.0.0.1:${webPort}`;
(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ ignoreHTTPSErrors: true });
    const { session, user_id: userId, key_id: keyId } = JSON.parse(fs.readFileSync(path.join(directory, 'input.json')));
    await context.addCookies([{ name: 'session_id', value: session, url: base }]);
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    // Wing serves web and REST apps separately, with one public authority.
    await page.route(`${base}/api/**`, async route => {
      const response = await route.fetch({
        url: route.request().url().replace(`:${webPort}/`, `:${apiPort}/`),
        headers: { ...route.request().headers(), host: `127.0.0.1:${webPort}` },
      });
      await route.fulfill({ response });
    });
    const account = await page.goto(`${base}/account`);
    assert.equal(account.status(), 200, await account.text());
    await page.waitForFunction(() => document.querySelector('#app')?.__vue__);
    assert.equal(await page.locator('#username').inputValue(), 'account-render');
    assert.equal(await page.locator('#email').inputValue(), 'account-render@example.invalid');
    const saved = page.waitForResponse(r => r.url().split('?')[0] === `${base}/api/user/${userId}` && r.request().method() === 'PUT');
    await page.locator('#real_name').fill('Browser Updated Owner');
    await page.locator('#real_name').press('Enter');
    const update = await saved;
    assert.equal(update.status(), 200, await update.text());
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#app')?.__vue__);
    assert.equal(await page.locator('#real_name').inputValue(), 'Browser Updated Owner');
    async function screenshots(name) {
      if (!process.env.ACCOUNT_PAGE_ARTIFACTS) return;
      await page.locator('#wingajaxprogress .progress').waitFor({ state: 'hidden' });
      fs.mkdirSync(process.env.ACCOUNT_PAGE_ARTIFACTS, { recursive: true });
      for (const width of [1440, 390]) for (const colorScheme of ['light', 'dark']) {
        await page.setViewportSize({ width, height: 1000 });
        await page.emulateMedia({ colorScheme });
        await page.screenshot({ path: path.join(process.env.ACCOUNT_PAGE_ARTIFACTS, `${name}-${width}-${colorScheme}.png`), fullPage: true });
      }
    }
    await screenshots('account');
    const loaded = page.waitForResponse(r => r.url().startsWith(`${base}/api/user/${userId}/apikeys`));
    const keys = await page.goto(`${base}/account/apikeys`);
    assert.equal(keys.status(), 200, await keys.text());
    const list = await loaded;
    assert.equal(list.status(), 200, await list.text());
    await page.getByRole('link', { name: 'rendered-key', exact: true }).waitFor();
    assert.equal(await page.getByRole('link', { name: 'rendered-key', exact: true }).getAttribute('href'), `/account/apikeys/${keyId}`);
    await screenshots('apikeys');
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
