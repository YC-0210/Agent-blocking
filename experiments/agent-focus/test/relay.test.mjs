import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRelay } from '../src/relay.mjs';

export const agentToken = 'test-agent-secret-at-least-32-characters';
export async function fixture(t, options = {}) {
  const relay = createRelay({ agentToken, database: ':memory:', ...options });
  await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => relay.server.close(resolve)); relay.close(); });
  const base = `http://127.0.0.1:${relay.server.address().port}`;
  async function request(path, body, token = agentToken, method = body === undefined ? 'GET' : 'POST') {
    const response = await fetch(base + path, { method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, body: await response.json() };
  }
  return { relay, base, request };
}

test('relay rejects an unauthenticated pairing request', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('/v1/pairings', {}, null)).status, 401);
});

test('pairing is single use and device credentials cannot create agent pairings', async t => {
  const { request } = await fixture(t);
  const invitation = await request('/v1/pairings', {});
  assert.equal(invitation.status, 201);
  const paired = await request('/v1/pairings/redeem', { code: invitation.body.code }, null);
  assert.equal(paired.status, 200);
  assert.equal(paired.body.deviceId, invitation.body.deviceId);
  assert.equal((await request('/v1/pairings/redeem', { code: invitation.body.code }, null)).status, 410);
  assert.equal((await request('/v1/pairings', {}, paired.body.deviceToken)).status, 401);
});

async function pair(request) {
  const invitation = (await request('/v1/pairings', {})).body;
  return (await request('/v1/pairings/redeem', { code: invitation.code }, null)).body;
}
const start = { id: 'request-1', action: 'start', modeID: 'work', durationMinutes: 30, sessionID: 's1' };

test('push acceptance stays pending until the paired phone acknowledges execution', async t => {
  const { request } = await fixture(t);
  const phone = await pair(request);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const queued = await request(path, start);
  assert.equal(queued.status, 202);
  assert.equal(queued.body.status, 'pending');
  const commands = (await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands;
  assert.equal(commands[0].id, 'request-1');
  assert.equal((await request('/v1/device/receipts', { id: 'request-1', status: 'applied' })).status, 401);
  assert.equal((await request('/v1/device/receipts', { id: 'request-1', status: 'applied' }, phone.deviceToken)).status, 200);
  assert.equal((await request(`${path}/request-1`)).body.status, 'applied');
});

test('retrying a command keeps its sequence and cannot rewrite its meaning', async t => {
  const { request } = await fixture(t);
  const phone = await pair(request);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const first = await request(path, start);
  const retry = await request(path, start);
  assert.equal(retry.status, 202);
  assert.deepEqual(retry.body.command, first.body.command);
  assert.equal((await request(path, { ...start, durationMinutes: 45 })).status, 409);
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands.length, 1);
});

test('undelivered commands expire and cannot be executed after reconnecting', async t => {
  let clock = 1793836800000;
  const { request } = await fixture(t, { now: () => clock });
  const phone = await pair(request);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  await request(path, start);
  clock += 120001;
  assert.deepEqual((await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands, []);
  assert.equal((await request(`${path}/request-1`)).body.status, 'expired');
});

test('another paired phone cannot acknowledge or inspect this phone command', async t => {
  const { request } = await fixture(t);
  const first = await pair(request), second = await pair(request);
  await request(`/v1/devices/${first.deviceId}/commands`, start);
  assert.equal((await request('/v1/device/receipts', { id: 'request-1', status: 'applied' }, second.deviceToken)).status, 404);
  assert.equal((await request(`/v1/devices/${first.deviceId}/commands/request-1`, undefined, second.deviceToken)).status, 401);
  // Terminal receipts cannot be overwritten by an old retry.
  await request('/v1/device/receipts', { id: 'request-1', status: 'rejected', reason: 'outside_approved_hours' }, first.deviceToken);
  assert.equal((await request('/v1/device/receipts', { id: 'request-1', status: 'applied' }, first.deviceToken)).status, 409);
});

test('phone publishes minimal observed status and push registration without Screen Time tokens', async t => {
  const { request } = await fixture(t);
  const phone = await pair(request);
  assert.equal((await request('/v1/device/snapshot', { modeID: 'work', sessionID: null, endAt: null, requiresRenewalApproval: false }, phone.deviceToken)).status, 200);
  const status = (await request(`/v1/devices/${phone.deviceId}`)).body;
  assert.equal(status.snapshot.modeID, 'work');
  assert.equal(typeof status.observedAt, 'number');
  assert.equal((await request('/v1/device/snapshot', { applicationTokens: ['private'] }, phone.deviceToken)).status, 400);
  assert.equal((await request('/v1/device/push', { token: 'a'.repeat(64) }, phone.deviceToken)).status, 200);
});

test('relay tries a silent push then offers a generic alert while execution remains pending', async t => {
  const pushes = [];
  const { request } = await fixture(t, { fallbackAfterMs: 10, push: async message => { pushes.push(message); return { status: 'accepted_by_apns' }; } });
  const phone = await pair(request);
  await request('/v1/device/push', { token: 'a'.repeat(64) }, phone.deviceToken);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const result = await request(path, start);
  assert.equal(result.body.status, 'pending');
  assert.equal(pushes[0].kind, 'background');
  await new Promise(resolve => setTimeout(resolve, 1100));
  assert.equal(pushes[1].kind, 'alert');
  assert.equal((await request(`${path}/request-1`)).body.status, 'pending');
});

test('relay sends an authenticated APNs background notification and keeps the command pending', async t => {
  const { createServer } = await import('node:http2');
  const { generateKeyPairSync, verify } = await import('node:crypto');
  const { createApnsPush } = await import('../src/apns.mjs');
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  let received;
  const apple = createServer();
  apple.on('stream', (stream, headers) => {
    let body = '';
    stream.on('data', chunk => { body += chunk; });
    stream.on('end', () => { received = { headers, body: JSON.parse(body) }; stream.respond({ ':status': 200 }); stream.end(); });
  });
  await new Promise(resolve => apple.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => apple.close(resolve)));
  const push = createApnsPush({ privateKey, teamId: 'TEAM', keyId: 'KEY', topic: 'online.do.card.app',
    origin: `http://127.0.0.1:${apple.address().port}` });
  const { request } = await fixture(t, { push });
  const phone = await pair(request);
  await request('/v1/device/push', { token: 'b'.repeat(64) }, phone.deviceToken);
  const result = await request(`/v1/devices/${phone.deviceId}/commands`, start);
  assert.equal(result.body.status, 'pending');
  assert.equal(received.headers['apns-push-type'], 'background');
  assert.equal(received.headers['apns-topic'], 'online.do.card.app');
  assert.deepEqual(received.body.aps, { 'content-available': 1 });
  const jwt = received.headers.authorization.replace('bearer ', '').split('.');
  assert.equal(verify('sha256', Buffer.from(`${jwt[0]}.${jwt[1]}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(jwt[2], 'base64url')), true);
});

test('phone snapshots accept absent optional values emitted by Swift Codable', async t => {
  const { request } = await fixture(t);
  const phone = await pair(request);
  const response = await request('/v1/device/snapshot', { modeID: 'work', requiresRenewalApproval: false }, phone.deviceToken);
  assert.equal(response.status, 200);
  const observed = (await request(`/v1/devices/${phone.deviceId}`)).body;
  assert.equal(observed.snapshot.sessionID, null);
  assert.equal(observed.snapshot.endAt, null);
});
