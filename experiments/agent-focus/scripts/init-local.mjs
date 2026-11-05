import { mkdirSync, existsSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

const directory = new URL('../.local/', import.meta.url);
mkdirSync(directory, { recursive: true, mode: 0o700 });
const token = new URL('agent-token', directory);
if (!existsSync(token)) writeFileSync(token, randomBytes(32).toString('hex'), { flag: 'wx', mode: 0o600 });
const env = new URL('relay.env', directory);
if (!existsSync(env)) writeFileSync(env, [
  `DO_CARD_AGENT_TOKEN_FILE=${JSON.stringify(token.pathname)}`,
  'APNS_KEY_FILE="/absolute/path/to/AuthKey_YOUR_KEY_ID.p8"',
  'APNS_TEAM_ID="YOUR_APPLE_TEAM_ID"',
  'APNS_KEY_ID="YOUR_KEY_ID"',
  'APNS_TOPIC="online.do.card.app"',
  'APNS_ENVIRONMENT="development"',
  'PORT=8787', '',
].join('\n'), { flag: 'wx', mode: 0o600 });
console.log(`Created private local configuration in ${directory.pathname}. Edit relay.env with your APNs key path and IDs. Existing credentials were preserved.`);
