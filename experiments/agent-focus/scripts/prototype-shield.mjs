// THROWAWAY: local visual comparison only. No relay, phone or signing connections.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
const page = new URL('../../../tools/shield-prototype/index.html', import.meta.url);
const port = Number(process.env.SHIELD_PROTOTYPE_PORT ?? 8804);
createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  if (url.pathname !== '/prototype/blocking-screen' && url.pathname !== '/') {
    res.writeHead(404); res.end(); return;
  }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
  res.end(await readFile(page));
}).listen(port, '127.0.0.1', () => console.log(`Shield prototype: http://127.0.0.1:${port}/prototype/blocking-screen?variant=A`));
