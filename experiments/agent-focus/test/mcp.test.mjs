import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createFocusMcp } from '../src/mcp.mjs';
import { createRelay } from '../src/relay.mjs';

async function fixture(t, { defaultDeviceId, paired = true, phoneApp } = {}) {
  const token = 'test-agent-secret-at-least-32-characters';
  const relay = createRelay({ agentToken: token, database: ':memory:' });
  await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${relay.server.address().port}`;
  const server = createFocusMcp({ relayURL: url, agentToken: token, defaultDeviceId, phoneApp });
  const client = new Client({ name: 'test-codex', version: '1.0.0' });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(b);
  await client.connect(a);
  t.after(async () => { await client.close(); await server.close(); await new Promise(resolve => relay.server.close(resolve)); relay.close(); });
  async function request(path, body, credential = token) {
    const response = await fetch(url + path, { method: body === undefined ? 'GET' : 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return response.json();
  }
  let phone = null;
  if (paired) {
    const invite = await request('/v1/pairings', {});
    phone = await request('/v1/pairings/redeem', { code: invite.code });
  }
  return { client, request, phone, url, token };
}
const input = { requestId: 'command-1', modeID: 'work', durationMinutes: 30, sessionID: 'session-1' };
const value = response => JSON.parse(response.content[0].text);

test('Codex sees pending rather than success before the phone applies a start', async t => {
  const { client, phone } = await fixture(t);
  const result = value(await client.callTool({ name: 'start_focus', arguments: { ...input, deviceId: phone.deviceId } }));
  assert.equal(result.status, 'pending');
  assert.equal(result.command.sessionID, 'session-1');
});

test('completion-based unlocking requires confirmation and then queues a session-specific stop', async t => {
  const { client, phone } = await fixture(t);
  const args = { deviceId: phone.deviceId, modeID: 'work', requestId: 'stop-1', sessionID: 'session-1', reason: 'completed' };
  const blocked = await client.callTool({ name: 'stop_focus', arguments: args });
  assert.equal(blocked.isError, true);
  assert.match(blocked.content[0].text, /completion_confirmation_required/);
  const allowed = value(await client.callTool({ name: 'stop_focus', arguments: { ...args, completionConfirmed: true } }));
  assert.equal(allowed.status, 'pending');
  assert.equal(allowed.command.action, 'stop');
});

test('Codex receives the actual phone rejection rather than a success message', async t => {
  const { client, phone, request } = await fixture(t);
  await client.callTool({ name: 'start_focus', arguments: { ...input, deviceId: phone.deviceId } });
  await request('/v1/device/receipts', { id: 'command-1', status: 'rejected', reason: 'duration_exceeds_approval' }, phone.deviceToken);
  const response = value(await client.callTool({ name: 'command_status', arguments: { deviceId: phone.deviceId, requestId: 'command-1' } }));
  assert.equal(response.status, 'rejected');
  assert.equal(response.reason, 'duration_exceeds_approval');
});

test('an explicit additional-phone request creates a setup link without exposing its agent credential', async t => {
  const { client } = await fixture(t);
  const invite = value(await client.callTool({ name: 'pair_phone', arguments: { newPhone: true } }));
  assert.equal(new URL(invite.setupURL).protocol, 'docard-agent:');
  assert.equal(new URL(invite.setupURL).searchParams.get('code'), invite.code);
  assert.equal(JSON.stringify(invite).includes('test-agent-secret'), false);
});

test('standalone MCP links open Agent Blocking for pairing and app review', async t => {
  const { client, request, phone } = await fixture(t, { phoneApp: 'agent-blocking' });
  const invite = value(await client.callTool({ name: 'pair_phone', arguments: { newPhone: true } }));
  assert.equal(new URL(invite.setupURL).protocol, 'agent-blocking:');
  assert.equal(new URL(invite.setupURL).host, 'setup');

  await request('/v1/device/snapshot', { modeID: 'work', requiresRenewalApproval: false,
    maximumMinutes: 45 }, phone.deviceToken);
  const review = value(await client.callTool({ name: 'review_focus_apps',
    arguments: { deviceId: phone.deviceId } }));
  assert.equal(new URL(review.reviewURL).protocol, 'agent-blocking:');
  assert.equal(new URL(review.reviewURL).searchParams.get('deviceId'), phone.deviceId);

  const picker = value(await client.callTool({ name: 'select_focus_session',
    arguments: { deviceId: phone.deviceId } }));
  assert.equal(new URL(picker.selection.reviewURL).protocol, 'agent-blocking:');
  assert.equal(picker.selection.phoneAppName, 'Agent Blocking');
});

test('Codex sees phone-approved limits with an observation timestamp', async t => {
  const { client, phone, request } = await fixture(t);
  await request('/v1/device/snapshot', { modeID: 'work', sessionID: null, endAt: null,
    requiresRenewalApproval: false, maximumMinutes: 45 }, phone.deviceToken);
  const response = value(await client.callTool({ name: 'focus_status', arguments: { deviceId: phone.deviceId } }));
  assert.equal(response.snapshot.maximumMinutes, 45);
  assert.equal(typeof response.observedAt, 'number');
});

test('Linear focus instructions preserve completion approval and time-limit rules', async t => {
  const { client } = await fixture(t);
  const prompt = await client.getPrompt({ name: 'focus_on_linear_issue', arguments: { issue: 'DO-123' } });
  const text = prompt.messages[0].content.text;
  assert.match(text, /DO-123/);
  assert.match(text, /confirm.*finished/i);
  assert.match(text, /In Progress/);
  assert.match(text, /never.*automatically renew/i);
});

test('Codex can discover tools through the real stdio process', async t => {
  const { StdioClientTransport } = await import('@modelcontextprotocol/sdk/client/stdio.js');
  const { mkdtemp, writeFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const directory = await mkdtemp(`${tmpdir()}/docard-mcp-`);
  t.after(() => rm(directory, { recursive: true, force: true }));
  const credential = `${directory}/token`;
  await writeFile(credential, 'a-secret-token-that-is-longer-than-32-characters', { mode: 0o600 });
  const transport = new StdioClientTransport({ command: process.execPath,
    args: [new URL('../src/mcp-main.mjs', import.meta.url).pathname],
    env: { ...process.env, DO_CARD_RELAY_URL: 'https://relay.example.com', DO_CARD_AGENT_TOKEN_FILE: credential } });
  const client = new Client({ name: 'stdio-codex', version: '1.0.0' });
  t.after(() => client.close());
  await client.connect(transport);
  const { tools } = await client.listTools();
  assert.deepEqual(tools.map(tool => tool.name).sort(), ['command_status', 'confirm_focus_selection', 'focus_selection_status', 'focus_status', 'pair_phone', 'refresh_focus_app_groups', 'review_focus_apps', 'revise_focus_selection', 'select_focus_maximum', 'select_focus_session', 'start_focus', 'stop_focus']);
});


test('two-minute expiry test reaches the phone queue through MCP and the relay', async t => {
  const { client, phone, request } = await fixture(t);
  const response = await client.callTool({ name: 'start_focus', arguments: {
    ...input, deviceId: phone.deviceId, durationMinutes: 2,
  } });
  assert.notEqual(response.isError, true);
  assert.equal(value(response).status, 'pending');
  const queued = await request('/v1/device/commands', undefined, phone.deviceToken);
  assert.equal(queued.commands[0].durationMinutes, 2);
});

test('maximum picker returns the shared UI without queuing a session, then confirms only a maximum change', async t => {
  const { client, phone, request } = await fixture(t);
  await request('/v1/device/snapshot', { modeID: 'work', sessionID: null, endAt: null,
    requiresRenewalApproval: false, maximumMinutes: 45, startMinute: 0, endMinute: 1440,
    timeZone: 'Asia/Taipei' }, phone.deviceToken);
  const tools = (await client.listTools()).tools;
  const maximumTool = tools.find(tool => tool.name === 'select_focus_maximum');
  const sessionTool = tools.find(tool => tool.name === 'select_focus_session');
  assert.ok(maximumTool, 'The agent can open a separate maximum picker');
  assert.equal(maximumTool._meta.ui.resourceUri, sessionTool._meta.ui.resourceUri);
  assert.notEqual(sessionTool._meta.ui.resourceUri, 'ui://docard/focus-timeline.html', 'A rebuilt language bundle needs a versioned cache key');
  const opened = await client.callTool({ name: 'select_focus_maximum', arguments: {
    deviceId: phone.deviceId, suggestedMinutes: 60,
  } });
  const draft = opened.structuredContent.selection;
  assert.equal(draft.kind, 'maximum');
  assert.equal(draft.currentMaximumMinutes, 45);
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).commands.length, 0);
  const edited = (await client.callTool({ name: 'revise_focus_selection', arguments: {
    selectionId: draft.id, minutes: 90,
  } })).structuredContent.selection;
  const confirmed = await client.callTool({ name: 'confirm_focus_selection', arguments: {
    selectionId: edited.id, revision: edited.revision, userConfirmed: true,
  } });
  assert.equal(confirmed.structuredContent.selection.phase, 'pending');
  const queued = (await request('/v1/device/commands', undefined, phone.deviceToken)).commands;
  assert.equal(queued[0].action, 'set_maximum');
  assert.equal(queued[0].maximumMinutes, 90);
  assert.equal('sessionID' in queued[0], false);
  assert.equal('durationMinutes' in queued[0], false);
  assert.equal((await request(`/v1/devices/${phone.deviceId}`)).snapshot.maximumMinutes, 45);
  const resource = await client.readResource({ uri: maximumTool._meta.ui.resourceUri });
  assert.equal(resource.contents[0].mimeType, 'text/html;profile=mcp-app');
  assert.match(resource.contents[0].text, /Maximum lock time/);
});

test('session picker changes only session duration and retries one stable command after user confirmation', async t => {
  const { client, phone, request } = await fixture(t);
  await request('/v1/device/snapshot', { modeID: 'work', maximumMinutes: 45,
    requiresRenewalApproval: true, startMinute: 0, endMinute: 1440, timeZone: 'Asia/Taipei' }, phone.deviceToken);
  const draft = (await client.callTool({ name: 'select_focus_session', arguments: {
    deviceId: phone.deviceId, suggestedMinutes: 30, issue: 'YAN-103',
  } })).structuredContent.selection;
  const oversized = await client.callTool({ name: 'revise_focus_selection', arguments: { selectionId: draft.id, minutes: 60 } });
  assert.equal(oversized.isError, true);
  const revised = (await client.callTool({ name: 'revise_focus_selection', arguments: {
    selectionId: draft.id, minutes: 20,
  } })).structuredContent.selection;
  const stale = await client.callTool({ name: 'confirm_focus_selection', arguments: { selectionId: draft.id, revision: draft.revision, userConfirmed: true } });
  assert.equal(stale.isError, true);
  const noApproval = await client.callTool({ name: 'confirm_focus_selection', arguments: { selectionId: revised.id, revision: revised.revision, userConfirmed: false } });
  assert.equal(noApproval.isError, true);
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).commands.length, 0);
  const args = { selectionId: revised.id, revision: revised.revision, userConfirmed: true };
  await Promise.all([client.callTool({ name: 'confirm_focus_selection', arguments: args }), client.callTool({ name: 'confirm_focus_selection', arguments: args })]);
  const queued = (await request('/v1/device/commands', undefined, phone.deviceToken)).commands;
  assert.equal(queued.length, 1);
  assert.equal(queued[0].action, 'start');
  assert.equal(queued[0].durationMinutes, 20);
  assert.equal(queued[0].renewalConfirmed, true);
  assert.equal('maximumMinutes' in queued[0], false);
  assert.equal((await request(`/v1/devices/${phone.deviceId}`)).snapshot.maximumMinutes, 45);
  const changedAfterSubmit = await client.callTool({ name: 'revise_focus_selection', arguments: { selectionId: revised.id, minutes: 25 } });
  assert.equal(changedAfterSubmit.isError, true);
  await request('/v1/device/receipts', { id: queued[0].id, status: 'applied' }, phone.deviceToken);
  const receipt = (await client.callTool({ name: 'focus_selection_status', arguments: { selectionId: revised.id } })).structuredContent.selection;
  assert.equal(receipt.phase, 'applied');
});

test('a picker cannot overwrite a newer phone policy or a newer draft revision', async t => {
  const { client, phone, request } = await fixture(t);
  await request('/v1/device/snapshot', { modeID: 'work', maximumMinutes: 45, requiresRenewalApproval: false }, phone.deviceToken);
  const opened = (await client.callTool({ name: 'select_focus_maximum', arguments: { deviceId: phone.deviceId, suggestedMinutes: 60 } })).structuredContent.selection;
  await client.callTool({ name: 'revise_focus_selection', arguments: { selectionId: opened.id, minutes: 90 } });
  const staleEdit = await client.callTool({ name: 'revise_focus_selection', arguments: { selectionId: opened.id, minutes: 30, expectedRevision: opened.revision } });
  assert.equal(staleEdit.isError, true);
  await request('/v1/device/snapshot', { modeID: 'changed-on-phone', maximumMinutes: 120, requiresRenewalApproval: false }, phone.deviceToken);
  const rejected = await client.callTool({ name: 'confirm_focus_selection', arguments: { selectionId: opened.id, revision: 2, userConfirmed: true } });
  assert.equal(rejected.isError, true);
  assert.match(rejected.content[0].text, /policy_changed/);
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).commands.length, 0);
});


test('confirmation cannot cross a concurrent chat revision or proposal expiry during the phone check', async t => {
  const { phone, request, url, token } = await fixture(t);
  await request('/v1/device/snapshot', { modeID: 'work', maximumMinutes: 45, requiresRenewalApproval: false }, phone.deviceToken);
  const { createServer } = await import('node:http');
  let armed = false, entered, resume;
  const proxy = createServer(async (req, res) => {
    if (armed && req.method === 'GET' && req.url === `/v1/devices/${phone.deviceId}`) {
      armed = false; entered(); await new Promise(resolve => { resume = resolve; });
    }
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const upstream = await fetch(url + req.url, { method: req.method,
      headers: { authorization: req.headers.authorization, 'content-type': 'application/json' },
      ...(chunks.length ? { body: Buffer.concat(chunks) } : {}) });
    res.writeHead(upstream.status, { 'content-type': 'application/json' }); res.end(await upstream.text());
  });
  await new Promise(resolve => proxy.listen(0, '127.0.0.1', resolve));
  let clock = Date.now();
  const server = createFocusMcp({ relayURL: `http://127.0.0.1:${proxy.address().port}`, agentToken: token, now: () => clock });
  const client = new Client({ name: 'concurrent-codex', version: '1.0.0' });
  const [a,b] = InMemoryTransport.createLinkedPair(); await server.connect(b); await client.connect(a);
  t.after(async () => { await client.close(); await server.close(); await new Promise(resolve => proxy.close(resolve)); });
  async function blockedConfirmation(draft, change) {
    const waiting = new Promise(resolve => { entered = resolve; }); armed = true;
    const confirmation = client.callTool({ name: 'confirm_focus_selection', arguments: {
      selectionId: draft.id, revision: draft.revision, userConfirmed: true,
    } });
    await waiting;
    await change(); resume();
    const result = await confirmation;
    assert.equal(result.isError, true);
    return result;
  }
  const opened = (await client.callTool({ name: 'select_focus_maximum', arguments: { deviceId: phone.deviceId, suggestedMinutes: 60 } })).structuredContent.selection;
  const revised = await blockedConfirmation(opened, () => client.callTool({ name: 'revise_focus_selection', arguments: { selectionId: opened.id, minutes: 1440 } }));
  assert.match(revised.content[0].text, /selection_changed/);
  const expiring = (await client.callTool({ name: 'select_focus_maximum', arguments: { deviceId: phone.deviceId, suggestedMinutes: 60 } })).structuredContent.selection;
  const expired = await blockedConfirmation(expiring, async () => { clock += 600001; });
  assert.match(expired.content[0].text, /selection_expired/);
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).commands.length, 0);
});


