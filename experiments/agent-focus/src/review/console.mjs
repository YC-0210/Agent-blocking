const element = id => document.getElementById(id);
const result = element('result');
const buttons = [...document.querySelectorAll('button')];

async function request(token, path, body) {
  const response = await fetch(path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`Relay request failed (${response.status}).`);
  return response.json();
}

async function phone(token) {
  const { devices } = await request(token, '/v1/devices');
  if (devices.length !== 1) throw new Error('Pair exactly one iPhone with this review credential.');
  const path = `/v1/devices/${encodeURIComponent(devices[0].deviceId)}`;
  const { snapshot } = await request(token, path);
  if (!snapshot) throw new Error('Open Agent Blocking and wait for the phone to sync.');
  return { path, snapshot };
}

function onClick(id, action) {
  element(id).addEventListener('click', async () => {
    const token = element('credential').value.trim();
    if (!/^agent_[a-f0-9]{64}$/.test(token)) {
      result.textContent = 'Enter a valid scoped review credential.';
      return;
    }
    buttons.forEach(button => { button.disabled = true; });
    result.textContent = 'Contacting relay…';
    try { await action(token); }
    catch (error) { result.textContent = error.message; }
    finally { buttons.forEach(button => { button.disabled = false; }); }
  });
}

onClick('pair', async token => {
  const { devices } = await request(token, '/v1/devices');
  if (devices.length) throw new Error('Disconnect the existing review phone before pairing again.');
  const { code } = await request(token, '/v1/pairings', {});
  element('code').textContent = `Relay: ${location.origin}\nCode: ${code}`;
  element('code').hidden = false;
  element('invitation').hidden = false;
  result.textContent = 'Pairing code expires in ten minutes.';
});

onClick('status', async token => {
  const { snapshot } = await phone(token);
  result.textContent = snapshot.sessionID
    ? `Session active until ${new Date(snapshot.endAt).toLocaleTimeString()}.`
    : 'Phone connected. No active session.';
});

async function command(token, action) {
  const { path, snapshot } = await phone(token);
  if (action === 'start' && snapshot.sessionID) throw new Error('A session is already active.');
  if (action === 'stop' && !snapshot.sessionID) throw new Error('No session is active.');
  const id = crypto.randomUUID();
  const start = action === 'start';
  const sessionID = start ? crypto.randomUUID() : snapshot.sessionID;
  await request(token, `${path}/commands`, {
    id, action, sessionID, modeID: snapshot.modeID,
    ...(start && { durationMinutes: 2, renewalConfirmed: true }),
  });
  result.textContent = 'Command queued. Waiting for the phone’s receipt…';
  for (let attempt = 0; attempt < 15; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const receipt = await request(token, `${path}/commands/${id}`);
    if (receipt.status !== 'pending') {
      result.textContent = receipt.status === 'applied'
        ? 'Phone confirmed the command.'
        : `Phone command ${receipt.status}. Check your approved hours and app settings.`;
      return;
    }
  }
  result.textContent = 'Still waiting for the phone. Check its connection and notification alerts.';
}

onClick('start', token => command(token, 'start'));
onClick('stop', token => command(token, 'stop'));
