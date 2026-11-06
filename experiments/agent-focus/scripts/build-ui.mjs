import { build } from 'esbuild';
import { readFile, mkdir, writeFile, rename } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const demoLanguage = process.env.DO_CARD_DEMO_LANGUAGE ?? '';
if (!['', 'en', 'zh-Hant'].includes(demoLanguage)) throw new Error('DO_CARD_DEMO_LANGUAGE must be en, zh-Hant or unset');
const bundled = await build({ entryPoints: [new URL('src/ui/focus-picker.mjs', root).pathname],
  bundle: true, write: false, format: 'iife', platform: 'browser', target: 'es2022', minify: true,
  loader: { '.png': 'dataurl' },
  define: { __DO_CARD_DEMO_LANGUAGE__: JSON.stringify(demoLanguage) } });
const template = await readFile(new URL('src/ui/focus-picker.html', root), 'utf8');
const notices = await Promise.all(['README.md', 'Dashboard-Icons-LICENSE.txt'].map(file =>
  readFile(new URL(`src/ui/icons/${file}`, root), 'utf8')));
await mkdir(new URL('dist/', root), { recursive: true });
const temporary = new URL(`dist/focus-picker-${process.pid}.tmp`, root);
await writeFile(temporary,
  template.replace('__FOCUS_APP_JS__', () => bundled.outputFiles[0].text) +
  `\n<!-- Third-party artwork notices\n${notices.join('\n\n').replaceAll('--', '—')}\n-->`);
await rename(temporary, new URL('dist/focus-picker.html', root));
