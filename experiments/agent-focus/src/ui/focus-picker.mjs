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
    commandStatus: next.phase, requestId: next.requestId, appGroupID: next.appGroupID });
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
  const axisMax = selection.maxMinutes;
  el('picker').hidden = false;
  el('groups').hidden = maximum;
  if (!maximum) {
    const groups = selection.appGroups ?? [];
    const select = el('app-group');
    select.replaceChildren(...groups.map(group => {
      const option = document.createElement('option');
      option.value = group.id; option.textContent = group.name;
      return option;
    }));
    if (!groups.length) {
      const option = document.createElement('option'); option.textContent = 'Saved apps — review on iPhone'; select.append(option);
    }
    if (groups.length) select.value = selection.appGroupID ?? groups[0].id;
    else select.selectedIndex = 0;
    select.disabled = blocked || !groups.length;
    el('refresh-groups').disabled = blocked;
    el('review-apps').disabled = working || Boolean(saving);
    el('review-url').textContent = selection.reviewURL ?? '';
  }
  document.querySelector('main').setAttribute('aria-busy', String(working));
  el('minutes').min = selection.minMinutes;
  el('minutes').max = selection.maxMinutes;
  el('minutes').value = Number.isFinite(minutes) ? String(minutes) : '';
  el('minutes').disabled = blocked;
  el('minutes').setAttribute('aria-label', maximum ? 'Maximum lock time in minutes' : 'Session duration in minutes');
  const range = el('timeline');
  range.min = selection.minMinutes; range.max = axisMax; range.step = '1'; range.value = safeMinutes;
  range.disabled = blocked;
  range.setAttribute('aria-label', maximum ? 'Drag maximum lock time' : 'Drag session duration');
  range.setAttribute('aria-valuetext', Number.isFinite(minutes) ? `${minutes} minutes` : 'Choose a duration');
  el('fill').style.width = `${Math.max(0, Math.min(100, (safeMinutes - selection.minMinutes) / (axisMax - selection.minMinutes) * 100))}%`;
  const endAt = selection.command?.issuedAt ? selection.command.issuedAt + minutes * 60000 : Date.now() + minutes * 60000;
  const formattedEnd = Number.isFinite(endAt) ? clock(endAt, selection.timeZone) : '—';
  const windowEnded = selection.phase === 'applied' && !maximum && Date.now() >= endAt;
  const confirm = el('confirm');
  confirm.textContent = working ? 'Sending…' : selection.phase === 'unknown' ? 'Retry the same request' : submitted()
    ? selection.phase === 'applied' ? maximum ? 'Maximum saved' : windowEnded ? 'Session window ended' : 'Blocking active' : selection.phase === 'pending' ? 'Waiting for phone…' : 'Request ended'
    : !valid() ? 'Choose a valid duration' : maximum ? 'Save maximum' : 'Start focus';
  confirm.disabled = working || Boolean(saving) || !valid() || (submitted() && selection.phase !== 'unknown') ||
    (!submitted() && maximum && minutes === selection.currentMaximumMinutes);
  const messages = {
    pending: 'Request sent. Waiting for the phone to acknowledge it. Pending does not mean applied.',
    unknown: 'Delivery status is unknown. Retry uses the same request; it will not create a second command.',
    applied: maximum ? `The phone confirmed the ${selection.minutes}-minute maximum is saved. Existing sessions are unchanged.` : windowEnded ? 'The scheduled end has passed. Check the phone or ask your agent for current status; this receipt confirms the earlier start.' : `The phone confirmed blocking was applied. Scheduled end: ${formattedEnd}.`,
    rejected: selection.reason === 'mode_not_approved'
      ? 'Your phone’s approved settings changed since this picker opened. Nothing was changed. Ask your agent for a fresh picker.'
      : `The phone rejected this request (${selection.reason ?? 'unknown reason'}). Ask your agent to open a new picker.`,
    expired: 'The command expired before phone acknowledgement. Ask your agent for a new picker.',
  };
  el('status').hidden = !messages[selection.phase]; el('status').textContent = messages[selection.phase] ?? '';

  if (!valid()) failure(maximum ? `Choose ${selection.minMinutes}–${selection.maxMinutes} minutes for your maximum.` : `Choose ${selection.minMinutes}–${selection.maxMinutes} minutes. To change your maximum, ask your agent separately.`);
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
el('app-group').onchange = async event => {
  const appGroupID = event.target.value;
  if (!selection || submitted() || working || saving) return;
  try {
    working = true; el('error').hidden = true; render();
    await flush();
    await call('revise_focus_selection', { selectionId: selection.id, appGroupID, expectedRevision: selection.revision });
  } catch (error) {
    try { await call('focus_selection_status', { selectionId: selection.id }); } catch {}
    failure(error);
  } finally { working = false; render(); }
};
el('refresh-groups').onclick = async () => {
  if (!selection || submitted() || working || saving) return;
  try {
    working = true; el('error').hidden = true; render();
    await flush();
    await call('refresh_focus_app_groups', { selectionId: selection.id });
  } catch (error) { failure(error); }
  finally { working = false; render(); }
};
el('review-apps').onclick = async () => {
  try {
    if (!selection?.reviewURL) return;
    const result = await app.openLink({ url: selection.reviewURL });
    if (result.isError) throw new Error('link_denied');
  } catch {
    failure('This chat host could not open the iPhone link. Open DO Card on your paired iPhone and tap Review app groups.');
  }
};
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
