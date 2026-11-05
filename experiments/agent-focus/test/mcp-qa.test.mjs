import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createFocusMcp } from '../src/mcp.mjs';
import { createRelay } from '../src/relay.mjs';

// Real initialized MCP and HTTP/SQLite relay; only the device boundary is simulated.
async function fixture(t, { loseResponse = false } = {}) {
  const token = 'qa-fixture-agent-credential-at-least-32-characters';
  let clock = Date.now();
  const relay = createRelay({ agentToken: token, database: ':memory:', now: () => clock });
  await new Promise(r => relay.server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${relay.server.address().port}`;
  const proxy = loseResponse ? createServer(async (req, res) => {
    const chunks = []; for await (const c of req) chunks.push(c);
    const upstream = await fetch(url + req.url, { method: req.method,
      headers: { authorization: req.headers.authorization, 'content-type': 'application/json' },
      ...(chunks.length ? { body: Buffer.concat(chunks) } : {}) });
    const body = await upstream.text();
    if (loseResponse && req.method === 'POST' && /\/commands$/.test(req.url)) {
      loseResponse = false; res.destroy(); return;
    }
    res.writeHead(upstream.status, { 'content-type': 'application/json' }); res.end(body);
  }) : null;
  if (proxy) await new Promise(r => proxy.listen(0, '127.0.0.1', r));
  const connections = [];
  t.after(async () => {
    for (const { client, server } of connections) { await client.close(); await server.close(); }
    if (proxy) await new Promise(r => proxy.close(r));
    await new Promise(r => relay.server.close(r)); relay.close();
  });
  async function connect() {
    const server = createFocusMcp({ relayURL: proxy ? `http://127.0.0.1:${proxy.address().port}` : url,
      agentToken: token, now: () => clock });
    const client = new Client({ name: 'qa-codex', version: '1' });
    const [a,b] = InMemoryTransport.createLinkedPair(); await server.connect(b); await client.connect(a);
    connections.push({ client, server }); return client;
  }
  async function request(path, body, credential = token) {
    const response = await fetch(url + path, { method: body === undefined ? 'GET' : 'POST',
      headers: { authorization: `Bearer ${credential}`, 'content-type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    assert.ok(response.ok, `${path}: ${response.status}`); return response.json();
  }
  const invite = await request('/v1/pairings', {});
  const phone = await request('/v1/pairings/redeem', { code: invite.code });
  const snapshot = changes => request('/v1/device/snapshot', { modeID: 'approved', maximumMinutes: 45,
    requiresRenewalApproval: false, timeZone: 'Asia/Taipei', startMinute: 0, endMinute: 1440, ...changes }, phone.deviceToken);
  await snapshot();
  const client = await connect(), call = (name, args) => client.callTool({ name, arguments: args });
  const open = async (kind, suggestedMinutes) => {
    const r = await call(`select_focus_${kind}`, { deviceId: phone.deviceId, suggestedMinutes });
    assert.notEqual(r.isError, true, r.content?.[0]?.text); return r.structuredContent.selection;
  };
  const confirm = d => call('confirm_focus_selection', { selectionId: d.id, revision: d.revision, userConfirmed: true });
  const queue = async () => (await request('/v1/device/commands', undefined, phone.deviceToken)).commands;
  return { client, call, open, confirm, queue, snapshot, request, phone, token, connect, advance: ms => { clock += ms; } };
}
function rejected(result, reason) {
  assert.equal(result.isError, true); if (reason) assert.match(result.content[0].text, reason);
}

for (const minutes of [15, 1440]) test(`maximum boundary ${minutes} queues only a maximum policy command`, async t => {
  const f = await fixture(t); const d = await f.open('maximum', minutes);
  assert.equal((await f.confirm(d)).structuredContent.selection.phase, 'pending');
  const [c] = await f.queue(); assert.equal(c.action, 'set_maximum'); assert.equal(c.maximumMinutes, minutes);
  assert.equal(c.expectedMaximumMinutes, 45); assert.equal(c.userConfirmed, true);
  for (const k of ['sessionID', 'durationMinutes', 'renewalConfirmed']) assert.equal(k in c, false);
});
for (const minutes of [2, 1440]) test(`session boundary ${minutes} cannot alter the approved maximum`, async t => {
  const f = await fixture(t); await f.snapshot({ maximumMinutes: 1440 });
  await f.confirm(await f.open('session', minutes)); const [c] = await f.queue();
  assert.equal(c.action, 'start'); assert.equal(c.durationMinutes, minutes);
  assert.equal('maximumMinutes' in c, false); assert.equal('userConfirmed' in c, false);
  assert.equal((await f.request(`/v1/devices/${f.phone.deviceId}`)).snapshot.maximumMinutes, 1440);
});
test('malformed and out-of-range opening arguments never create commands', async t => {
  const f = await fixture(t);
  for (const [kind, values] of [['maximum', [14,1441,15.5,'60']], ['session', [1,1441,2.5,'30']]]) {
    for (const suggestedMinutes of values) rejected(await f.call(`select_focus_${kind}`, { deviceId: f.phone.deviceId, suggestedMinutes }));
  }
  rejected(await f.call('select_focus_session', { deviceId: 'not-a-device', suggestedMinutes: 30 }));
  assert.deepEqual(await f.queue(), []);
});
test('editing both purposes stays local and an over-limit session cannot escalate its maximum', async t => {
  const f = await fixture(t); const session = await f.open('session', 30), maximum = await f.open('maximum', 60);
  const edit = await f.call('revise_focus_selection', { selectionId: session.id, minutes: 45 });
  assert.equal(edit.structuredContent.selection.kind, 'session');
  rejected(await f.call('revise_focus_selection', { selectionId: session.id, minutes: 46 }), /duration_exceeds_approval/);
  rejected(await f.call('revise_focus_selection', { selectionId: maximum.id, minutes: 14 }));
  const maxEdit = await f.call('revise_focus_selection', { selectionId: maximum.id, minutes: 120 });
  assert.equal(maxEdit.structuredContent.selection.kind, 'maximum'); assert.deepEqual(await f.queue(), []);
  assert.equal((await f.request(`/v1/devices/${f.phone.deviceId}`)).snapshot.maximumMinutes, 45);
});
test('same-handle maximum changes invalidate both previously opened purposes', async t => {
  const f = await fixture(t); const session = await f.open('session', 30), maximum = await f.open('maximum', 60);
  await f.snapshot({ maximumMinutes: 90 });
  rejected(await f.confirm(session), /policy_changed/); rejected(await f.confirm(maximum), /policy_changed/);
  assert.deepEqual(await f.queue(), []);
});
test('a rotated approval invalidates a draft even when its maximum is unchanged', async t => {
  const f = await fixture(t); const draft = await f.open('session', 30); await f.snapshot({ modeID: 'emergency-rotated' });
  rejected(await f.confirm(draft), /policy_changed/); assert.deepEqual(await f.queue(), []);
});
test('maximum may change during a session while another start is refused', async t => {
  const f = await fixture(t); await f.snapshot({ sessionID: 'running', endAt: Date.now() + 600000 });
  rejected(await f.call('select_focus_session', { deviceId: f.phone.deviceId, suggestedMinutes: 15 }), /session_active/);
  await f.confirm(await f.open('maximum', 15)); const commands = await f.queue();
  assert.equal(commands.length, 1); assert.equal(commands[0].action, 'set_maximum');
  assert.equal((await f.request(`/v1/devices/${f.phone.deviceId}`)).snapshot.sessionID, 'running');
});
test('a session becoming active between opening and confirmation prevents a start', async t => {
  const f = await fixture(t); const draft = await f.open('session', 15);
  await f.snapshot({ sessionID: 'started-elsewhere', endAt: Date.now() + 600000 });
  rejected(await f.confirm(draft), /session_active/); assert.deepEqual(await f.queue(), []);
});
test('confirmation requires literal attestation true and a valid revision', async t => {
  const f = await fixture(t); const draft = await f.open('maximum', 60);
  for (const userConfirmed of [undefined,false,'true',1]) rejected(await f.call('confirm_focus_selection', { selectionId: draft.id, revision: 1, userConfirmed }));
  for (const revision of [0,1.5,'1']) rejected(await f.call('confirm_focus_selection', { selectionId: draft.id, revision, userConfirmed: true }));
  assert.deepEqual(await f.queue(), []);
});
test('expired drafts cannot be edited or confirmed', async t => {
  const f = await fixture(t); const draft = await f.open('maximum', 60); f.advance(600000);
  rejected(await f.call('revise_focus_selection', { selectionId: draft.id, minutes: 90 }), /selection_expired/);
  rejected(await f.confirm(draft), /selection_expired/); assert.deepEqual(await f.queue(), []);
});
test('lost submission response retries one immutable command even after draft lifetime', async t => {
  const f = await fixture(t, { loseResponse: true }); const draft = await f.open('maximum', 60);
  assert.equal((await f.confirm(draft)).structuredContent.selection.phase, 'unknown');
  const [original] = await f.queue(); assert.equal(original.maximumMinutes, 60);
  rejected(await f.call('revise_focus_selection', { selectionId: draft.id, minutes: 1440 }), /selection_already_submitted/);
  f.advance(600001); const retry = (await f.confirm(draft)).structuredContent.selection;
  assert.equal(retry.phase, 'expired'); assert.deepEqual(retry.command, original); assert.deepEqual(await f.queue(), []);
  const receipt = await f.call('command_status', { deviceId: f.phone.deviceId, requestId: original.id });
  assert.equal(JSON.parse(receipt.content[0].text).command.sequence, original.sequence);
});
test('opening a new picker cannot erase a submitted picker needed to reconcile a lost response', async t => {
  const f = await fixture(t, { loseResponse: true });
  const draft = await f.open('maximum', 60);
  assert.equal((await f.confirm(draft)).structuredContent.selection.phase, 'unknown');
  const [original] = await f.queue();
  f.advance(600001);
  await f.open('maximum', 90);
  const retried = await f.confirm(draft);
  assert.notEqual(retried.isError, true, retried.content?.[0]?.text);
  assert.equal(retried.structuredContent.selection.phase, 'expired');
  assert.deepEqual(retried.structuredContent.selection.command, original);
  assert.deepEqual(await f.queue(), []);
  const receipt = await f.call('command_status', { deviceId: f.phone.deviceId, requestId: original.id });
  const observed = JSON.parse(receipt.content[0].text);
  assert.equal(observed.command.id, original.id);
  assert.equal(observed.command.sequence, original.sequence);
});
test('full expired submission history permits a new picker while evicted receipts remain durable', async t => {
  const f = await fixture(t);
  let oldest;
  for (let index = 0; index < 100; index += 1) {
    const draft = await f.open('maximum', 60);
    if (index === 0) oldest = draft;
    assert.equal((await f.confirm(draft)).structuredContent.selection.phase, 'pending');
  }
  const originalCommands = await f.queue();
  assert.equal(originalCommands.length, 100);
  const original = originalCommands[0];
  f.advance(600001);
  const next = await f.open('maximum', 90);
  assert.equal(next.phase, 'draft');
  rejected(await f.confirm(oldest), /selection_missing/);
  const receipt = await f.call('command_status', { deviceId: f.phone.deviceId, requestId: original.id });
  const observed = JSON.parse(receipt.content[0].text);
  assert.equal(observed.status, 'expired');
  assert.deepEqual(observed.command, original);
  assert.deepEqual(await f.queue(), []);
});
test('one hundred fresh drafts reject another picker without submitting commands', async t => {
  const f = await fixture(t);
  let first;
  for (let index = 0; index < 100; index += 1) {
    const draft = await f.open('maximum', 60);
    if (index === 0) first = draft;
  }
  rejected(await f.call('select_focus_maximum', { deviceId: f.phone.deviceId, suggestedMinutes: 90 }), /too_many_open_pickers/);
  const retained = await f.call('focus_selection_status', { selectionId: first.id });
  assert.equal(retained.structuredContent.selection.phase, 'draft');
  assert.equal(retained.structuredContent.selection.minutes, 60);
  assert.deepEqual(await f.queue(), []);
});
test('maximum double confirmation and retry preserve one payload and sequence', async t => {
  const f = await fixture(t); const draft = await f.open('maximum', 60);
  for (const r of await Promise.all([f.confirm(draft), f.confirm(draft)])) assert.equal(r.structuredContent.selection.phase, 'pending');
  const [original] = await f.queue(); await f.confirm(draft); assert.deepEqual(await f.queue(), [original]);
});
test('break insistence and task completion are distinct stop permissions', async t => {
  const f = await fixture(t); const args = { deviceId: f.phone.deviceId, modeID: 'approved', sessionID: 'running', requestId: 'qa-stop' };
  rejected(await f.call('stop_focus', { ...args, reason: 'break', completionConfirmed: true }), /ask_about_break/);
  rejected(await f.call('stop_focus', { ...args, reason: 'completed', userInsisted: true }), /completion_confirmation_required/);
  assert.deepEqual(await f.queue(), []);
  const r = await f.call('stop_focus', { ...args, reason: 'break', userInsisted: true });
  assert.equal(JSON.parse(r.content[0].text).status, 'pending');
  const [c] = await f.queue(); assert.equal(c.action, 'stop'); assert.equal(c.sessionID, 'running');
});
test('picker rejection never claims a maximum was saved', async t => {
  const f = await fixture(t); const draft = await f.open('maximum', 60); await f.confirm(draft); const [c] = await f.queue();
  await f.request('/v1/device/receipts', { id: c.id, status: 'rejected', reason: 'policy_changed' }, f.phone.deviceToken);
  const r = await f.call('focus_selection_status', { selectionId: draft.id });
  assert.equal(r.structuredContent.selection.phase, 'rejected'); assert.equal(r.structuredContent.selection.reason, 'policy_changed');
  assert.equal((await f.request(`/v1/devices/${f.phone.deviceId}`)).snapshot.maximumMinutes, 45);
});
test('restarting MCP invalidates old drafts while queued command receipts remain readable', async t => {
  const f = await fixture(t); const draft = await f.open('session', 15); await f.confirm(draft);
  const [c] = await f.queue(); const restarted = await f.connect();
  rejected(await restarted.callTool({ name: 'confirm_focus_selection', arguments: { selectionId: draft.id, revision: 1, userConfirmed: true } }), /selection_missing/);
  const status = await restarted.callTool({ name: 'command_status', arguments: { deviceId: f.phone.deviceId, requestId: c.id } });
  assert.equal(JSON.parse(status.content[0].text).command.id, c.id); assert.deepEqual(await f.queue(), [c]);
});
test('shared UI resource is bundled without fixture credentials or external script sources', async t => {
  const f = await fixture(t); const r = await f.client.readResource({ uri: 'ui://docard/focus-timeline.html' });
  const html = r.contents[0].text;
  assert.ok(html.length > 1000); assert.doesNotMatch(html, /__FOCUS_APP_JS__|<script\b[^>]*\bsrc\s*=/i);
  for (const secret of [f.token, f.phone.deviceToken]) assert.equal(html.includes(secret), false);
  assert.deepEqual(r.contents[0]._meta.ui.csp, { connectDomains: [], resourceDomains: [] });
});
test('missing phone policy prevents both pickers without creating commands', async t => {
  const f = await fixture(t);
  const invite = await f.request('/v1/pairings', {});
  const unconfigured = await f.request('/v1/pairings/redeem', { code: invite.code });
  for (const kind of ['session', 'maximum']) {
    rejected(await f.call(`select_focus_${kind}`, { deviceId: unconfigured.deviceId, suggestedMinutes: 30 }), /phone_setup_required/);
  }
  assert.deepEqual((await f.request('/v1/device/commands', undefined, unconfigured.deviceToken)).commands, []);
});
test('maximum stays pending until an applied phone receipt and a fresh snapshot reports the new policy', async t => {
  const f = await fixture(t); const draft = await f.open('maximum', 60); await f.confirm(draft);
  assert.equal((await f.call('focus_selection_status', { selectionId: draft.id })).structuredContent.selection.phase, 'pending');
  const [command] = await f.queue();
  await f.snapshot({ modeID: 'maximum-updated', maximumMinutes: 60 });
  await f.request('/v1/device/receipts', { id: command.id, status: 'applied' }, f.phone.deviceToken);
  assert.equal((await f.call('focus_selection_status', { selectionId: draft.id })).structuredContent.selection.phase, 'applied');
  const next = await f.open('session', 60); assert.equal(next.currentMaximumMinutes, 60); assert.equal(next.modeID, 'maximum-updated');
  rejected(await f.call('select_focus_session', { deviceId: f.phone.deviceId, suggestedMinutes: 61 }), /duration_exceeds_approval/);
  assert.deepEqual(await f.queue(), []);
});
