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
  const agentToken = readFileSync(required('DO_CARD_AGENT_TOKEN_FILE'), 'utf8').trim();
  const privateKey = createPrivateKey(readFileSync(required('APNS_KEY_FILE')));
  const database = process.env.DO_CARD_DATABASE ?? new URL('../.local/agent-focus.sqlite', import.meta.url).pathname;
  mkdirSync(dirname(database), { recursive: true, mode: 0o700 });
  const relay = createRelay({ agentToken, database, push: createApnsPush({ privateKey,
    teamId: required('APNS_TEAM_ID'), keyId: required('APNS_KEY_ID'),
    topic: process.env.APNS_TOPIC ?? 'online.do.card.app',
    sandbox: process.env.APNS_ENVIRONMENT !== 'production',
  }) });
  chmodSync(database, 0o600);
  const port = Number(process.env.PORT ?? 8787);
  relay.server.listen(port, '127.0.0.1', () => console.error(`DO Card relay listening on http://127.0.0.1:${port}`));
  const shutdown = () => relay.server.close(() => { relay.close(); process.exit(0); });
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
} catch (error) {
  console.error(`DO Card relay: ${error.message}`);
  process.exitCode = 1;
}
