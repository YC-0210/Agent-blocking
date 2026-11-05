import { AppBridge, PostMessageTransport } from '@modelcontextprotocol/ext-apps/app-bridge';
let bridge, selected;
const el = id => document.getElementById(id);
async function tool(params) {
  const res = await fetch('/tool', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(params) });
  const result = await res.json();
  if (result.structuredContent?.selection) selected = result.structuredContent.selection;
  el('state').textContent = JSON.stringify(result, null, 2);
  return result;
}
async function open(kind) {
  if (bridge) { await bridge.teardownResource({}).catch(() => {}); await bridge.close(); }
  const args = { deviceId: '00000000-0000-4000-8000-000000000001', suggestedMinutes: kind === 'maximum' ? 60 : 30,
    ...(kind === 'session' ? { issue: 'YAN-103' } : {}) };
  const result = await tool({ name: kind === 'maximum' ? 'select_focus_maximum' : 'select_focus_session', arguments: args });
  if (result.isError) { el('message').textContent = result.content[0].text; return; }
  const iframe = document.getElementById('view');
  bridge = new AppBridge(null, { name: 'DO isolated host', version: '0.2.0' }, { serverTools: {}, updateModelContext: {} });
  bridge.oncalltool = params => tool(params);
  bridge.onupdatemodelcontext = async params => { el('state').textContent = JSON.stringify(params, null, 2); return {}; };
  bridge.onsizechange = ({ height }) => { iframe.style.height = `${Math.max(500, height)}px`; };
  bridge.oninitialized = async () => { await bridge.sendToolInput({ arguments: args }); await bridge.sendToolResult(result); };
  // Connect the bridge before navigation, so the iframe's initial handshake cannot be missed.
  await bridge.connect(new PostMessageTransport(iframe.contentWindow, iframe.contentWindow));
  iframe.src = `/view?selection=${encodeURIComponent(selected.id)}`;
  el('message').textContent = `${kind === 'maximum' ? 'Maximum change' : 'Session'} picker opened. No command is sent until you confirm.`;
}
el('session').onclick = () => open('session').catch(error => { el('message').textContent = error.message; });
el('maximum').onclick = () => open('maximum').catch(error => { el('message').textContent = error.message; });
el('ack').onclick = async () => { const result = await (await fetch('/ack', { method: 'POST' })).json(); el('message').textContent = `Test phone acknowledged ${result.acknowledged} command(s).`; };
document.querySelector('form').onsubmit = async event => {
  event.preventDefault(); if (!selected) return;
  const minutes = Number(el('revision').value.match(/\d+/)?.[0]);
  const result = await tool({ name: 'revise_focus_selection', arguments: { selectionId: selected.id, minutes } });
  await bridge.sendToolResult(result); el('revision').value = '';
  el('message').textContent = result.isError ? result.content[0].text : 'Draft revised in chat. The saved maximum and phone are unchanged.';
};
open(new URLSearchParams(location.search).get('kind') === 'maximum' ? 'maximum' : 'session').catch(error => { el('message').textContent = error.message; });
