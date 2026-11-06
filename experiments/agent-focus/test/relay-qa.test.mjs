import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRelay } from '../src/relay.mjs';

const agentToken = 'isolated-qa-agent-token-at-least-32-characters';
const start = { id: 'start-1', action: 'start', modeID: 'approved-mode', sessionID: 'session-1', durationMinutes: 30 };
const snapshot = { modeID: 'approved-mode', requiresRenewalApproval: false,
  maximumMinutes: 45, startMinute: 480, endMinute: 1080, timeZone: 'Asia/Taipei' };

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'docard-relay-qa-'));
  let relay;
  let base;
  async function open() {
    relay = createRelay({ agentToken, database: join(directory, 'relay.sqlite'), ...options });
    await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${relay.server.address().port}`;
  }
  async function close() {
    if (!relay) return;
    await new Promise(resolve => relay.server.close(resolve));
    relay.close();
    relay = undefined;
  }
  await open();
  t.after(async () => { await close(); await rm(directory, { recursive: true, force: true }); });
  async function request(path, body, token = agentToken) {
    const response = await fetch(base + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json() };
  }
  async function pair() {
    const invitation = await request('/v1/pairings', {});
    assert.equal(invitation.status, 201);
    const redeemed = await request('/v1/pairings/redeem', { code: invitation.body.code }, null);
    assert.equal(redeemed.status, 200);
    return redeemed.body;
  }
  return { request, pair, restart: async () => { await close(); await open(); },
    raw: (path, init) => fetch(base + path, init) };
}

test('malformed snapshots cannot replace the last phone-observed approval', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  assert.equal((await request('/v1/device/snapshot', snapshot, phone.deviceToken)).status, 200);
  for (const invalid of [
    { maximumMinutes: '45' }, { maximumMinutes: 45.5 }, { startMinute: 1.5 },
    { endMinute: '1080' }, { requiresRenewalApproval: 'false' }, { applicationTokens: ['private'] },
  ]) {
    const result = await request('/v1/device/snapshot', { ...snapshot, ...invalid }, phone.deviceToken);
    assert.equal(result.status, 400, `Reject invalid policy ${JSON.stringify(invalid)}`);
  }
  const observed = await request(`/v1/devices/${phone.deviceId}`);
  assert.equal(observed.body.snapshot.maximumMinutes, 45);
  assert.equal(observed.body.snapshot.startMinute, 480);
});

test('a start without a finite duration is rejected before delivery', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  const { durationMinutes, ...incomplete } = start;
  const response = await request(`/v1/devices/${phone.deviceId}/commands`, incomplete);
  assert.equal(response.status, 400);
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
});

test('pairing codes remain redeemable just before their ten-minute deadline', async t => {
  let clock = 1793836800000;
  const { request } = await fixture(t, { now: () => clock });
  const invitation = (await request('/v1/pairings', {})).body;
  clock += 599999;
  const redeemed = await request('/v1/pairings/redeem', { code: invitation.code }, null);
  assert.equal(redeemed.status, 200);
  assert.equal(redeemed.body.deviceId, invitation.deviceId);
  assert.equal((await request('/v1/pairings/redeem', { code: invitation.code }, null)).status, 410);
});

test('pairing codes expire exactly at the ten-minute deadline', async t => {
  let clock = 1793836800000;
  const { request } = await fixture(t, { now: () => clock });
  const invitation = (await request('/v1/pairings', {})).body;
  clock += 600000;
  assert.equal((await request('/v1/pairings/redeem', { code: invitation.code }, null)).status, 410);
  assert.equal((await request(`/v1/devices/${invitation.deviceId}`)).status, 404);
});

test('wrong credentials and credential roles cannot cross the agent-device boundary', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  const devicePath = `/v1/devices/${phone.deviceId}`;
  for (const token of [null, 'incorrect-agent-secret', phone.deviceToken]) {
    assert.equal((await request(devicePath, undefined, token)).status, 401);
    assert.equal((await request(`${devicePath}/commands`, start, token)).status, 401);
  }
  const badDevice = `${phone.deviceId}.${'0'.repeat(64)}`;
  for (const token of [null, agentToken, badDevice]) {
    assert.equal((await request('/v1/device/commands', undefined, token)).status, 401);
    assert.equal((await request('/v1/device/snapshot', snapshot, token)).status, 401);
    assert.equal((await request('/v1/device/receipts', { id: start.id, status: 'applied' }, token)).status, 401);
  }
});

test('identical request IDs on different devices retain independent commands and receipts', async t => {
  const { request, pair } = await fixture(t);
  const first = await pair(), second = await pair();
  await request(`/v1/devices/${first.deviceId}/commands`, start);
  await request(`/v1/devices/${second.deviceId}/commands`, { ...start, sessionID: 'other-session' });
  assert.equal((await request('/v1/device/receipts', { id: start.id, status: 'rejected', reason: 'mode_not_approved' }, second.deviceToken)).status, 200);
  const firstView = await request(`/v1/device/commands/${start.id}`, undefined, first.deviceToken);
  const secondView = await request(`/v1/device/commands/${start.id}`, undefined, second.deviceToken);
  assert.equal(firstView.body.status, 'pending');
  assert.equal(firstView.body.command.sessionID, 'session-1');
  assert.equal(secondView.body.status, 'rejected');
  assert.equal(secondView.body.command.sessionID, 'other-session');
  assert.equal((await request(`/v1/devices/${first.deviceId}/commands/${start.id}`, undefined, second.deviceToken)).status, 401);
});

test('malformed and mixed command fields are rejected without consuming a sequence', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  for (const invalid of [
    { ...start, action: 'erase' }, { ...start, durationMinutes: 0 },
    { ...start, durationMinutes: 1441 }, { ...start, durationMinutes: 2.5 },
    { ...start, durationMinutes: '30' }, { ...start, modeID: '' },
    { ...start, sessionID: null }, { ...start, applicationTokens: ['private'] },
    { ...start, maximumMinutes: 60 },
    { id: 'maximum', action: 'set_maximum', modeID: 'approved-mode', maximumMinutes: 60,
      expectedMaximumMinutes: 45, userConfirmed: true, sessionID: 'session-1' },
  ]) {
    assert.equal((await request(path, invalid)).status, 400, `Reject ${JSON.stringify(invalid)}`);
  }
  const valid = await request(path, start);
  assert.equal(valid.status, 202);
  assert.equal(valid.body.command.sequence, 1);
});

test('commands remain pending until the final millisecond before the delivery deadline', async t => {
  let clock = 1793836800000;
  const { request, pair } = await fixture(t, { now: () => clock });
  const phone = await pair();
  const queued = await request(`/v1/devices/${phone.deviceId}/commands`, start);
  assert.equal(queued.body.command.expiresAt, 1793836920000);
  clock = 1793836919999;
  const commands = (await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands;
  assert.equal(commands.length, 1);
  assert.equal(commands[0].id, start.id);
});

test('commands expire exactly at the two-minute delivery deadline', async t => {
  let clock = 1793836800000;
  const { request, pair } = await fixture(t, { now: () => clock });
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  await request(path, start);
  clock = 1793836920000;
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
  const expired = await request(`${path}/${start.id}`);
  assert.equal(expired.body.status, 'expired');
  assert.equal(expired.body.reason, 'delivery_expired');
});

test('retrying an expired request never rejuvenates its delivery deadline or sends another push', async t => {
  let clock = 1793836800000;
  const pushes = [];
  const { request, pair } = await fixture(t, { now: () => clock,
    push: async message => { pushes.push(message); return { status: 'accepted_by_apns' }; } });
  const phone = await pair();
  await request('/v1/device/push', { token: 'a'.repeat(64) }, phone.deviceToken);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const original = await request(path, start);
  clock += 120000;
  const retried = await request(path, start);
  assert.equal(retried.status, 200);
  assert.equal(retried.body.status, 'expired');
  assert.deepEqual(retried.body.command, original.body.command);
  assert.equal(pushes.length, 1);
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
});

test('reusing a request ID for a different action preserves the original pending command', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const original = await request(path, start);
  const conflict = await request(path, { id: start.id, action: 'stop', modeID: start.modeID, sessionID: start.sessionID });
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error, 'command_id_conflict');
  assert.deepEqual((await request(`${path}/${start.id}`)).body.command, original.body.command);
  const next = await request(path, { ...start, id: 'next-start' });
  assert.equal(next.body.command.sequence, 2);
});

test('repeated terminal acknowledgements are idempotent and terminal request retries do not push', async t => {
  const pushes = [];
  const { request, pair } = await fixture(t, {
    push: async message => { pushes.push(message); return { status: 'accepted_by_apns' }; } });
  const phone = await pair();
  await request('/v1/device/push', { token: 'b'.repeat(64) }, phone.deviceToken);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  await request(path, start);
  assert.equal((await request('/v1/device/receipts', { id: start.id, status: 'applied' }, phone.deviceToken)).status, 200);
  assert.equal((await request('/v1/device/receipts', { id: start.id, status: 'applied', reason: null }, phone.deviceToken)).status, 200);
  const retried = await request(path, start);
  assert.equal(retried.status, 200);
  assert.equal(retried.body.status, 'applied');
  assert.equal(pushes.length, 1);
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
});

test('a conflicting rejection reason cannot overwrite the phone terminal receipt', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  await request(`/v1/devices/${phone.deviceId}/commands`, start);
  const receipt = { id: start.id, status: 'rejected', reason: 'outside_approved_hours' };
  assert.equal((await request('/v1/device/receipts', receipt, phone.deviceToken)).status, 200);
  assert.equal((await request('/v1/device/receipts', { ...receipt, reason: 'execution_failed' }, phone.deviceToken)).status, 409);
  const observed = await request(`/v1/device/commands/${start.id}`, undefined, phone.deviceToken);
  assert.equal(observed.body.status, 'rejected');
  assert.equal(observed.body.reason, 'outside_approved_hours');
});

test('failed push delivery remains pending until a real phone receipt arrives', async t => {
  const { request, pair } = await fixture(t, { push: async () => { throw new Error('simulated APNs outage'); } });
  const phone = await pair();
  await request('/v1/device/push', { token: 'c'.repeat(64) }, phone.deviceToken);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const queued = await request(path, start);
  assert.equal(queued.status, 202);
  assert.equal(queued.body.status, 'pending');
  assert.equal(queued.body.delivery.status, 'push_failed');
  assert.equal((await request(`${path}/${start.id}`)).body.status, 'pending');
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands[0].id, start.id);
  assert.equal((await request('/v1/device/receipts', { id: start.id, status: 'applied' }, phone.deviceToken)).status, 200);
  assert.equal((await request(`${path}/${start.id}`)).body.status, 'applied');
});

test('concurrent identical submissions allocate one command and one sequence', async t => {
  const { request, pair } = await fixture(t);
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const responses = await Promise.all(Array.from({ length: 12 }, () => request(path, start)));
  for (const response of responses) {
    assert.equal(response.status, 202);
    assert.deepEqual(response.body.command, responses[0].body.command);
  }
  const commands = (await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands;
  assert.equal(commands.length, 1);
  assert.equal(commands[0].sequence, 1);
  const next = await request(path, { ...start, id: 'second-start' });
  assert.equal(next.body.command.sequence, 2);
});

test('relay restart preserves a pending command and permits its original device to acknowledge it', async t => {
  const { request, pair, restart } = await fixture(t, { now: () => 1793836800000 });
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const queued = await request(path, start);
  await restart();
  const commands = await request('/v1/device/commands', undefined, phone.deviceToken);
  assert.equal(commands.status, 200);
  assert.deepEqual(commands.body.commands, [queued.body.command]);
  assert.equal((await request('/v1/device/receipts', { id: start.id, status: 'applied' }, phone.deviceToken)).status, 200);
  assert.equal((await request(`${path}/${start.id}`)).body.status, 'applied');
});

test('relay restart retains terminal receipts, observed status and the next command sequence', async t => {
  const { request, pair, restart } = await fixture(t, { now: () => 1793836800000 });
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  await request(path, start);
  await request(path, { ...start, id: 'rejected-start', sessionID: 'session-2' });
  await request('/v1/device/receipts', { id: start.id, status: 'applied' }, phone.deviceToken);
  await request('/v1/device/receipts', { id: 'rejected-start', status: 'rejected', reason: 'mode_not_approved' }, phone.deviceToken);
  await request('/v1/device/snapshot', snapshot, phone.deviceToken);
  await restart();
  assert.equal((await request(`${path}/${start.id}`)).body.status, 'applied');
  const rejected = await request('/v1/device/commands/rejected-start', undefined, phone.deviceToken);
  assert.equal(rejected.body.status, 'rejected');
  assert.equal(rejected.body.reason, 'mode_not_approved');
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
  const observed = await request(`/v1/devices/${phone.deviceId}`);
  assert.deepEqual(observed.body.snapshot, { ...snapshot, sessionID: null, endAt: null });
  assert.equal(observed.body.observedAt, 1793836800000);
  assert.equal((await request(path, { ...start, id: 'third-start' })).body.command.sequence, 3);
});

test('malformed JSON and oversized command bodies do not enqueue work or break subsequent requests', async t => {
  const { request, pair, raw } = await fixture(t);
  const phone = await pair();
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const headers = { authorization: `Bearer ${agentToken}`, 'content-type': 'application/json' };
  const malformed = await raw(path, { method: 'POST', headers, body: '{' });
  assert.equal(malformed.status, 400);
  assert.deepEqual(await malformed.json(), { error: 'invalid_json' });
  const oversized = await raw(path, { method: 'POST', headers, body: JSON.stringify({ ...start, id: 'x'.repeat(9000) }) });
  assert.equal(oversized.status, 413);
  assert.deepEqual(await oversized.json(), { error: 'body_too_large' });
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
  const valid = await request(path, start);
  assert.equal(valid.status, 202);
  assert.equal(valid.body.command.sequence, 1);
});

test('group metadata accepts aliases but rejects selection tokens, duplicate IDs and mixed commands', async t => {
  const { request, pair } = await fixture(t); const phone = await pair();
  const good = { ...snapshot, appGroups: [{ id: 'default', name: 'Saved apps' }] };
  assert.equal((await request('/v1/device/snapshot', good, phone.deviceToken)).status, 200);
  for (const appGroups of [
    [{ id: 'default', name: 'Saved apps', applicationTokens: ['PRIVATE'] }],
    [{ id: 'same', name: 'One' }, { id: 'same', name: 'Two' }],
    [{ id: 'bad/id', name: 'One' }], [{ id: 'default', name: 'a\nb' }],
  ]) assert.equal((await request('/v1/device/snapshot', { ...snapshot, appGroups }, phone.deviceToken)).status, 400);
  const observed = await request(`/v1/devices/${phone.deviceId}`);
  assert.deepEqual(observed.body.snapshot.appGroups, good.appGroups);
  for (const action of ['stop', 'set_maximum']) {
    const command = action === 'stop' ? { id: 'stop', action, modeID: 'approved-mode', sessionID: 'session-1', appGroupID: 'default' }
      : { id: 'max', action, modeID: 'approved-mode', maximumMinutes: 60, expectedMaximumMinutes: 45, userConfirmed: true, appGroupID: 'default' };
    assert.equal((await request(`/v1/devices/${phone.deviceId}/commands`, command)).status, 400);
  }
});
