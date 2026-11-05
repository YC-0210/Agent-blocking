import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { createServer } from 'node:http2';
import { createApnsPush } from '../src/apns.mjs';

const commandId = 'focus-command-opaque-17';
const token = 'd'.repeat(64);
// Independent SHA-256 reference values for commandId and "expiry:" + commandId.
const commandCollapse = '865633a4f18e72cf7932bee447c6c4182622cef71b76c5472708cb34e5a1fc55';
const expiryCollapse = '2ce9e9cf20ac6df1ae5f8f3c57371caef1167d563350d8e05d1555cbfaaa8b11';

async function fixture(t) {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const received = [];
  const connections = new Set();
  const apple = createServer();
  apple.on('session', session => {
    connections.add(session);
    session.on('close', () => connections.delete(session));
  });
  apple.on('stream', (stream, headers) => {
    let body = '';
    stream.setEncoding('utf8');
    stream.on('data', chunk => { body += chunk; });
    stream.on('end', () => {
      received.push({ headers, body: JSON.parse(body) });
      stream.respond({ ':status': 200 });
      stream.end();
    });
  });
  t.after(async () => {
    for (const session of connections) session.destroy();
    await new Promise(resolve => apple.close(resolve));
  });
  await new Promise((resolve, reject) => {
    apple.once('error', reject);
    apple.listen(0, '127.0.0.1', resolve);
  });
  const push = createApnsPush({
    privateKey, teamId: 'ISOLATED_TEAM', keyId: 'ISOLATED_KEY', topic: 'isolated.docard.test',
    origin: `http://127.0.0.1:${apple.address().port}`,
  });
  return { push, received };
}

test('expiry recovery is a visible mutable alert with an expiry marker and the original opaque command ID', async t => {
  const { push, received } = await fixture(t);
  // The sender supplies the deadline + 24-hour recovery window; transport preserves it.
  const result = await push({ token, commandId, kind: 'alert', purpose: 'expiry', expiresAt: 1793923320000 });
  assert.deepEqual(result, { status: 'accepted_by_apns' });
  assert.equal(received.length, 1);
  const { headers, body } = received[0];
  assert.equal(headers['apns-push-type'], 'alert');
  assert.equal(headers['apns-priority'], '10');
  assert.equal(headers['apns-expiration'], '1793923320');
  assert.equal(body.aps['mutable-content'], 1);
  assert.equal(typeof body.aps.alert.title, 'string');
  assert.ok(body.aps.alert.title.length > 0);
  assert.equal(typeof body.aps.alert.body, 'string');
  assert.ok(body.aps.alert.body.length > 0);
  assert.equal(body.docardAgent, true);
  assert.equal(body.docardExpiry, true);
  assert.equal(body.commandId, commandId);
  assert.deepEqual(Object.keys(body).sort(), ['aps', 'commandId', 'docardAgent', 'docardExpiry']);
  const serialized = JSON.stringify(body);
  for (const secret of [token, 'ISOLATED_TEAM', 'ISOLATED_KEY', 'PRIVATE KEY']) {
    assert.equal(serialized.includes(secret), false);
  }
});

test('expiry recovery uses a separate stable collapse identity from the original start alert', async t => {
  const { push, received } = await fixture(t);
  await push({ token, commandId, kind: 'alert', expiresAt: 1793836920000 });
  await push({ token, commandId, kind: 'alert', purpose: 'expiry', expiresAt: 1793923320000 });
  await push({ token, commandId, kind: 'alert', purpose: 'expiry', expiresAt: 1793923320000 });
  assert.equal(received.length, 3);
  assert.equal(received[0].headers['apns-collapse-id'], commandCollapse);
  assert.equal(received[1].headers['apns-collapse-id'], expiryCollapse);
  assert.equal(received[2].headers['apns-collapse-id'], expiryCollapse);
  assert.notEqual(received[0].headers['apns-collapse-id'], received[1].headers['apns-collapse-id']);
  assert.deepEqual(received.map(message => message.body.commandId), [commandId, commandId, commandId]);
});

test('ordinary alert and background pushes keep their existing payloads without an expiry marker', async t => {
  const { push, received } = await fixture(t);
  for (const kind of ['alert', 'background']) {
    assert.deepEqual(
      await push({ token, commandId, kind, expiresAt: 1793836920000 }),
      { status: 'accepted_by_apns' });
  }
  assert.equal(received.length, 2);
  const [alert, background] = received;
  assert.equal(alert.headers['apns-push-type'], 'alert');
  assert.equal(alert.headers['apns-priority'], '10');
  assert.deepEqual(alert.body.aps, {
    'mutable-content': 1,
    alert: { title: 'DO Card', body: 'A focus request is waiting. Open DO Card if it does not apply.' },
    sound: 'default',
  });
  assert.equal(background.headers['apns-push-type'], 'background');
  assert.equal(background.headers['apns-priority'], '5');
  assert.deepEqual(background.body.aps, { 'content-available': 1 });
  for (const { headers, body } of received) {
    assert.equal(headers['apns-expiration'], '1793836920');
    assert.equal(headers['apns-collapse-id'], commandCollapse);
    assert.deepEqual(Object.keys(body).sort(), ['aps', 'commandId', 'docardAgent']);
    assert.equal(Object.hasOwn(body, 'docardExpiry'), false);
    assert.equal(body.docardAgent, true);
    assert.equal(body.commandId, commandId);
  }
});