test('a fresh chat can open a suggested picker without knowing its paired phone ID', async t => {
  const { client, request, phone } = await fixture(t);
  await request('/v1/device/snapshot', { modeID: 'approved', maximumMinutes: 45,
    requiresRenewalApproval: false, selectionSummary: { applications: 2, categories: 0, websites: 0 } }, phone.deviceToken);
  const response = await client.callTool({ name: 'select_focus_session', arguments: {} });
  assert.notEqual(response.isError, true, response.content?.[0]?.text);
  assert.equal(response.structuredContent.selection.deviceId, phone.deviceId);
  assert.equal(response.structuredContent.selection.minutes, 30);
  assert.equal(response.structuredContent.selection.phase, 'draft');
  const status = value(await client.callTool({ name: 'focus_status', arguments: {} }));
  assert.equal(status.deviceId, phone.deviceId);
  const reused = value(await client.callTool({ name: 'pair_phone', arguments: {} }));
  assert.equal(reused.status, 'already_paired');
  assert.equal(reused.setupURL, undefined);
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).commands, []);
});


async function anotherChat(t, f, defaultDeviceId) {
  const server = createFocusMcp({ relayURL: f.url, agentToken: f.token, defaultDeviceId });
  const client = new Client({ name: 'unrelated-workspace', version: '1.0.0' });
  const [a,b] = InMemoryTransport.createLinkedPair();
  await server.connect(b); await client.connect(a);
  t.after(async () => { await client.close(); await server.close(); });
  return client;
}

