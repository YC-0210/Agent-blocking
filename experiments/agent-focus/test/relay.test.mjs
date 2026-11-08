import { test } from 'node:test';
import assert from 'node:assert/strict';
import { request as sendHTTP } from 'node:http';
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

test('scoped agents see only their phones and a phone can revoke its pairing', async t => {
  const { request } = await fixture(t);
  const first = await request('/v1/agents', {});
  const second = await request('/v1/agents', {});
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  assert.equal((await request('/v1/agents', {}, first.body.token)).status, 401);
  const invitation = await request('/v1/pairings', {}, first.body.token);
  assert.equal(invitation.status, 201);
  const { body: phone } = await request('/v1/pairings/redeem', { code: invitation.body.code }, null);
  const { body: own } = await request('/v1/devices', undefined, first.body.token);
  assert.deepEqual(own.devices.map(device => device.deviceId), [phone.deviceId]);
  assert.deepEqual((await request('/v1/devices')).body.devices, []);
  assert.deepEqual((await request('/v1/devices', undefined, second.body.token)).body.devices, []);
  const path = `/v1/devices/${phone.deviceId}`;
  assert.equal((await request(path, undefined, second.body.token)).status, 404);
  assert.equal((await request(`${path}/commands`, start, second.body.token)).status, 404);
  assert.equal((await request(`${path}/commands`, start, first.body.token)).status, 202);
  assert.equal((await request('/v1/device/pairing', undefined, first.body.token, 'DELETE')).status, 401);
  assert.equal((await request('/v1/device/pairing', undefined, phone.deviceToken, 'DELETE')).status, 200);
  assert.equal((await request('/v1/device/commands', undefined, phone.deviceToken)).status, 401);
  assert.equal((await request(`${path}/commands/${start.id}`, undefined, first.body.token)).status, 404);
});

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

test('relay immediately sends one visible extension push while execution remains pending', async t => {
  const pushes = [];
  let clock = 1793836800000;
  const { request } = await fixture(t, { now: () => clock, push: async message => { pushes.push(message); return { status: 'accepted_by_apns' }; } });
  const phone = await pair(request);
  await request('/v1/device/push', { token: 'a'.repeat(64) }, phone.deviceToken);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const result = await request(path, start);
  assert.equal(result.body.status, 'pending');
  assert.equal(pushes[0].kind, 'alert');
  clock += 20000;
  await new Promise(resolve => setTimeout(resolve, 1100));
  assert.equal(pushes.length, 1, 'Do not send a second fallback alert for an extension request');
  assert.equal((await request(`${path}/request-1`)).body.status, 'pending');
});

