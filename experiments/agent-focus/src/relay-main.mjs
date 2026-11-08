import { mkdirSync, readFileSync, chmodSync } from 'node:fs';
import { createPrivateKey } from 'node:crypto';
import { dirname } from 'node:path';
import { createRelay } from './relay.mjs';
import { createApnsPush } from './apns.mjs';

const required = name => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}; see experiments/agent-focus/README.md`);
  return value;
};
try {
  const agentToken = (process.env.DO_CARD_AGENT_TOKEN ??
    readFileSync(required('DO_CARD_AGENT_TOKEN_FILE'), 'utf8')).trim();
  const privateKey = createPrivateKey(process.env.APNS_PRIVATE_KEY ??
    readFileSync(required('APNS_KEY_FILE'), 'utf8'));
  const apnsEnvironment = process.env.APNS_ENVIRONMENT ?? 'development';
  if (!['development', 'production'].includes(apnsEnvironment)) {
    throw new Error('APNS_ENVIRONMENT must be development or production');
  }
  const database = process.env.DO_CARD_DATABASE ?? new URL('../.local/agent-focus.sqlite', import.meta.url).pathname;
  mkdirSync(dirname(database), { recursive: true, mode: 0o700 });
  const topic = process.env.APNS_TOPIC ?? 'online.do.card.app';
  const appName = topic === 'online.do.card.agentblocking' ? 'Agent Blocking' : 'DO Card';
  const sendPush = createApnsPush({ privateKey,
    teamId: required('APNS_TEAM_ID'), keyId: required('APNS_KEY_ID'),
    topic, appName,
    sandbox: apnsEnvironment !== 'production',
  });
  const relay = createRelay({ agentToken, database, phoneAppBundleID: topic, apnsEnvironment, expiryIntervalMs: 1000,
    onDeliveryIssue: (event, count) => console.warn(JSON.stringify({ event, count })),
    push: async message => {
      try { return await sendPush(message); }
      catch (error) {
        const code = error?.code ?? error?.message;
        const safeCode = typeof code === 'string' && /^[A-Za-z0-9_]{1,96}$/.test(code)
          ? code : 'unknown_error';
        console.warn(`APNs delivery failed: ${safeCode}`);
        throw error;
      }
    },
  });
  chmodSync(database, 0o600);
  const port = Number(process.env.PORT ?? 8787);
  const host = process.env.HOST ?? '127.0.0.1';
  relay.server.listen(port, host, () => console.error(`DO Card relay listening on http://${host}:${relay.server.address().port}`));
  const shutdown = () => relay.server.close(() => { relay.close(); process.exit(0); });
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
} catch (error) {
  console.error(`DO Card relay: ${error.message}`);
  process.exitCode = 1;
}
