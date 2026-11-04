const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { chromium } = require('playwright');
const assets = process.argv[2];

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ timezoneId: 'America/Chicago', locale: 'en-US' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.setContent('<main id="app" style="padding:16px"></main>');
    for (const name of ['bootstrap', 'bootstrap-vue']) {
      await page.addStyleTag({ path: path.join(assets, name + '.css') });
    }
    for (const name of ['vue', 'bootstrap-vue', 'lodash', 'qs', 'axios', 'luxon']) {
      await page.addScriptTag({ path: path.join(assets, name + '.js') });
    }
    await page.addScriptTag({ path: path.resolve('public/wing.vue.js') });
    await page.evaluate(() => {
      window.app = new Vue({
        el: '#app',
        data: { value: '2026-07-15 18:34:56', manual: false, wrap: false, inputs: [], changes: [] },
        template: `<main id="app" style="padding:16px">
          <luxon-date-time id="subject" v-model="value" :allow_manual_entry="manual" :wrap="wrap"
            @input="inputs.push($event)" @change="changes.push($event)"></luxon-date-time>
          <output>{{value}}</output></main>`
      });
      return Vue.nextTick();
    });
    for (const manual of [false, true]) for (const wrap of [false, true]) {
      await page.evaluate(async ({ manual, wrap }) => {
        Object.assign(app, { manual, wrap, value: '2026-07-15 18:34:56', inputs: [], changes: [] });
        await Vue.nextTick();
      }, { manual, wrap });
      for (const width of [390, 1440]) for (const colorScheme of ['light', 'dark']) {
        await page.setViewportSize({ width, height: 700 });
        await page.emulateMedia({ colorScheme });
        const artifact = process.env.WING_UI_ARTIFACTS;
        if (artifact) {
          fs.mkdirSync(artifact, { recursive: true });
          await page.screenshot({ path: path.join(artifact, `${manual ? 'manual' : 'picker'}-wrap-${wrap}-${width}-${colorScheme}.png`) });
        }
        const geometry = await page.locator('#subject .b-form-btn-label-control > label:not(.sr-only)').evaluateAll(labels => labels.map(label => {
          const range = document.createRange();
          range.selectNodeContents(label);
          const text = range.getBoundingClientRect();
          const box = label.getBoundingClientRect();
          return { text: label.textContent, textHeight: text.height, lineHeight: parseFloat(getComputedStyle(label).lineHeight), left: box.left, right: box.right };
        }));
        assert(geometry.length >= 1, 'Mounted date label must exist');
        for (const box of geometry) {
          assert(box.textHeight <= box.lineHeight + 1, `${manual ? 'manual' : 'picker'} wrap=${wrap} ${width}: label wraps into narrow columns: ${JSON.stringify(box)}`);
          assert(box.left >= 0 && box.right <= width, 'Controls must fit the viewport');
        }
        if (manual) {
          const input = page.locator('#subject input[type=text]');
          assert.equal(await input.inputValue(), '13:34:56');
          assert(await input.evaluate(el => el.clientWidth >= 90), 'Manual time must remain readable');
        }
        assert.equal(await page.locator('#subject').getByText('America/Chicago', { exact: true }).count(), 1);
      }
      if (manual && !wrap) {
        await page.setViewportSize({ width: 1440, height: 700 });
        assert(await page.locator('#subject').evaluate(el => {
          const date = el.querySelector('.b-form-datepicker').getBoundingClientRect();
          const input = el.querySelector('input[type=text]');
          return parseFloat(getComputedStyle(input).borderTopLeftRadius) === 0 || input.getBoundingClientRect().left > date.right;
        }), 'Rounded manual input must not collide with the adjacent date border');
      }
      await page.locator('#app').evaluate(el => { el.style.width = '240px'; });
      assert(await page.locator('#app').evaluate(el => el.scrollWidth <= el.clientWidth),
        'Date/time controls must also fit a narrow parent');
      await page.locator('#app').evaluate(el => { el.style.width = ''; });
      await page.setViewportSize({ width: 390, height: 700 });
      if (manual) {
        await page.locator('#subject input[type=text]').fill('09:10:11');
        await page.evaluate(() => Vue.nextTick());
        assert.deepEqual(await page.evaluate(() => [app.value, app.inputs.at(-1), app.changes.at(-1)]),
          ['2026-07-15 14:10:11', '2026-07-15 14:10:11', '2026-07-15 14:10:11'], 'Typing manual time must update the parent and emit both events');
      }
      await page.locator('#subject .b-form-datepicker button').first().click();
      await page.getByRole('button', { name: 'Thursday, July 16, 2026', exact: true }).click();
      const expected = manual ? '2026-07-16 14:10:11' : '2026-07-16 18:34:56';
      await page.waitForFunction(expected => app.value === expected, expected);
      assert.deepEqual(await page.evaluate(() => [app.inputs.at(-1), app.changes.at(-1)]), [expected, expected]);
      await page.locator('#subject .b-form-timepicker button').first().click();
      await page.getByRole('spinbutton').first().waitFor({ state: 'visible' });
      await page.getByRole('spinbutton', { name: 'Minutes', exact: true }).press('ArrowUp');
      const timeExpected = manual ? '2026-07-16 14:11:00' : '2026-07-16 18:35:00';
      await page.waitForFunction(previous => app.value !== previous, expected);
      assert.equal(await page.evaluate(() => app.value), timeExpected);
      assert.deepEqual(await page.evaluate(() => [app.inputs.at(-1), app.changes.at(-1)]), [timeExpected, timeExpected]);
      await page.getByRole('button', { name: 'Close', exact: true }).click();
      await page.evaluate(async () => { app.value = '2026-01-01 02:03:04'; await Vue.nextTick(); });
      await page.getByRole('button', { name: 'Wednesday, December 31, 2025 Selected date', exact: true }).waitFor({ state: 'visible' });
      if (manual) assert.equal(await page.locator('#subject input[type=text]').inputValue(), '20:03:04');
      else await page.getByRole('button', { name: '8:03 PM Selected time', exact: true }).waitFor({ state: 'visible' });
    }

    assert.deepEqual(errors, []);
    console.log('PASS: Chromium mounted layout, manual/date/time edits, input/change events and UTC/local prop updates in both modes and wraps');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
