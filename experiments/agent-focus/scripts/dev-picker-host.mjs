// Isolated development host: real MCP Apps bridge + MCP client + HTTP relay.
// The in-memory phone fixture is explicit. No live device or developer credentials.
import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { build } from 'esbuild';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createRelay } from '../src/relay.mjs';
import { createFocusMcp } from '../src/mcp.mjs';
const port = Number(process.env.FOCUS_UI_PORT ?? 8792);
const origin = `http://127.0.0.1:${port}`;
const appGroups = [{ id: 'default', name: 'Saved apps' }, { id: 'deep-work', name: 'Deep Work' }];
const token = randomBytes(32).toString('hex');
const relay = createRelay({ agentToken: token, database: ':memory:' });
await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
const relayURL = `http://127.0.0.1:${relay.server.address().port}`;
async function phoneRequest(path, body, credential = token) {
  const res = await fetch(relayURL + path, { method: body === undefined ? 'GET' : 'POST',
    headers: { authorization: `Bearer ${credential}`, 'content-type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  return res.json();
}
const invite = await phoneRequest('/v1/pairings', {});
const fixture = await phoneRequest('/v1/pairings/redeem', { code: invite.code });
await phoneRequest('/v1/device/snapshot', { modeID: 'development-mode', maximumMinutes: 45,
  requiresRenewalApproval: false, startMinute: 0, endMinute: 1440, timeZone: 'Asia/Taipei', appGroups }, fixture.deviceToken);
const server = createFocusMcp({ relayURL, agentToken: token });
const client = new Client({ name: 'DO development host', version: '0.2.0' });
const [a, b] = InMemoryTransport.createLinkedPair();
await server.connect(b); await client.connect(a);
const hostJs = (await build({ entryPoints: [new URL('./picker-host-ui.mjs', import.meta.url).pathname],
  bundle: true, write: false, platform: 'browser', format: 'iife', minify: true })).outputFiles[0].text;
const page = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DO · MCP Apps integration check</title>
<style>body{font:14px system-ui;background:#e9ede2;color:#263c2c;margin:0}header{padding:20px 30px;border-bottom:1px solid #ccd6c2;display:flex;justify-content:space-between;gap:15px}main{max-width:900px;margin:25px auto;padding:0 20px}button,input{font:inherit;padding:10px 14px;border:1px solid #b2c2a6;border-radius:8px;background:#fff;color:#263c2c}input{min-width:0;flex:1}.tools{display:flex;gap:8px;margin:15px 0}iframe{width:100%;height:680px;border:1px solid #c1d0b7;border-radius:15px;background:#f5f5ee}.chat{display:flex;gap:10px;margin-top:14px}#message{font-size:12px;line-height:1.6}pre{font-size:11px;white-space:pre-wrap}.tiny{font-size:11px;color:#62775a}</style>
<header><b>DO · MCP Apps integration check</b><span class="tiny">ISOLATED TEST PHONE · NO LIVE COMMANDS</span></header><main><div class="tools"><button id="session">Choose session</button><button id="maximum">Change maximum</button><button id="ack">Simulate phone acknowledgement</button></div><p class="tiny">These open the two real MCP tools. Both load the same bundled App resource.</p><iframe id="view" title="DO focus timeline" sandbox="allow-scripts allow-same-origin"></iframe><form class="chat"><input id="revision" placeholder="Revise in chat: 20 minutes" aria-label="Revise the current picker in chat"><button>Send revision</button></form><p id="message" role="status"></p><details><summary>Host / model context</summary><pre id="state"></pre></details></main><script>${hostJs}</script>`;
const host = createServer(async (req, res) => {
  // Cross-site pages cannot call this loopback harness's tools.
  if (req.headers.origin && req.headers.origin !== origin) { res.writeHead(403); res.end(); return; }
  const url = new URL(req.url, origin);
  try {
    if (req.method === 'GET' && url.pathname === '/') { res.writeHead(200, { 'content-type': 'text/html' }); res.end(page); return; }
    if (req.method === 'GET' && url.pathname === '/view') {
      const resource = await client.readResource({ uri: 'ui://docard/focus-timeline.html' });
      res.writeHead(200, { 'content-type': 'text/html' }); res.end(resource.contents[0].text); return;
    }
    if (req.method === 'POST' && url.pathname === '/tool') {
      let raw = ''; for await (const chunk of req) { raw += chunk; if (raw.length > 8192) throw new Error('too_large'); }
      const input = JSON.parse(raw);
      if (input.name === 'select_focus_session' || input.name === 'select_focus_maximum') input.arguments.deviceId = fixture.deviceId;
      const result = await client.callTool(input);
      res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(result)); return;
    }
    if (req.method === 'POST' && url.pathname === '/ack') {
      const { commands } = await phoneRequest('/v1/device/commands', undefined, fixture.deviceToken);
      for (const command of commands) {
        await phoneRequest('/v1/device/receipts', { id: command.id, status: 'applied' }, fixture.deviceToken);
        if (command.action === 'set_maximum') await phoneRequest('/v1/device/snapshot', {
          modeID: `development-${command.id}`, maximumMinutes: command.maximumMinutes,
          requiresRenewalApproval: false, startMinute: 0, endMinute: 1440, timeZone: 'Asia/Taipei', appGroups,
        }, fixture.deviceToken);
      }
      res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ acknowledged: commands.length })); return;
    }
    res.writeHead(404); res.end();
  } catch (error) { res.writeHead(500, { 'content-type': 'application/json' }); res.end(JSON.stringify({ error: error.message })); }
});
host.listen(port, '127.0.0.1', () => console.log(`Isolated MCP Apps host: ${origin}`));
const shutdown = () => host.close(async () => { await client.close(); await server.close(); relay.server.close(() => { relay.close(); process.exit(0); }); });
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
