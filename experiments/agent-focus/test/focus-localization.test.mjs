import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { resolveLocale, translate, errorMessage, rejectionMessage } from '../src/ui/focus-i18n.mjs';

async function picker(locale, languages = ['en-US'], toolHandler) {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { hidden: true, style: {}, children: [],
      replaceChildren(...children) { this.children = children; },
      append(child) { this.children.push(child); },
      setAttribute(name, value) { this[name] = value; } });
    return elements.get(id);
  };
  const document = { documentElement: {}, getElementById: element, querySelector: element,
    createElement: () => ({ children: [], append(...children) { this.children.push(...children); },
      setAttribute(name, value) { this[name] = value; } }) };
  let host;
  const calls = [];
  class App {
    constructor() { host = this; }
    connect() { return Promise.resolve(); }
    getHostContext() { return { locale }; }
    updateModelContext() { return Promise.resolve(); }
    async callServerTool(args) { calls.push(args); if (toolHandler) return toolHandler(args); throw new Error('Unexpected command'); }
  }
  const source = readFileSync(new URL('../src/ui/focus-picker.mjs', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '');
  vm.runInNewContext(source, { App, resolveLocale, translate, errorMessage, rejectionMessage,
    document, navigator: { languages }, Intl, Date, setInterval: () => 1, clearInterval() {},
    setTimeout: () => 1, clearTimeout() {} });
  await new Promise(resolve => setImmediate(resolve));
  return { host, calls, document, element, show(selection) {
    host.ontoolresult({ structuredContent: { selection: { id: 'test', revision: 1, kind: 'session',
      minutes: 30, minMinutes: 2, maxMinutes: 45, currentMaximumMinutes: 45,
      timeZone: 'Asia/Taipei', phase: 'draft', selectionSummary: { applications: 3, categories: 0, websites: 0 }, ...selection } } });
  } };
}

test('Taiwan/Hant locale selection respects host language, browser fallback and English', () => {
  for (const language of ['zh-TW', 'zh_Hant_TW', 'zh-Hant', 'zh-HK', 'zh']) assert.equal(resolveLocale(language), 'zh-Hant');
  assert.equal(resolveLocale('en-US', ['zh-TW']), 'en');
  assert.equal(resolveLocale(undefined, ['zh-TW', 'en-US']), 'zh-Hant');
  assert.equal(resolveLocale('zh-CN'), 'en');
  assert.equal(resolveLocale('fr-FR'), 'en');
});

test('Taiwan session and maximum pickers share Chinese slider copy without sending commands', async () => {
  const ui = await picker('zh-TW');
  ui.show({});
  assert.equal(ui.document.documentElement.lang, 'zh-Hant');
  assert.equal(ui.element('label[for=minutes]').textContent, '分鐘');
  assert.equal(ui.element('confirm').textContent, '開始專注');
  assert.equal(ui.element('timeline')['aria-label'], '拖曳以調整本次專注時間');
  ui.show({ kind: 'maximum', minutes: 170, minMinutes: 15, maxMinutes: 1440 });
  assert.equal(ui.element('confirm').textContent, '儲存時間上限');
  assert.equal(ui.element('timeline')['aria-valuetext'], '170 分鐘');
  assert.deepEqual(ui.calls, []);
});

test('Chinese pending, unknown, applied and elapsed receipts retain distinct meanings', async () => {
  const ui = await picker('zh-Hant');
  ui.show({ phase: 'pending' });
  assert.equal(ui.element('confirm').textContent, '等待手機確認…');
  assert.match(ui.element('status').textContent, /尚未確認設定是否生效/);
  ui.show({ phase: 'unknown' });
  assert.equal(ui.element('confirm').disabled, false);
  assert.match(ui.element('status').textContent, /不會重複建立/);
  ui.show({ phase: 'applied', command: { issuedAt: Date.now() } });
  assert.equal(ui.element('confirm').textContent, '已開始專注');
  ui.show({ phase: 'applied', command: { issuedAt: Date.now() - 31 * 60000 } });
  assert.equal(ui.element('confirm').textContent, '已到預計結束時間');
  assert.match(ui.element('status').textContent, /先前的確認僅代表/);
});