test('relay sends an authenticated mutable alert for the extension without leaking command details', async t => {
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
  assert.equal(received.headers['apns-push-type'], 'alert');
  assert.equal(received.headers['apns-priority'], '10');
  assert.equal(received.headers['apns-topic'], 'online.do.card.app');
  assert.equal(received.body.aps['mutable-content'], 1);
  assert.equal(received.body.aps.alert.body, 'A focus request is waiting. Open DO Card if it does not apply.');
  assert.equal(received.body.commandId, 'request-1');
  assert.equal(received.body.docardAgent, true);
  assert.equal(received.body.sessionID, undefined);
  assert.equal(received.body.modeID, undefined);
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

test('overlapping submissions allocate distinct ordered sequences after reading their bodies', async t => {
  const { request: httpRequest } = await import('node:http');
  const { base, request } = await fixture(t);
  const phone = await pair(request);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  let delayed;
  const firstResult = new Promise((resolve, reject) => {
    delayed = httpRequest(base + path, { method: 'POST', headers: {
      authorization: `Bearer ${agentToken}`, 'content-type': 'application/json', expect: '100-continue',
    } }, response => {
      let body = ''; response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolve(JSON.parse(body)));
    });
    delayed.on('error', reject);
  });
  const receivingHeaders = new Promise(resolve => delayed.once('continue', resolve));
  delayed.flushHeaders();
  await receivingHeaders;
  const fast = await request(path, { ...start, id: 'fast-stop', action: 'stop' });
  delayed.end(JSON.stringify(start));
  const slow = await firstResult;
  assert.notEqual(slow.command.sequence, fast.body.command.sequence);
  const queued = (await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands;
  assert.deepEqual(queued.map(command => command.sequence), [1, 2]);
});

test('confirmed maximum changes use a separate session-free command and keep phone acknowledgement authoritative', async t => {
  const { request } = await fixture(t);
  const phone = await pair(request);
  const path = `/v1/devices/${phone.deviceId}/commands`;
  const maximum = { id: 'max-1', action: 'set_maximum', modeID: 'work', maximumMinutes: 60,
    expectedMaximumMinutes: 45, userConfirmed: true };
  const response = await request(path, maximum);
  assert.equal(response.status, 202);
  assert.equal(response.body.status, 'pending');
  const queued = (await request('/v1/device/commands', undefined, phone.deviceToken)).body.commands;
  assert.equal(queued[0].maximumMinutes, 60);
  assert.equal('sessionID' in queued[0], false);
  assert.equal('durationMinutes' in queued[0], false);
  assert.equal((await request(path, { ...maximum, id: 'mixed', durationMinutes: 30 })).status, 400);
  assert.equal((await request(path, { ...maximum, id: 'unconfirmed', userConfirmed: false })).status, 400);
  assert.equal((await request(path, { ...start, id: 'start-with-max', maximumMinutes: 60 })).status, 400);
  await request('/v1/device/receipts', { id: 'max-1', status: 'applied' }, phone.deviceToken);
  assert.equal((await request(`${path}/max-1`)).body.status, 'applied');
});

test('a device can inspect its command result without using the agent credential', async t => {
  const { request } = await fixture(t);
  const phone = await pair(request), other = await pair(request);
  await request(`/v1/devices/${phone.deviceId}/commands`, start);
  const path = '/v1/device/commands/request-1';
  assert.equal((await request(path, undefined, other.deviceToken)).status, 404);
  assert.equal((await request(path, undefined, agentToken)).status, 401);
  await request('/v1/device/receipts', { id: 'request-1', status: 'applied' }, phone.deviceToken);
  const result = await request(path, undefined, phone.deviceToken);
  assert.equal(result.status, 200);
  assert.equal(result.body.status, 'applied');
  assert.equal(result.body.command.id, 'request-1');
});

test('phone can publish bounded selected app identities but not tokens or arbitrary icon URLs', async t => {
  const { request } = await fixture(t); const phone = await pair(request);
  const snapshot = { modeID: 'work', requiresRenewalApproval: false, maximumMinutes: 45,
    selectionSummary: { applications: 2, categories: 0, websites: 0 },
    selectedAppIDs: ['com.burbn.instagram', 'com.supercell.laser'] };
  assert.equal((await request('/v1/device/snapshot', snapshot, phone.deviceToken)).status, 200);
  assert.deepEqual((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, snapshot.selectedAppIDs);
  for (const invalid of [['private token'], ['https://evil.example/icon.png'], Array(51).fill('com.example.app'),
    ['com.burbn.instagram', 'com.burbn.instagram']]) {
    assert.equal((await request('/v1/device/snapshot', { ...snapshot, selectedAppIDs: invalid }, phone.deviceToken)).status, 400);
  }
  assert.equal((await request('/v1/device/snapshot', { ...snapshot, selectedAppIDs: ['com.a.app','com.b.app','com.c.app'] }, phone.deviceToken)).status, 400);
});

test('snapshot accepts fifty long valid bundle identifiers within its bounded payload', async t => {
  const { request } = await fixture(t); const phone = await pair(request);
  const ids = Array.from({ length: 50 }, (_, i) => `com.example.${String(i).padStart(3, '0')}${'a'.repeat(230)}`);
  const result = await request('/v1/device/snapshot', { modeID: 'work', requiresRenewalApproval: false,
    maximumMinutes: 45, selectionSummary: { applications: 50, categories: 0, websites: 0 }, selectedAppIDs: ids }, phone.deviceToken);
  assert.equal(result.status, 200);
});

test('paired phone discovery is agent-only, excludes invitations and never exposes credentials', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('/v1/devices', undefined, null)).status, 401);
  const phone = await pair(request);
  await request('/v1/pairings', {});
  assert.equal((await request('/v1/devices', undefined, phone.deviceToken)).status, 401);
  const response = await request('/v1/devices');
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.devices, [{ deviceId: phone.deviceId, observedAt: null }]);
  assert.equal(JSON.stringify(response.body).includes(phone.deviceToken), false);
  assert.equal(JSON.stringify(response.body).includes('tokenHash'), false);
});