test('an unrelated workspace reuses the configured phone when several pairings exist', async t => {
  const f = await fixture(t);
  const invitation = await f.request('/v1/pairings', {});
  const second = await f.request('/v1/pairings/redeem', { code: invitation.code });
  await f.request('/v1/device/snapshot', { modeID: 'approved', maximumMinutes: 20,
    requiresRenewalApproval: false }, f.phone.deviceToken);
  await f.request('/v1/device/snapshot', { modeID: 'other-phone', maximumMinutes: 60,
    requiresRenewalApproval: false }, second.deviceToken);
  const fresh = await anotherChat(t, f, f.phone.deviceId);
  const opened = await fresh.callTool({ name: 'select_focus_session', arguments: {} });
  assert.equal(opened.structuredContent.selection.deviceId, f.phone.deviceId);
  assert.equal(opened.structuredContent.selection.minutes, 20);
  const reused = value(await fresh.callTool({ name: 'pair_phone', arguments: {} }));
  assert.equal(reused.defaultDeviceId, f.phone.deviceId);
  assert.equal(reused.setupURL, undefined);
  assert.equal((await f.request('/v1/devices')).devices.length, 2);
  for (const phone of [f.phone, second]) assert.deepEqual((await f.request('/v1/device/commands', undefined, phone.deviceToken)).commands, []);
});

