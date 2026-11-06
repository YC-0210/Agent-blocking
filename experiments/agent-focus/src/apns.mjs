import { connect } from 'node:http2';
import { createHash, sign } from 'node:crypto';

export function createApnsPush({ privateKey, teamId, keyId, topic, sandbox = true,
  origin = sandbox ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com' }) {
  if (!privateKey || !teamId || !keyId || !topic) throw new Error('APNs key, team, key ID and topic are required');
  return async ({ token, commandId, expiresAt, kind, purpose }) => {
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyId })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })).toString('base64url');
    const signingInput = `${header}.${payload}`;
    const signature = sign('sha256', Buffer.from(signingInput), { key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    const aps = kind === 'background' ? { 'content-available': 1 } : {
      'mutable-content': 1, alert: { title: 'DO Card', body: purpose === 'expiry'
        ? 'Checking an expired focus session.' : 'A focus request is waiting. Open DO Card if it does not apply.',
        'loc-key': purpose === 'expiry' ? 'Checking an expired focus session.'
          : 'A focus request is waiting. Open DO Card if it does not apply.' }, sound: 'default',
    };
    return new Promise((resolve, reject) => {
      const connection = connect(origin);
      const timeout = setTimeout(() => { connection.destroy(); reject(new Error('apns_timeout')); }, 8000);
      const finish = (error, value) => {
        clearTimeout(timeout); connection.close();
        error ? reject(error) : resolve(value);
      };
      connection.on('error', error => finish(error));
      const request = connection.request({ ':method': 'POST', ':path': `/3/device/${token}`,
        authorization: `bearer ${signingInput}.${signature}`, 'apns-topic': topic,
        'apns-push-type': kind, 'apns-priority': kind === 'background' ? '5' : '10',
        'apns-expiration': String(Math.floor(expiresAt / 1000)),
        'apns-collapse-id': createHash('sha256').update(purpose === 'expiry' ? `expiry:${commandId}` : commandId).digest('hex'),
      });
      let status;
      request.on('response', headers => { status = headers[':status']; });
      request.on('data', () => {});
      request.on('error', error => finish(error));
      request.on('end', () => status === 200 ? finish(null, { status: 'accepted_by_apns' }) : finish(new Error(`apns_status_${status}`)));
      request.end(JSON.stringify({ aps, docardAgent: true, commandId,
        ...(purpose === 'expiry' ? { docardExpiry: true } : {}) }));
    });
  };
}
