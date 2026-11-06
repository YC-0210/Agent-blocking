import { build } from 'esbuild';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const bundled = await build({ entryPoints: [new URL('src/ui/focus-picker.mjs', root).pathname],
  loader: { '.svg': 'text' }, bundle: true, write: false, format: 'iife', platform: 'browser', target: 'es2022', minify: true });
const template = await readFile(new URL('src/ui/focus-picker.html', root), 'utf8');
await mkdir(new URL('dist/', root), { recursive: true });
await writeFile(new URL('dist/focus-picker.html', root), template.replace('__FOCUS_APP_JS__', () => bundled.outputFiles[0].text));