test('Chinese errors and rejection reasons do not expose raw server codes', async () => {
  const ui = await picker('zh-TW');
  ui.show({ phase: 'rejected', reason: 'mode_not_approved' });
  assert.match(ui.element('status').textContent, /手機上的設定已變更/);
  assert.doesNotMatch(ui.element('status').textContent, /mode_not_approved/);
  ui.show({ phase: 'rejected', reason: 'outside_approved_hours' });
  assert.match(ui.element('status').textContent, /允許的時段/);
  ui.show({ minutes: 46 });
  assert.equal(ui.element('confirm').disabled, true);
  assert.match(ui.element('error').textContent, /2 至 45 分鐘/);
  ui.host.ontoolresult({ isError: true, content: [{ type: 'text', text: 'selection_expired: open a new picker' }] });
  assert.match(ui.element('error').textContent, /此設定已過期/);
});

test('host locale changes retranslate the current picker without resetting draft edits', async () => {
  const ui = await picker('en-US');
  ui.show({});
  ui.element('minutes').oninput({ target: { value: '20' } });
  ui.host.onhostcontextchanged({ locale: 'zh-TW' });
  assert.equal(ui.element('minutes').value, '20');
  assert.equal(ui.element('confirm').textContent, '開始專注');
  ui.host.onhostcontextchanged({ locale: 'en' });
  assert.equal(ui.element('confirm').textContent, 'Start focus');
  assert.equal(ui.element('timeline')['aria-valuetext'], '20 minutes');
  assert.deepEqual(ui.calls, []);
});

test('the picker displays multiple selected apps without identity setup or manual refresh', async () => {
  const ui = await picker('zh-TW');
  ui.show({});
  assert.equal(ui.element('selection-label').textContent, '已選取 3 個 App');
  assert.equal(ui.element('confirm').disabled, false);
  assert.deepEqual(ui.calls, []);
  ui.element('minutes').oninput({ target: { value: '17' } });
  ui.show({ revision: 2, selectionSummary: { applications: 5, categories: 0, websites: 0 } });
  assert.equal(ui.element('selection-label').textContent, '已選取 5 個 App');
  assert.equal(ui.element('minutes').value, '17');
  ui.show({ kind: 'maximum', minutes: 45, minMinutes: 15, maxMinutes: 1440 });
  assert.equal(ui.element('groups').hidden, true);
});

test('missing private selection counts require phone sync without inventing app identities', async () => {
  const ui = await picker('en');
  ui.show({ selectionSummary: undefined });
  assert.equal(ui.element('confirm').disabled, true);
  assert.equal(ui.element('confirm').textContent, 'Choose apps on iPhone');
  assert.deepEqual(ui.calls, []);
});

test('a count refresh arriving during a time edit preserves that time and rebases its revision', async () => {
  const current = { id: 'test', kind: 'session', revision: 2, minutes: 30, phase: 'draft',
    minMinutes: 2, maxMinutes: 45, currentMaximumMinutes: 45, timeZone: 'Asia/Taipei',
    selectionSummary: { applications: 5, categories: 0, websites: 0 } };
  const ui = await picker('en', ['en-US'], async ({ name, arguments: args }) => {
    if (name === 'focus_selection_status') return { structuredContent: { selection: current } };
    if (name === 'revise_focus_selection' && args.expectedRevision === 2) {
      return { structuredContent: { selection: { ...current, revision: 3, minutes: args.minutes } } };
    }
    return { isError: true, content: [{ type: 'text', text: 'selection_changed' }] };
  });
  ui.show({});
  ui.element('minutes').oninput({ target: { value: '17' } });
  ui.show(current);
  await ui.element('minutes').onchange();
  assert.equal(ui.element('minutes').value, '17');
  assert.equal(ui.element('selection-label').textContent, '5 selected apps');
  assert.equal(ui.calls[0].arguments.expectedRevision, 2);
  assert.equal(ui.calls.some(call => call.name === 'confirm_focus_selection'), false);
});
