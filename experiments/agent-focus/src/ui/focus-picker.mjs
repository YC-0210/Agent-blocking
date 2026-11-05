import { App } from '@modelcontextprotocol/ext-apps';

const app = new App({ name: 'DO Card focus timeline', version: '0.2.0' }, {}, { autoResize: true });
const el = id => document.getElementById(id);
let selection, minutes, editRevision, dirty = false, working = false, timer, saving, expiryTimer, lastContext;
const terminal = new Set(['applied', 'rejected', 'expired']);
const submitted = () => selection && selection.phase !== 'draft';
const valid = () => Number.isInteger(minutes) && minutes >= selection.minMinutes && minutes <= selection.maxMinutes;
const clock = (at, zone) => new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', timeZone: zone }).format(at);
function failure(error) {
  el('error').textContent = error instanceof Error ? error.message : String(error);
  el('error').hidden = false;
}
function accept(result) {
  if (result.isError) throw new Error(result.content?.find(part => part.type === 'text')?.text ?? 'Could not update this selection.');
  const next = result.structuredContent?.selection;
  if (!next || (selection && selection.id !== next.id)) return;
  selection = next;
  if (!dirty) { minutes = next.minutes; editRevision = next.revision; }
  render();
  const context = JSON.stringify({ selectionId: next.id, kind: next.kind, minutes: next.minutes,
    commandStatus: next.phase, requestId: next.requestId });
  if (context !== lastContext) {
    lastContext = context;
    // Model context is supplementary; a host that does not support it must not make a successful command look failed.
    app.updateModelContext({ content: [{ type: 'text', text: context }] }).catch(() => {});
  }
  if (terminal.has(next.phase)) clearInterval(timer);
  if (next.phase === 'applied' && next.kind === 'session' && next.command?.issuedAt) {
    clearTimeout(expiryTimer);
    const remaining = next.command.issuedAt + next.minutes * 60000 - Date.now();
    if (remaining > 0) expiryTimer = setTimeout(render, remaining + 50);
  }
}
async function call(name, args) {
  const result = await app.callServerTool({ name, arguments: args });
  accept(result);
  return result;
}
function render() {
  if (!selection) return;
  const maximum = selection.kind === 'maximum';
  const blocked = working || Boolean(saving) || submitted();
  const safeMinutes = Number.isFinite(minutes) ? minutes : selection.minMinutes;
  const axisMax = maximum ? Math.max(180, Math.min(1440, Math.ceil(safeMinutes / 60) * 60)) : selection.maxMinutes;
  el('picker').hidden = false;
  document.querySelector('main').setAttribute('aria-busy', String(working));
  el('kind').textContent = maximum ? 'Maximum lock time' : 'Session duration';
  el('context').textContent = maximum ? 'Agent settings' : selection.issue || 'Your next focus session';
  el('title').textContent = maximum ? 'A clear limit for your focus.' : 'Make room for your next step.';
  el('description').textContent = maximum
    ? 'Choose the maximum duration this agent may request for future sessions. Review the change, then save it here.'
    : 'Your agent suggested a focus window. Drag its end or type a duration that works for you, then approve the start.';
  el('minutes').min = selection.minMinutes;
  el('minutes').max = selection.maxMinutes;
  el('minutes').value = Number.isFinite(minutes) ? String(minutes) : '';
  el('minutes').disabled = blocked;
  el('minutes').setAttribute('aria-label', maximum ? 'Maximum lock time in minutes' : 'Session duration in minutes');
  const range = el('timeline');
  range.min = selection.minMinutes; range.max = axisMax; range.step = '1'; range.value = safeMinutes;
  range.disabled = blocked;
  range.setAttribute('aria-label', maximum ? 'Drag maximum lock time' : 'Drag session duration');
  range.setAttribute('aria-valuetext', `${minutes} minutes`);
  el('fill').style.width = `${Math.max(0, Math.min(100, (safeMinutes - selection.minMinutes) / (axisMax - selection.minMinutes) * 100))}%`;
  el('track-label').replaceChildren();
  el('track-label').append(document.createTextNode(maximum ? 'Maximum per session' : selection.issue || 'Focus session'));
  const detail = document.createElement('small'); detail.textContent = maximum ? 'Future sessions from this agent' : 'Selected distractions paused';
  el('track-label').append(detail);
  el('ticks').replaceChildren();
  for (const value of [selection.minMinutes, Math.round(axisMax / 3), Math.round(axisMax * 2 / 3), axisMax]) {
    const span = document.createElement('span'); span.textContent = `${value}m`; el('ticks').append(span);
  }
  const endAt = selection.command?.issuedAt ? selection.command.issuedAt + minutes * 60000 : Date.now() + minutes * 60000;
  const formattedEnd = Number.isFinite(endAt) ? clock(endAt, selection.timeZone) : '—';
  const windowEnded = selection.phase === 'applied' && !maximum && Date.now() >= endAt;
  el('end').replaceChildren();
  el('end').append(document.createTextNode(maximum ? `${selection.currentMaximumMinutes}m → ${minutes}m` : valid() ? `End at ${formattedEnd}` : 'Choose a valid duration'));
  const timezone = document.createElement('span'); timezone.textContent = maximum ? selection.phase === 'applied' ? 'Previous → saved maximum' : 'Current → proposed maximum' : selection.timeZone;
  el('end').append(timezone);
  el('presets').replaceChildren();
  for (const value of (maximum ? [30, 45, 60, 90, 120] : [15, 30, 45, 60]).filter(n => n >= selection.minMinutes && n <= selection.maxMinutes)) {
    const button = document.createElement('button'); button.textContent = `${value} min`; button.disabled = blocked;
    button.setAttribute('aria-pressed', String(minutes === value));
    button.onclick = () => { edit(value); flush().catch(failure); }; el('presets').append(button);
  }
  el('summary').replaceChildren();
  const summaryLabel = document.createElement('span'); summaryLabel.textContent = maximum ? 'Applies to future sessions' : 'Saved maximum';
  const summaryValue = document.createElement('strong'); summaryValue.textContent = maximum ? 'This agent only' : `${selection.currentMaximumMinutes} minutes`;
  el('summary').append(summaryLabel, summaryValue);
  el('note').textContent = maximum
    ? 'Saving changes only the maximum. It does not start a block or change a session already running.'
    : 'The phone enforces your saved maximum and allowed hours. It unlocks automatically when this session expires.';
  const confirm = el('confirm');
  confirm.textContent = working ? 'Sending…' : selection.phase === 'unknown' ? 'Retry the same request' : submitted()
    ? selection.phase === 'applied' ? maximum ? 'Maximum saved' : windowEnded ? 'Session window ended' : 'Blocking active' : selection.phase === 'pending' ? 'Waiting for phone…' : 'Request ended'
    : !valid() ? 'Choose a valid duration' : maximum ? `Save ${minutes}-minute maximum ↗` : `Start ${minutes}-minute focus ↗`;
  confirm.disabled = working || Boolean(saving) || !valid() || (submitted() && selection.phase !== 'unknown') ||
    (!submitted() && maximum && minutes === selection.currentMaximumMinutes);
  const messages = {
    pending: 'Request sent. Waiting for the phone to acknowledge it. Pending does not mean applied.',
    unknown: 'Delivery status is unknown. Retry uses the same request; it will not create a second command.',
    applied: maximum ? `The phone confirmed the ${selection.minutes}-minute maximum is saved. Existing sessions are unchanged.` : windowEnded ? 'The scheduled end has passed. Check the phone or ask your agent for current status; this receipt confirms the earlier start.' : `The phone confirmed blocking was applied. Scheduled end: ${formattedEnd}.`,
    rejected: `The phone rejected this request (${selection.reason ?? 'unknown reason'}). Ask your agent to open a new picker.`,
    expired: 'The command expired before phone acknowledgement. Ask your agent for a new picker.',
  };
  el('status').hidden = !messages[selection.phase]; el('status').textContent = messages[selection.phase] ?? '';
  el('observed').textContent = `Phone settings last observed ${selection.observedAt ? clock(selection.observedAt, selection.timeZone) : 'at an unknown time'} · ${selection.timeZone}. Open DO Card to sync if these look outdated.`;
  if (!valid()) failure(`Choose ${selection.minMinutes}–${selection.maxMinutes} minutes. A maximum change is a separate tool.`);
}
function edit(value) {
  if (submitted() || working || saving) return;
  if (!dirty) editRevision = selection.revision;
  dirty = true; minutes = value === '' ? NaN : Number(value); el('error').hidden = true;
  // Keep the same range element while dragging; replacing it loses pointer capture.
  render();
}
async function saveDraft() {
  if (!dirty || !valid()) return;
  const target = minutes;
  const result = await app.callServerTool({ name: 'revise_focus_selection', arguments: {
    selectionId: selection.id, minutes: target, expectedRevision: editRevision,
  } });
  if (result.isError) {
    dirty = false;
    await call('focus_selection_status', { selectionId: selection.id });
    throw new Error(result.content?.[0]?.text ?? 'The proposal changed. Review it again.');
  }
  dirty = false; accept(result);
}
function flush() {
  if (saving) return saving;
  if (!dirty || !valid()) return Promise.resolve();
  saving = saveDraft().finally(() => { saving = undefined; render(); });
  render();
  return saving;
}
el('timeline').oninput = event => edit(event.target.value);
el('timeline').onchange = () => flush().catch(failure);
el('minutes').oninput = event => edit(event.target.value);
el('minutes').onchange = () => flush().catch(failure);
el('confirm').onclick = async () => {
  if (working || !selection || !valid()) return;
  try {
    working = true; el('error').hidden = true; render();
    await flush();
    await call('confirm_focus_selection', { selectionId: selection.id, revision: selection.revision, userConfirmed: true });
  } catch (error) { failure(error); }
  finally { working = false; render(); }
};
app.ontoolresult = result => { try { accept(result); } catch (error) { failure(error); } };
app.onteardown = async () => { clearInterval(timer); clearTimeout(expiryTimer); return {}; };
app.connect().then(() => {
  timer = setInterval(async () => {
    if (!selection || working || saving || dirty || terminal.has(selection.phase)) return;
    try { await call('focus_selection_status', { selectionId: selection.id }); } catch (error) { failure(error); }
  }, 3000);
}).catch(() => failure('Open this timeline from your agent’s focus selection tool in an MCP Apps-compatible client.'));
