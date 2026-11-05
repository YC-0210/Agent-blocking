import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { createRelay } from '../src/relay.mjs';

const initialTime = 1793836800000;
const agentToken = 'expiry-test-agent-token-at-least-32-characters';
const start = { id: 'original-start', action: 'start', modeID: 'approved', sessionID: 'focus-session', durationMinutes: 2 };
async function until(predicate) {
  const deadline = Date.now() + 1500;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, 'Expiry worker did not reach the expected push outcome');
    await delay(5);
  }
}
async function fixture(t, { push: transport, interval = 5 } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'docard-expiry-test-'));
  let clock = initialTime, relay, base;
  const pushes = [];
  async function open() {
    relay = createRelay({ agentToken, database: join(directory, 'relay.sqlite'), now: () => clock,
      expiryIntervalMs: interval, push: async message => {
        pushes.push(message);
        return transport ? transport(message) : { status: 'accepted_by_apns' };
      } });
    await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${relay.server.address().port}`;
  }
  async function close() {
    if (!relay) return;
    await new Promise(resolve => relay.server.close(resolve));
    relay.close(); relay = undefined;
  }
  await open();
  t.after(async () => { await close(); await rm(directory, { recursive: true, force: true }); });
  async function request(path, body, token = agentToken) {
    const response = await fetch(base + path, { method: body === undefined ? 'GET' : 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    assert.ok(response.ok, `${path}: ${response.status}`);
    return response.json();
  }
  const invitation = await request('/v1/pairings', {});
  const phone = await request('/v1/pairings/redeem', { code: invitation.code });
  await request('/v1/device/push', { token: 'a'.repeat(64) }, phone.deviceToken);
  const submit = command => request(`/v1/devices/${phone.deviceId}/commands`, command);
  const receipt = (id, status = 'applied') => request('/v1/device/receipts', { id, status }, phone.deviceToken);
  return { pushes, phone, request, submit, receipt, expiry: () => pushes.filter(p => p.purpose === 'expiry'),
    at: time => { clock = time; }, restart: async () => { await close(); await open(); }, close };
}

test('only an applied start schedules an expiry alert exactly at its original deadline', async t => {
  const f = await fixture(t);
  await f.submit(start);
  await f.submit({ ...start, id: 'pending-start', sessionID: 'pending-session' });
  await f.submit({ ...start, id: 'rejected-start', sessionID: 'rejected-session' });
  await f.receipt('rejected-start', 'rejected');
  f.at(initialTime + 30000);
  await f.receipt(start.id);
  f.at(initialTime + 119999);
  await delay(30);
  assert.equal(f.expiry().length, 0);
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  assert.deepEqual(f.expiry()[0], { token: 'a'.repeat(64), commandId: start.id,
    expiresAt: initialTime + 120000 + 86400000, kind: 'alert', purpose: 'expiry' });
  await delay(30);
  assert.equal(f.expiry().length, 1);
});

test('a maximum change cannot move the original start expiry reminder', async t => {
  const f = await fixture(t);
  await f.submit(start);
  await f.receipt(start.id);
  f.at(initialTime + 60000);
  await f.submit({ id: 'new-maximum', action: 'set_maximum', modeID: 'approved',
    maximumMinutes: 120, expectedMaximumMinutes: 45, userConfirmed: true });
  await f.receipt('new-maximum');
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  assert.equal(f.expiry()[0].commandId, start.id);
  assert.equal(f.expiry()[0].expiresAt, initialTime + 120000 + 86400000);
  f.at(initialTime + 120 * 60000);
  await delay(30);
  assert.equal(f.expiry().length, 1);
});

test('only an applied stop for the matching session cancels its reminder', async t => {
  const f = await fixture(t);
  await f.submit(start);
  await f.receipt(start.id);
  await f.submit({ id: 'wrong-stop', action: 'stop', modeID: 'approved', sessionID: 'another-session' });
  await f.receipt('wrong-stop');
  await f.submit({ id: 'rejected-stop', action: 'stop', modeID: 'approved', sessionID: start.sessionID });
  await f.receipt('rejected-stop', 'rejected');
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  const nextStart = { ...start, id: 'second-start', sessionID: 'second-session' };
  await f.submit(nextStart);
  await f.receipt(nextStart.id);
  await f.submit({ id: 'matching-stop', action: 'stop', modeID: 'approved', sessionID: nextStart.sessionID });
  await f.receipt('matching-stop');
  await f.receipt(nextStart.id); // A duplicate old start receipt cannot resurrect a canceled job.
  f.at(initialTime + 240000);
  await delay(40);
  assert.deepEqual(f.expiry().map(message => message.commandId), [start.id]);
});

test('a later applied stop acknowledged first prevents a late start receipt from recreating its reminder', async t => {
  const f = await fixture(t);
  await f.submit(start);
  await f.submit({ id: 'later-stop', action: 'stop', modeID: 'approved', sessionID: start.sessionID });
  await f.receipt('later-stop');
  await f.receipt(start.id);
  f.at(initialTime + 120000);
  await delay(40);
  assert.equal(f.expiry().length, 0);
  // A stop from an earlier command sequence cannot cancel a subsequent start.
  await f.submit({ ...start, id: 'newer-start' });
  await f.receipt('newer-start');
  f.at(initialTime + 240000);
  await until(() => f.expiry().length === 1);
  assert.equal(f.expiry()[0].commandId, 'newer-start');
});

test('a delayed old stop receipt cannot cancel a newer start that reuses its session ID', async t => {
  const f = await fixture(t);
  await f.submit(start);
  await f.receipt(start.id);
  await f.submit({ id: 'old-stop', action: 'stop', modeID: 'approved', sessionID: start.sessionID });
  await f.submit({ ...start, id: 'newer-reused-session' });
  await f.receipt('newer-reused-session');
  await f.receipt('old-stop');
  await f.receipt('old-stop');
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  assert.equal(f.expiry()[0].commandId, 'newer-reused-session');
  await delay(30);
  assert.equal(f.expiry().length, 1, 'Only the earlier start should have been canceled');
});

test('failed and unconfigured expiry pushes retry every thirty seconds until accepted', async t => {
  let attempts = 0;
  const f = await fixture(t, { push: async message => {
    if (message.purpose !== 'expiry') return { status: 'accepted_by_apns' };
    attempts += 1;
    if (attempts === 1) throw new Error('simulated APNs outage');
    return { status: attempts === 2 ? 'unconfigured' : 'accepted_by_apns' };
  } });
  await f.submit(start);
  await f.receipt(start.id);
  f.at(initialTime + 120000);
  await until(() => attempts === 1);
  f.at(initialTime + 149999);
  await delay(30);
  assert.equal(attempts, 1);
  f.at(initialTime + 150000);
  await until(() => attempts === 2);
  f.at(initialTime + 180000);
  await until(() => attempts === 3);
  await delay(20);
  f.at(initialTime + 210000);
  await delay(30);
  assert.equal(attempts, 3);
});

test('SQLite restart preserves retry leases and successful delivery across duplicate receipts', async t => {
  let attempts = 0;
  const f = await fixture(t, { push: async message => {
    if (message.purpose !== 'expiry') return { status: 'accepted_by_apns' };
    return { status: ++attempts === 1 ? 'push_failed' : 'accepted_by_apns' };
  } });
  await f.submit(start);
  await f.receipt(start.id);
  await f.receipt(start.id);
  f.at(initialTime + 120000);
  await until(() => attempts === 1);
  await f.restart();
  f.at(initialTime + 149999);
  await delay(30);
  assert.equal(attempts, 1);
  f.at(initialTime + 150000);
  await until(() => attempts === 2);
  await delay(20);
  await f.restart();
  await f.receipt(start.id);
  f.at(initialTime + 180000);
  await delay(30);
  assert.equal(attempts, 2);
});

test('APNs expiry acceptance cannot mutate the original receipt, command TTL or phone snapshot', async t => {
  const f = await fixture(t);
  const queued = await f.submit(start);
  await f.receipt(start.id);
  const snapshot = { modeID: 'approved', sessionID: start.sessionID,
    endAt: initialTime + 120000, requiresRenewalApproval: false };
  await f.request('/v1/device/snapshot', snapshot, f.phone.deviceToken);
  const before = await f.request(`/v1/devices/${f.phone.deviceId}`);
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  const original = await f.request(`/v1/devices/${f.phone.deviceId}/commands/${start.id}`);
  assert.equal(original.status, 'applied');
  assert.deepEqual(original.command, queued.command);
  assert.deepEqual(await f.request(`/v1/devices/${f.phone.deviceId}`), before);
});

test('expiry reminders stop at the twenty-four-hour horizon even after failed sends', async t => {
  const f = await fixture(t, { push: async message => ({ status: message.purpose === 'expiry' ? 'push_failed' : 'accepted_by_apns' }) });
  await f.submit(start);
  await f.receipt(start.id);
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  f.at(initialTime + 120000 + 86400000);
  await delay(30);
  await f.restart();
  f.at(initialTime + 120000 + 86400000 + 30000);
  await delay(30);
  assert.equal(f.expiry().length, 1);
});

test('closing during an in-flight expiry send prevents overlap and writes to the closed database', async t => {
  let complete;
  const held = new Promise(resolve => { complete = resolve; });
  const f = await fixture(t, { push: message => message.purpose === 'expiry'
    ? held : Promise.resolve({ status: 'accepted_by_apns' }) });
  await f.submit(start);
  await f.receipt(start.id);
  f.at(initialTime + 120000);
  await until(() => f.expiry().length === 1);
  f.at(initialTime + 180000);
  await delay(30);
  assert.equal(f.expiry().length, 1, 'A running send must serialize later worker ticks');
  await f.close();
  complete({ status: 'accepted_by_apns' });
  await delay(30);
  assert.equal(f.expiry().length, 1);
});