test('multiple phones without a configured choice never silently target a phone or repair', async t => {
  const f = await fixture(t);
  const invitation = await f.request('/v1/pairings', {});
  await f.request('/v1/pairings/redeem', { code: invitation.code });
  const response = await f.client.callTool({ name: 'select_focus_session', arguments: {} });
  assert.equal(response.isError, true);
  assert.match(response.content[0].text, /phone_selection_required/);
  const reused = value(await f.client.callTool({ name: 'pair_phone', arguments: {} }));
  assert.equal(reused.status, 'already_paired'); assert.equal(reused.setupURL, undefined);
});

test('a missing configured phone never falls back to controlling another paired phone', async t => {
  const f = await fixture(t);
  const fresh = await anotherChat(t, f, '11111111-1111-4111-8111-111111111111');
  const response = await fresh.callTool({ name: 'select_focus_session', arguments: {} });
  assert.equal(response.isError, true);
  assert.deepEqual((await f.request('/v1/device/commands', undefined, f.phone.deviceToken)).commands, []);
});


test('an actually unpaired relay still offers first-phone setup only when pairing is requested', async t => {
  const f = await fixture(t, { paired: false });
  const opened = await f.client.callTool({ name: 'select_focus_session', arguments: {} });
  assert.equal(opened.isError, true);
  assert.match(opened.content[0].text, /phone_not_paired/);
  assert.deepEqual((await f.request('/v1/devices')).devices, []);
  const invitation = value(await f.client.callTool({ name: 'pair_phone', arguments: {} }));
  assert.equal(new URL(invitation.setupURL).protocol, 'docard-agent:');
  const paired = await f.request('/v1/pairings/redeem', { code: invitation.code });
  assert.equal(paired.deviceId, invitation.deviceId);
});
