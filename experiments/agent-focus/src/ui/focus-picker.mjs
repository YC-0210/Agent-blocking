import { appIcon } from './app-icons.mjs';
import { resolveLocale, translate, errorMessage, rejectionMessage } from './focus-i18n.mjs';
import { App } from '@modelcontextprotocol/ext-apps';

const app = new App({ name: 'DO Card focus timeline', version: '0.2.0' }, {}, { autoResize: true });
const el = id => document.getElementById(id);
let locale = resolveLocale(undefined, navigator.languages ?? [navigator.language]);
let lastFailure;
const t = (message, values) => translate(locale, message, values);
function localize() {
  document.documentElement.lang = locale;
  document.title = t('DO · Focus timeline');
  document.querySelector('label[for=minutes]').textContent = t('minutes');
  el('minutes').setAttribute('aria-label', t('Duration in minutes'));
  el('timeline').setAttribute('aria-label', t('Drag to choose duration'));
  el('confirm').textContent = t('Confirm');
  el('groups').setAttribute('aria-label', t('Apps for this session'));
  el('app-options').setAttribute('aria-label', t('Choose an app'));
  for (const [id, copy] of Object.entries({
    'app-empty': 'Choose an app on iPhone',
    'review-apps': 'Review / change on iPhone', 'refresh-groups': 'Refresh apps',
    'review-summary': 'Open from another device',
    'review-help': 'Open this address on your paired iPhone. If your chat app cannot open it, open DO Card and tap Manage apps.',
  })) el(id).textContent = t(copy);
  render();
  if (lastFailure && !el('error').hidden) failure(lastFailure);
}
let appRenderKey;
let selection, minutes, editRevision, dirty = false, working = false, timer, saving, expiryTimer, lastContext;
const terminal = new Set(['applied', 'rejected', 'expired']);
const submitted = () => selection && selection.phase !== 'draft';
const valid = () => Number.isInteger(minutes) && minutes >= selection.minMinutes && minutes <= selection.maxMinutes;
const clock = (at, zone) => new Intl.DateTimeFormat(locale, { hour: '2-digit', minute: '2-digit', timeZone: zone }).format(at);
function failure(error) {
  if (error?.copy) {
    lastFailure = error;
    el('error').textContent = t(error.copy, error.values);
    el('error').hidden = false;
    return;
  }
  lastFailure = error;
  el('error').textContent = t(errorMessage(error));
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
  el('app-management').hidden = maximum;
  const identities = (selection.appGroups ?? []).filter(app => ['instagram', 'tiktok', 'youtube', 'facebook', 'reddit', 'x', 'other'].includes(app.iconKey));
  const chosenApp = identities.find(app => app.id === selection.appGroupID);
  if (!maximum) {
    const nextAppKey = JSON.stringify([selection.id, identities, selection.appGroupID, blocked]);
    if (nextAppKey !== appRenderKey) {
    appRenderKey = nextAppKey;
    el('app-options').replaceChildren(...identities.map(app => {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'app-chip'; button.disabled = blocked;
      button.setAttribute('aria-pressed', String(app.id === selection.appGroupID));
      const icon = document.createElement('span'); icon.className = `app-icon ${app.iconKey}`;
      icon.setAttribute('aria-hidden', 'true'); icon.innerHTML = appIcon(app.iconKey);
      const name = document.createElement('span'); name.textContent = app.name;
      button.append(icon, name); button.onclick = () => chooseApp(app.id);
      return button;
    }));
    }
    el('app-empty').hidden = Boolean(chosenApp);
    el('refresh-groups').disabled = blocked;
    el('review-apps').disabled = working || Boolean(saving);
    el('review-url').textContent = selection.reviewURL ?? '';
  }
  document.querySelector('main').setAttribute('aria-busy', String(working));
  el('minutes').min = selection.minMinutes;
  el('minutes').max = selection.maxMinutes;
  el('minutes').value = Number.isFinite(minutes) ? String(minutes) : '';
  el('minutes').disabled = blocked;
  el('minutes').setAttribute('aria-label', maximum ? t('Maximum lock time in minutes') : t('Session duration in minutes'));
  const range = el('timeline');
  range.min = selection.minMinutes; range.max = axisMax; range.step = '1'; range.value = safeMinutes;
  range.disabled = blocked;
  range.setAttribute('aria-label', maximum ? t('Drag maximum lock time') : t('Drag session duration'));
  range.setAttribute('aria-valuetext', Number.isFinite(minutes) ? t('{minutes} minutes', { minutes }) : t('Choose a duration'));
  el('fill').style.width = `${Math.max(0, Math.min(100, (safeMinutes - selection.minMinutes) / (axisMax - selection.minMinutes) * 100))}%`;
  const endAt = selection.command?.issuedAt ? selection.command.issuedAt + minutes * 60000 : Date.now() + minutes * 60000;
  const formattedEnd = Number.isFinite(endAt) ? clock(endAt, selection.timeZone) : '—';
  const windowEnded = selection.phase === 'applied' && !maximum && Date.now() >= endAt;
  const confirm = el('confirm');
  confirm.textContent = !maximum && !chosenApp && !submitted() ? t('Choose an app on iPhone') : working ? t('Sending…') : selection.phase === 'unknown' ? t('Retry the same request') : submitted()
    ? selection.phase === 'applied' ? maximum ? t('Maximum saved') : windowEnded ? t('Session window ended') : t('Blocking active') : selection.phase === 'pending' ? t('Waiting for phone…') : t('Request ended')
    : !valid() ? t('Choose a valid duration') : maximum ? t('Save maximum') : t('Start focus');
  confirm.disabled = (!maximum && !chosenApp) || working || Boolean(saving) || !valid() || (submitted() && selection.phase !== 'unknown') ||
    (!submitted() && maximum && minutes === selection.currentMaximumMinutes);
  const messages = {
    pending: t('Request sent. Waiting for the phone to acknowledge it. Pending does not mean applied.'),
    unknown: t('Delivery status is unknown. Retry uses the same request; it will not create a second command.'),
    applied: maximum ? t('The phone confirmed the {minutes}-minute maximum is saved. Existing sessions are unchanged.', { minutes: selection.minutes }) : windowEnded ? t('The scheduled end has passed. Check the phone or ask your agent for current status; this receipt confirms the earlier start.') : t('The phone confirmed blocking was applied. Scheduled end: {end}.', { end: formattedEnd }),
    rejected: selection.reason === 'mode_not_approved'
      ? t('Your phone’s approved settings changed since this picker opened. Nothing was changed. Ask your agent for a fresh picker.')
      : t('The phone rejected this request. {reason} Ask your agent to open a new picker.', { reason: t(rejectionMessage(selection.reason)) }),
    expired: t('The command expired before phone acknowledgement. Ask your agent for a new picker.'),
  };
  el('status').hidden = !messages[selection.phase]; el('status').textContent = messages[selection.phase] ?? '';

  if (!valid()) failure({ copy: maximum ? 'Choose {min}–{max} minutes for your maximum.' : 'Choose {min}–{max} minutes. To change your maximum, ask your agent separately.', values: { min: selection.minMinutes, max: selection.maxMinutes } });
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
async function chooseApp(appGroupID) {
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
    failure({ copy: 'This chat host could not open the iPhone link. Open DO Card on your paired iPhone and tap Manage apps.' });
  }
};
el('confirm').onclick = async () => {
  if (working || !selection || !valid() || el('confirm').disabled) return;
  try {
    working = true; el('error').hidden = true; render();
    await flush();
    await call('confirm_focus_selection', { selectionId: selection.id, revision: selection.revision, userConfirmed: true });
  } catch (error) { failure(error); }
  finally { working = false; render(); }
};
app.ontoolresult = result => { try { accept(result); } catch (error) { failure(error); } };
app.onteardown = async () => { clearInterval(timer); clearTimeout(expiryTimer); return {}; };
app.onhostcontextchanged = context => {
  if (context.locale) locale = resolveLocale(context.locale, navigator.languages ?? [navigator.language]);
  localize();
};
localize();
app.connect().then(() => {
  locale = resolveLocale(app.getHostContext()?.locale, navigator.languages ?? [navigator.language]);
  localize();
  timer = setInterval(async () => {
    if (!selection || working || saving || dirty || terminal.has(selection.phase)) return;
    try { await call('focus_selection_status', { selectionId: selection.id }); } catch (error) { failure(error); }
  }, 3000);
}).catch(() => failure({ copy: 'Open this timeline from your agent’s focus selection tool in an MCP Apps-compatible client.' }));
