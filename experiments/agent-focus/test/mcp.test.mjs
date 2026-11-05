import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createFocusMcp } from '../src/mcp.mjs';
import { createRelay } from '../src/relay.mjs';

async function fixture(t) {
  const token = 'test-agent-secret-at-least-32-characters';
  const relay = createRelay({ agentToken: token, database: ':memory:' });
  await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${relay.server.address().port}`;
  const server = createFocusMcp({ relayURL: url, agentToken: token });
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
  const invite = await request('/v1/pairings', {});
  const phone = await request('/v1/pairings/redeem', { code: invite.code });
  return { client, request, phone };
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

test('Codex can produce a one-time phone setup link without exposing its agent credential', async t => {
  const { client } = await fixture(t);
  const invite = value(await client.callTool({ name: 'pair_phone', arguments: {} }));
  assert.equal(new URL(invite.setupURL).protocol, 'docard-agent:');
  assert.equal(new URL(invite.setupURL).searchParams.get('code'), invite.code);
  assert.equal(JSON.stringify(invite).includes('test-agent-secret'), false);
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
  assert.deepEqual(tools.map(tool => tool.name).sort(), ['command_status', 'focus_status', 'pair_phone', 'start_focus', 'stop_focus']);
});
