import { createServer } from 'node:http';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { DatabaseSync } from 'node:sqlite';

const commandSchema = z.object({
  id: z.string().min(1).max(80), action: z.enum(['start', 'stop']),
  modeID: z.string().min(1).max(80), sessionID: z.string().min(1).max(80),
  durationMinutes: z.number().int().min(15).max(1440).optional(), renewalConfirmed: z.boolean().optional(),
}).strict();
const receiptSchema = z.object({ id: z.string().min(1).max(80),
  status: z.enum(['applied', 'rejected']), reason: z.string().max(100).optional().nullable() }).strict();
const snapshotSchema = z.object({ modeID: z.string().min(1).max(80),
  sessionID: z.string().max(80).nullable().optional().default(null), endAt: z.number().finite().nullable().optional().default(null),
  requiresRenewalApproval: z.boolean(), maximumMinutes: z.number().int().optional(),
  startMinute: z.number().int().optional(), endMinute: z.number().int().optional(),
  timeZone: z.string().max(100).optional() }).strict();
const hash = value => createHash('sha256').update(value).digest('hex');
function matches(a, b) {
  const x = Buffer.from(a ?? ''), y = Buffer.from(b ?? '');
  return x.length === y.length && timingSafeEqual(x, y);
}
function fail(status, message) { throw Object.assign(new Error(message), { status }); }
async function readBody(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (Buffer.byteLength(body) > 8192) fail(413, 'body_too_large');
  }
  try { return JSON.parse(body || '{}'); } catch { fail(400, 'invalid_json'); }
}
export function createRelay({ agentToken, database = 'agent-focus.sqlite', now = Date.now,
  push = async () => ({ status: 'unconfigured' }), fallbackAfterMs = 15000 }) {
  if (!agentToken || agentToken.length < 32) throw new Error('Agent token must contain at least 32 characters');
  const db = new DatabaseSync(database);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, tokenHash TEXT, pushToken TEXT,
      snapshot TEXT, observedAt REAL, sequence INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS pairings (codeHash TEXT PRIMARY KEY, deviceId TEXT, expiresAt REAL);
    CREATE TABLE IF NOT EXISTS commands (deviceId TEXT, id TEXT, command TEXT, request TEXT,
      status TEXT NOT NULL, reason TEXT, alertSent INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(deviceId, id));`);
  async function notify(device, command, kind) {
    if (!device.pushToken) return { status: 'phone_registration_required' };
    try { return await push({ token: device.pushToken, commandId: command.id, expiresAt: command.expiresAt, kind }); }
    catch { return { status: 'push_failed' }; }
  }
  const fallback = setInterval(async () => {
    const rows = db.prepare("SELECT * FROM commands WHERE status = 'pending' AND alertSent = 0 AND json_extract(command, '$.issuedAt') <= ? AND json_extract(command, '$.expiresAt') > ?")
      .all(now() - fallbackAfterMs, now());
    for (const row of rows) {
      db.prepare('UPDATE commands SET alertSent = 1 WHERE deviceId = ? AND id = ?').run(row.deviceId, row.id);
      const device = db.prepare('SELECT * FROM devices WHERE id = ?').get(row.deviceId);
      await notify(device, JSON.parse(row.command), 'alert');
    }
  }, 1000);
  fallback.unref();
  const server = createServer(async (req, res) => {
    const send = (status, value) => {
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify(value));
    };
    try {
      db.prepare("UPDATE commands SET status = 'expired', reason = 'delivery_expired' WHERE status = 'pending' AND json_extract(command, '$.expiresAt') <= ?").run(now());
      const path = new URL(req.url, 'http://localhost').pathname;
      const isAgent = matches(req.headers.authorization, `Bearer ${agentToken}`);
      if (req.method === 'POST' && path === '/v1/pairings/redeem') {
        const { code } = await readBody(req);
        if (typeof code !== 'string' || code.length > 128) fail(400, 'invalid_code');
        const pairing = db.prepare('SELECT * FROM pairings WHERE codeHash = ?').get(hash(code));
        if (!pairing || pairing.expiresAt <= now()) fail(410, 'pairing_expired_or_used');
        const secret = randomBytes(32).toString('hex');
        db.prepare('INSERT INTO devices (id, tokenHash) VALUES (?, ?)').run(pairing.deviceId, hash(secret));
        db.prepare('DELETE FROM pairings WHERE codeHash = ?').run(hash(code));
        return send(200, { deviceId: pairing.deviceId, deviceToken: `${pairing.deviceId}.${secret}` });
      }
      const credential = (req.headers.authorization ?? '').replace(/^Bearer /, '');
      const [deviceId, secret] = credential.split('.');
      const device = secret && db.prepare('SELECT * FROM devices WHERE id = ?').get(deviceId);
      const isDevice = device && matches(device.tokenHash, hash(secret));
      if (path.startsWith('/v1/device/')) {
        if (!isDevice) fail(401, 'unauthorized');
        if (req.method === 'POST' && path === '/v1/device/push') {
          const { token } = await readBody(req);
          if (typeof token !== 'string' || !/^[a-f0-9]{64,200}$/.test(token)) fail(400, 'invalid_push_token');
          db.prepare('UPDATE devices SET pushToken = ? WHERE id = ?').run(token, deviceId);
          return send(200, { accepted: true });
        }
        if (req.method === 'POST' && path === '/v1/device/snapshot') {
          const parsed = snapshotSchema.safeParse(await readBody(req));
          if (!parsed.success) fail(400, 'invalid_snapshot');
          db.prepare('UPDATE devices SET snapshot = ?, observedAt = ? WHERE id = ?')
            .run(JSON.stringify(parsed.data), now(), deviceId);
          return send(200, { accepted: true });
        }
        if (req.method === 'GET' && path === '/v1/device/commands') {
          const rows = db.prepare("SELECT command FROM commands WHERE deviceId = ? AND status = 'pending' ORDER BY json_extract(command, '$.sequence')").all(deviceId);
          return send(200, { commands: rows.map(row => JSON.parse(row.command)) });
        }
        if (req.method === 'POST' && path === '/v1/device/receipts') {
          const parsed = receiptSchema.safeParse(await readBody(req));
          if (!parsed.success) fail(400, 'invalid_receipt');
          const receipt = parsed.data;
          const row = db.prepare('SELECT * FROM commands WHERE deviceId = ? AND id = ?').get(deviceId, receipt.id);
          if (!row) fail(404, 'unknown_command');
          if (['applied', 'rejected'].includes(row.status) &&
            (row.status !== receipt.status || row.reason !== (receipt.reason ?? null))) fail(409, 'receipt_conflict');
          db.prepare('UPDATE commands SET status = ?, reason = ? WHERE deviceId = ? AND id = ?')
            .run(receipt.status, receipt.reason ?? null, deviceId, receipt.id);
          return send(200, { accepted: true });
        }
        fail(404, 'not_found');
      }
      if (!isAgent) fail(401, 'unauthorized');
      const statusRoute = path.match(/^\/v1\/devices\/([a-f0-9-]+)$/);
      if (req.method === 'GET' && statusRoute) {
        const target = db.prepare('SELECT * FROM devices WHERE id = ?').get(statusRoute[1]);
        if (!target) fail(404, 'unknown_device');
        return send(200, { snapshot: target.snapshot ? JSON.parse(target.snapshot) : null, observedAt: target.observedAt });
      }
      const route = path.match(/^\/v1\/devices\/([a-f0-9-]+)\/commands(?:\/([^/]+))?$/);
      if (route) {
        const target = db.prepare('SELECT * FROM devices WHERE id = ?').get(route[1]);
        if (!target) fail(404, 'unknown_device');
        if (req.method === 'GET' && route[2]) {
          const row = db.prepare('SELECT * FROM commands WHERE deviceId = ? AND id = ?').get(target.id, decodeURIComponent(route[2]));
          if (!row) fail(404, 'unknown_command');
          return send(200, { command: JSON.parse(row.command), status: row.status, reason: row.reason });
        }
        if (req.method === 'POST' && !route[2]) {
          const parsed = commandSchema.safeParse(await readBody(req));
          if (!parsed.success) fail(400, 'invalid_command');
          const request = parsed.data;
          const existing = db.prepare('SELECT * FROM commands WHERE deviceId = ? AND id = ?').get(target.id, request.id);
          if (existing) {
            if (existing.request !== JSON.stringify(request)) fail(409, 'command_id_conflict');
            return send(existing.status === 'pending' ? 202 : 200,
              { command: JSON.parse(existing.command), status: existing.status, reason: existing.reason });
          }
          const command = { ...request, sequence: target.sequence + 1, issuedAt: now(), expiresAt: now() + 120000 };
          db.prepare('INSERT INTO commands (deviceId, id, command, request, status, reason) VALUES (?, ?, ?, ?, ?, ?)')
            .run(target.id, request.id, JSON.stringify(command), JSON.stringify(request), 'pending', null);
          db.prepare('UPDATE devices SET sequence = ? WHERE id = ?').run(command.sequence, target.id);
          const delivery = await notify(target, command, 'background');
          return send(202, { command, status: 'pending', delivery });
        }
      }
      if (req.method === 'POST' && path === '/v1/pairings') {
        const deviceId = randomUUID(), code = randomBytes(16).toString('hex');
        const expiresAt = now() + 600000;
        db.prepare('INSERT INTO pairings VALUES (?, ?, ?)').run(hash(code), deviceId, expiresAt);
        return send(201, { deviceId, code, expiresAt });
      }
      fail(404, 'not_found');
    } catch (error) { send(error.status ?? 500, { error: error.status ? error.message : 'internal_error' }); }
  });
  return { server, close() { clearInterval(fallback); db.close(); } };
}