const identityA = '22222222-2222-4222-8222-222222222222';
const identityB = '33333333-3333-4333-8333-333333333333';
const iconSnapshot = { modeID: 'work', requiresRenewalApproval: false, maximumMinutes: 45,
  selectionIdentity: identityA, selectionSummary: { applications: 2, categories: 0, websites: 0 } };
const iconIDs = ['com.burbn.instagram', 'com.supercell.laser'];

test('matching selection identity retains approved icons across background start and expiry snapshots', async t => {
  const { request } = await fixture(t); const phone = await pair(request);
  await request('/v1/device/snapshot', { ...iconSnapshot, selectedAppIDs: iconIDs }, phone.deviceToken);
  for (const update of [{ sessionID: 'session', endAt: Date.now() + 120000 },
    { modeID: 'after-expiry', sessionID: null, requiresRenewalApproval: true }]) {
    assert.equal((await request('/v1/device/snapshot', { ...iconSnapshot, ...update }, phone.deviceToken)).status, 200);
    assert.deepEqual((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, iconIDs);
  }
});

test('changed or missing selection identity never inherits icons just because app counts match', async t => {
  const { request } = await fixture(t); const phone = await pair(request);
  for (const selectionIdentity of [identityB, undefined]) {
    await request('/v1/device/snapshot', { ...iconSnapshot, selectedAppIDs: iconIDs }, phone.deviceToken);
    await request('/v1/device/snapshot', { ...iconSnapshot, selectionIdentity }, phone.deviceToken);
    assert.equal((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, undefined);
  }
});

test('explicit identity revocation clears icons and later unknown background updates cannot restore them', async t => {
  const { request } = await fixture(t); const phone = await pair(request);
  await request('/v1/device/snapshot', { ...iconSnapshot, selectedAppIDs: iconIDs }, phone.deviceToken);
  await request('/v1/device/snapshot', { ...iconSnapshot, selectionIdentity: undefined, selectedAppIDs: [] }, phone.deviceToken);
  assert.deepEqual((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, []);
  await request('/v1/device/snapshot', iconSnapshot, phone.deviceToken);
  assert.equal((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, undefined);
});

test('a mismatched application count or malformed selection identity cannot retain known icons', async t => {
  const { request } = await fixture(t); const phone = await pair(request);
  await request('/v1/device/snapshot', { ...iconSnapshot, selectedAppIDs: iconIDs }, phone.deviceToken);
  const mismatch = { ...iconSnapshot, selectionSummary: { applications: 1, categories: 0, websites: 0 } };
  await request('/v1/device/snapshot', mismatch, phone.deviceToken);
  assert.equal((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, undefined);
  assert.equal((await request('/v1/device/snapshot', { ...iconSnapshot, selectionIdentity: 'opaque-token-or-hash' }, phone.deviceToken)).status, 400);
});


test('a slow background upload cannot resurrect identities cleared while its body was arriving', { timeout: 5000 }, async t => {
  const { request, relay, base } = await fixture(t); const phone = await pair(request);
  await request('/v1/device/snapshot', { ...iconSnapshot, selectedAppIDs: iconIDs }, phone.deviceToken);
  const entered = new Promise(resolve => relay.server.once('request', resolve));
  const payload = JSON.stringify(iconSnapshot);
  let stalled;
  const finished = new Promise((resolve, reject) => {
    stalled = sendHTTP(base + '/v1/device/snapshot', { method: 'POST', headers: {
      authorization: `Bearer ${phone.deviceToken}`, 'content-type': 'application/json' } }, response => {
      response.resume(); response.on('end', () => resolve(response.statusCode));
    });
    stalled.on('error', reject);
  });
  t.after(() => stalled.destroy());
  stalled.write(payload.slice(0, 10));
  await entered;
  await request('/v1/device/snapshot', { ...iconSnapshot, selectionIdentity: undefined, selectedAppIDs: [] }, phone.deviceToken);
  stalled.end(payload.slice(10));
  assert.equal(await finished, 200);
  assert.equal((await request(`/v1/devices/${phone.deviceId}`)).body.snapshot.selectedAppIDs, undefined);
});
