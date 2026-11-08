import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';

const runner = new URL('../src/relay-main.mjs', import.meta.url);
const privateKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1',
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' } }).privateKey;

async function configuration(t) {
  const directory = await mkdtemp(join(tmpdir(), 'docard-hosting-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return { directory, token: randomBytes(32).toString('hex') };
}

async function start(t, configuration, overrides = {}) {
  const env = { ...process.env };
  for (const name of Object.keys(env)) {
    if (/^(DO_CARD_|APNS_|RAILWAY_)/.test(name)) delete env[name];
  }
  Object.assign(env, { PORT: '0', HOST: '0.0.0.0',
    DO_CARD_DATABASE: join(configuration.directory, 'relay.sqlite'),
    DO_CARD_AGENT_TOKEN: configuration.token, APNS_PRIVATE_KEY: privateKey,
    APNS_TEAM_ID: 'TEST_TEAM', APNS_KEY_ID: 'TEST_KEY', APNS_ENVIRONMENT: 'development',
    ...overrides });
  for (const name of Object.keys(env)) if (env[name] === undefined) delete env[name];
  const child = spawn(process.execPath, [runner.pathname], { env, stdio: ['ignore', 'ignore', 'pipe'] });
  const exited = once(child, 'exit');
  const stop = async () => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM'); await exited; };
  t.after(stop);
  const base = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('relay startup timed out')), 10000);
    const lines = createInterface({ input: child.stderr });
    lines.on('line', line => {
      const match = line.match(/listening on http:\/\/0\.0\.0\.0:(\d+)/);
      if (match) { clearTimeout(timeout); resolve(`http://127.0.0.1:${match[1]}`); }
    });
    child.once('error', error => { clearTimeout(timeout); reject(error); });
    child.once('exit', () => { clearTimeout(timeout); reject(new Error('relay exited before listening')); });
  });
  return { base, stop };
}

test('hosted runner accepts environment secrets, protects APIs and preserves pairing across restart', async t => {
  const config = await configuration(t);
  const topic = 'online.do.card.agentblocking';
  const first = await start(t, config, { APNS_TOPIC: topic, APNS_ENVIRONMENT: 'production' });
  const health = await fetch(`${first.base}/healthz`);
  assert.equal(health.status, 200);
  assert.equal(health.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await health.json(), { status: 'ok' });
  assert.equal((await fetch(`${first.base}/v1/pairings`, { method: 'POST' })).status, 401);
  assert.equal((await fetch(`${first.base}/healthz`, { method: 'POST' })).status, 401);
  const phoneApp = await fetch(`${first.base}/v1/phone-app`);
  assert.equal(phoneApp.status, 200);
  assert.deepEqual(await phoneApp.json(), { bundleID: topic, apnsEnvironment: 'production' });
  const invitation = await fetch(`${first.base}/v1/pairings`, { method: 'POST',
    headers: { authorization: `Bearer ${config.token}`, 'content-type': 'application/json' }, body: '{}' });
  assert.equal(invitation.status, 201);
  const { code } = await invitation.json();
  const redemption = await fetch(`${first.base}/v1/pairings/redeem`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ code }) });
  assert.equal(redemption.status, 200);
  const { deviceToken } = await redemption.json();
  await first.stop();
  const second = await start(t, config, { APNS_TOPIC: topic });
  assert.deepEqual(await (await fetch(`${second.base}/v1/phone-app`)).json(),
    { bundleID: topic, apnsEnvironment: 'development' });
  const commands = await fetch(`${second.base}/v1/device/commands`, {
    headers: { authorization: `Bearer ${deviceToken}` } });
  assert.equal(commands.status, 200);
  assert.deepEqual((await commands.json()).commands, []);
});

test('local runner still accepts credential files', async t => {
  const config = await configuration(t);
  const tokenFile = join(config.directory, 'agent-token');
  const keyFile = join(config.directory, 'apns.p8');
  await writeFile(tokenFile, `${config.token}\n`, { mode: 0o600 });
  await writeFile(keyFile, privateKey, { mode: 0o600 });
  const relay = await start(t, config, { DO_CARD_AGENT_TOKEN: undefined, APNS_PRIVATE_KEY: undefined,
    DO_CARD_AGENT_TOKEN_FILE: tokenFile, APNS_KEY_FILE: keyFile });
  const response = await fetch(`${relay.base}/v1/pairings`, { method: 'POST',
    headers: { authorization: `Bearer ${config.token}`, 'content-type': 'application/json' }, body: '{}' });
  assert.equal(response.status, 201);
});
