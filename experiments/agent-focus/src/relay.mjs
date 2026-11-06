import { createServer } from 'node:http';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { DatabaseSync } from 'node:sqlite';
import { commandSchema } from './focus-command-schema.mjs';

const receiptSchema = z.object({ id: z.string().min(1).max(80),
  status: z.enum(['applied', 'rejected']), reason: z.string().max(100).optional().nullable() }).strict();
const snapshotSchema = z.object({ modeID: z.string().min(1).max(80),
  sessionID: z.string().max(80).nullable().optional().default(null), endAt: z.number().finite().nullable().optional().default(null),
  requiresRenewalApproval: z.boolean(), maximumMinutes: z.number().int().optional(),
  startMinute: z.number().int().optional(), endMinute: z.number().int().optional(),
  timeZone: z.string().max(100).optional(),
  selectionSummary: z.object({ applications: z.number().int().min(0).max(10000),
    categories: z.number().int().min(0).max(10000), websites: z.number().int().min(0).max(10000) }).strict().optional(),
  selectedAppIDs: z.array(z.string().max(255).regex(/^[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$/)).max(50)
    .refine(ids => new Set(ids).size === ids.length).optional(),
  selectionIdentity: z.string().uuid().optional(),
  appGroups: z.array(z.object({ id: z.string().regex(/^[a-zA-Z0-9-]{1,80}$/),
    name: z.string().trim().min(1).max(40).regex(/^[^\x00-\x1f\x7f]+$/),
    iconKey: z.enum(['instagram', 'tiktok', 'youtube', 'facebook', 'reddit', 'x', 'other']).optional() }).strict()).max(8)
    .refine(groups => new Set(groups.map(group => group.id)).size === groups.length).optional(),
  activeAppGroupID: z.string().regex(/^[a-zA-Z0-9-]{1,80}$/).nullable().optional() }).strict()
  .refine(snapshot => !snapshot.selectedAppIDs || snapshot.selectedAppIDs.length === 0 ||
    (snapshot.selectionSummary && snapshot.selectedAppIDs.length <= snapshot.selectionSummary.applications));
const hash = value => createHash('sha256').update(value).digest('hex');
function matches(a, b) {
  const x = Buffer.from(a ?? ''), y = Buffer.from(b ?? '');
  return x.length === y.length && timingSafeEqual(x, y);
}
function fail(status, message) { throw Object.assign(new Error(message), { status }); }
async function readBody(req) {
  let body = '';
  const limit = req.url === '/v1/device/snapshot' ? 32768 : 8192;
  for await (const chunk of req) {
    body += chunk;
    if (Buffer.byteLength(body) > limit) fail(413, 'body_too_large');
  }
  try { return JSON.parse(body || '{}'); } catch { fail(400, 'invalid_json'); }
}
export function createRelay({ agentToken, database = 'agent-focus.sqlite', now = Date.now,
  push = async () => ({ status: 'unconfigured' }), expiryIntervalMs = null }) {
  if (!agentToken || agentToken.length < 32) throw new Error('Agent token must contain at least 32 characters');
  if (expiryIntervalMs !== null && (!Number.isInteger(expiryIntervalMs) || expiryIntervalMs < 1)) {
    throw new Error('Expiry worker interval must be a positive integer or null');
  }
  const db = new DatabaseSync(database);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, tokenHash TEXT, pushToken TEXT,
      snapshot TEXT, observedAt REAL, sequence INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS pairings (codeHash TEXT PRIMARY KEY, deviceId TEXT, expiresAt REAL);
    CREATE TABLE IF NOT EXISTS commands (deviceId TEXT, id TEXT, command TEXT, request TEXT,
      status TEXT NOT NULL, reason TEXT, alertSent INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(deviceId, id));
    CREATE TABLE IF NOT EXISTS expiryJobs (deviceId TEXT, commandId TEXT, sessionId TEXT,
      dueAt REAL NOT NULL, status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      nextAttemptAt REAL NOT NULL, PRIMARY KEY(deviceId, commandId));
    CREATE INDEX IF NOT EXISTS expiryJobs_due ON expiryJobs(status, nextAttemptAt);`);
  let closed = false;
  let expiryRunning = false;
  async function deliverExpiries() {
    if (closed || expiryRunning) return;
    expiryRunning = true;
    try {
      const tick = now();
      db.prepare("UPDATE expiryJobs SET status = 'expired' WHERE status = 'pending' AND dueAt + 86400000 <= ?").run(tick);
      const jobs = db.prepare("SELECT * FROM expiryJobs WHERE status = 'pending' AND dueAt <= ? AND nextAttemptAt <= ? ORDER BY nextAttemptAt LIMIT 10").all(tick, tick);
      for (const job of jobs) {
        if (closed) return;
        const claimedAt = now();
        // Persist a retry lease before APNs I/O. A crash may repeat an uncertain send,
        // but cannot lose the job or create a tight restart loop.
        const claimed = db.prepare("UPDATE expiryJobs SET attempts = attempts + 1, nextAttemptAt = ? WHERE deviceId = ? AND commandId = ? AND status = 'pending' AND nextAttemptAt <= ? AND dueAt <= ? AND dueAt + 86400000 > ?")
          .run(claimedAt + 30000, job.deviceId, job.commandId, claimedAt, claimedAt, claimedAt);
        if (!claimed.changes) continue;
        const device = db.prepare('SELECT pushToken FROM devices WHERE id = ?').get(job.deviceId);
        let delivery;
        try {
          delivery = device?.pushToken ? await push({ token: device.pushToken, commandId: job.commandId,
            expiresAt: job.dueAt + 86400000, kind: 'alert', purpose: 'expiry' }) : null;
        } catch { delivery = null; }
        if (closed) return;
        if (delivery?.status === 'accepted_by_apns') {
          db.prepare("UPDATE expiryJobs SET status = 'sent' WHERE deviceId = ? AND commandId = ? AND status = 'pending'")
            .run(job.deviceId, job.commandId);
        }
      }
    } finally { expiryRunning = false; }
  }
  const expiryTimer = expiryIntervalMs === null ? null : setInterval(() => {
    // A failed database operation leaves the persisted lease for a later tick/restart.
    void deliverExpiries().catch(() => {});
  }, expiryIntervalMs);
  expiryTimer?.unref();
  async function notify(device, command, kind) {
    if (!device.pushToken) return { status: 'phone_registration_required' };
    try { return await push({ token: device.pushToken, commandId: command.id, expiresAt: command.expiresAt, kind }); }
    catch { return { status: 'push_failed' }; }
  }
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
          const next = parsed.data;
          const current = db.prepare('SELECT snapshot FROM devices WHERE id = ?').get(deviceId);
          const previous = JSON.parse(current.snapshot ?? 'null');
          // A background process may confirm the same selection without access to
          // identities. Preserve only a matching random selection marker, never counts alone.
          if (next.selectedAppIDs === undefined && next.selectionIdentity &&
            next.selectionIdentity === previous?.selectionIdentity &&
            next.selectionSummary?.applications === previous?.selectionSummary?.applications &&
            previous.selectedAppIDs) {
            next.selectedAppIDs = previous.selectedAppIDs;
          }
          db.prepare('UPDATE devices SET snapshot = ?, observedAt = ? WHERE id = ?')
            .run(JSON.stringify(next), now(), deviceId);
          return send(200, { accepted: true });
        }
        if (req.method === 'GET' && path === '/v1/device/commands') {
          const rows = db.prepare("SELECT command FROM commands WHERE deviceId = ? AND status = 'pending' ORDER BY json_extract(command, '$.sequence')").all(deviceId);
          return send(200, { commands: rows.map(row => JSON.parse(row.command)) });
        }
        const receiptRoute = path.match(/^\/v1\/device\/commands\/([^/]+)$/);
        if (req.method === 'GET' && receiptRoute) {
          const row = db.prepare('SELECT * FROM commands WHERE deviceId = ? AND id = ?')
            .get(deviceId, decodeURIComponent(receiptRoute[1]));
          if (!row) fail(404, 'unknown_command');
          return send(200, { command: JSON.parse(row.command), status: row.status, reason: row.reason });
        }
        if (req.method === 'POST' && path === '/v1/device/receipts') {
          const parsed = receiptSchema.safeParse(await readBody(req));
          if (!parsed.success) fail(400, 'invalid_receipt');
          const receipt = parsed.data;
          const row = db.prepare('SELECT * FROM commands WHERE deviceId = ? AND id = ?').get(deviceId, receipt.id);
          if (!row) fail(404, 'unknown_command');
          if (['applied', 'rejected'].includes(row.status) &&
            (row.status !== receipt.status || row.reason !== (receipt.reason ?? null))) fail(409, 'receipt_conflict');
          db.exec('BEGIN IMMEDIATE');
          try {
            db.prepare('UPDATE commands SET status = ?, reason = ? WHERE deviceId = ? AND id = ?')
              .run(receipt.status, receipt.reason ?? null, deviceId, receipt.id);
            const command = JSON.parse(row.command);
            if (receipt.status === 'applied' && command.action === 'start') {
              const dueAt = command.issuedAt + command.durationMinutes * 60000;
              // Receipts may arrive out of order after offline recovery. A later
              // applied stop still ends this owner when its start receipt arrives last.
              const stopped = db.prepare("SELECT 1 FROM commands WHERE deviceId = ? AND status = 'applied' AND json_extract(command, '$.action') = 'stop' AND json_extract(command, '$.sessionID') = ? AND json_extract(command, '$.sequence') > ? LIMIT 1")
                .get(deviceId, command.sessionID, command.sequence);
              db.prepare('INSERT OR IGNORE INTO expiryJobs (deviceId, commandId, sessionId, dueAt, nextAttemptAt, status) VALUES (?, ?, ?, ?, ?, ?)')
                .run(deviceId, command.id, command.sessionID, dueAt, dueAt, stopped ? 'canceled' : 'pending');
            } else if (receipt.status === 'applied' && command.action === 'stop') {
              db.prepare("UPDATE expiryJobs SET status = 'canceled' WHERE deviceId = ? AND sessionId = ? AND status = 'pending' AND EXISTS (SELECT 1 FROM commands AS start WHERE start.deviceId = expiryJobs.deviceId AND start.id = expiryJobs.commandId AND json_extract(start.command, '$.sequence') < ?)")
                .run(deviceId, command.sessionID, command.sequence);
            }
            db.exec('COMMIT');
          } catch (error) {
            if (db.isTransaction) db.exec('ROLLBACK');
            throw error;
          }
          return send(200, { accepted: true });
        }
        fail(404, 'not_found');
      }
      if (!isAgent) fail(401, 'unauthorized');
      if (req.method === 'GET' && path === '/v1/devices') {
        const devices = db.prepare('SELECT id, observedAt FROM devices ORDER BY id').all()
          .map(row => ({ deviceId: row.id, observedAt: row.observedAt ?? null }));
        return send(200, { devices });
      }
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
          let command;
          db.exec('BEGIN IMMEDIATE');
          try {
            const existing = db.prepare('SELECT * FROM commands WHERE deviceId = ? AND id = ?').get(target.id, request.id);
            if (existing) {
              if (existing.request !== JSON.stringify(request)) fail(409, 'command_id_conflict');
              db.exec('COMMIT');
              return send(existing.status === 'pending' ? 202 : 200,
                { command: JSON.parse(existing.command), status: existing.status, reason: existing.reason });
            }
            const allocated = db.prepare('UPDATE devices SET sequence = sequence + 1 WHERE id = ? RETURNING sequence').get(target.id);
            command = { ...request, sequence: allocated.sequence, issuedAt: now(), expiresAt: now() + 120000 };
            db.prepare('INSERT INTO commands (deviceId, id, command, request, status, reason) VALUES (?, ?, ?, ?, ?, ?)')
              .run(target.id, request.id, JSON.stringify(command), JSON.stringify(request), 'pending', null);
            db.exec('COMMIT');
          } catch (error) {
            if (db.isTransaction) db.exec('ROLLBACK');
            throw error;
          }
          const delivery = await notify(target, command, 'alert');
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
  return { server, close() {
    if (closed) return;
    closed = true;
    if (expiryTimer) clearInterval(expiryTimer);
    db.close();
  } };
}
