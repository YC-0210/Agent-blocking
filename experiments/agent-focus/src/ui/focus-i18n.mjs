// Product copy only. Protocol names, receipts and approval semantics stay language-neutral.
const traditional = {
  'Change selected apps': '變更選取的 App', 'Choose apps on iPhone': '請在 iPhone 選擇 App',
  '1 selected app': '已選取 1 個 App', '{count} selected apps': '已選取 {count} 個 App',
  '1 selected category': '已選取 1 個類別', '{count} selected categories': '已選取 {count} 個類別',
  '1 selected website': '已選取 1 個網站', '{count} selected websites': '已選取 {count} 個網站',
  'Open DO Card on your paired iPhone and choose apps. This chat will update after saving.': '請在已配對的 iPhone 開啟 DO Card 並選擇 App。儲存後，聊天室會自動更新。',
  'Choose an app': '選擇 App', 'Choose an app on iPhone': '請在 iPhone 設定 App',
  'Refresh apps': '重新整理 App',
  'Open this address on your paired iPhone. If your chat app cannot open it, open DO Card and tap Manage apps.': '請在已配對的 iPhone 開啟此連結。若聊天工具無法開啟，請在 DO Card 點選「管理 App」。',
  'This chat host could not open the iPhone link. Open DO Card on your paired iPhone and tap Manage apps.': '聊天工具無法開啟 iPhone 連結。請在已配對的 iPhone 開啟 DO Card，點選「管理 App」。',
  'Apps for this session': '本次專注的 App', 'App group': 'App 群組',
  'Choose a group saved on your iPhone. Actual app names and icons stay on the phone.': '選擇儲存在 iPhone 上的群組。實際 App 名稱與圖示只會顯示在手機上。',
  'Review / change on iPhone': '在 iPhone 檢視或變更', 'Refresh groups': '重新整理群組',
  'Open from another device': '從其他裝置開啟',
  'Open this address on your paired iPhone. If your chat app cannot open it, open DO Card and tap Review app groups.': '請在已配對的 iPhone 開啟此連結。如果聊天工具無法開啟，請開啟 DO Card，點選「檢視 App 群組」。',
  'Saved apps — review on iPhone': '已儲存的 App — 請在 iPhone 檢視',
  'This chat host could not open the iPhone link. Open DO Card on your paired iPhone and tap Review app groups.': '聊天工具無法開啟 iPhone 連結。請在已配對的 iPhone 開啟 DO Card，點選「檢視 App 群組」。',
  'The selected app changed. Refresh apps and review your choice.': 'App 已變更。請重新整理 App，並確認你的選擇。',
  'DO · Focus timeline': 'DO · 專注時間設定',
  'minutes': '分鐘', 'Confirm': '確認',
  'Duration in minutes': '時間（分鐘）', 'Drag to choose duration': '拖曳以調整時間',
  'Maximum lock time in minutes': '每次專注時間上限（分鐘）',
  'Session duration in minutes': '本次專注時間（分鐘）',
  'Drag maximum lock time': '拖曳以調整每次專注時間上限',
  'Drag session duration': '拖曳以調整本次專注時間',
  '{minutes} minutes': '{minutes} 分鐘', 'Choose a duration': '請選擇時間',
  'Sending…': '正在傳送…', 'Retry the same request': '重試這次要求',
  'Maximum saved': '時間上限已更新', 'Session window ended': '已到預計結束時間',
  'Blocking active': '已開始專注', 'Waiting for phone…': '等待手機確認…',
  'Request ended': '本次要求已結束', 'Choose a valid duration': '請選擇有效的時間',
  'Save maximum': '儲存時間上限', 'Start focus': '開始專注',
  'Request sent. Waiting for the phone to acknowledge it. Pending does not mean applied.':
    '已傳送要求，等待手機確認。尚未確認設定是否生效。',
  'Delivery status is unknown. Retry uses the same request; it will not create a second command.':
    '目前無法確認傳送結果。重試會使用同一項要求，不會重複建立。',
  'The phone confirmed the {minutes}-minute maximum is saved. Existing sessions are unchanged.':
    '手機已確認儲存 {minutes} 分鐘的時間上限，不影響正在進行的專注。',
  'The scheduled end has passed. Check the phone or ask your agent for current status; this receipt confirms the earlier start.':
    '已到預計結束時間。請查看手機，或請 AI 助理確認目前狀態；先前的確認僅代表專注曾成功開始。',
  'The phone confirmed blocking was applied. Scheduled end: {end}.':
    '手機已確認套用 App 使用限制，預計於 {end} 結束。',
  'Your phone’s approved settings changed since this picker opened. Nothing was changed. Ask your agent for a fresh picker.':
    '手機上的設定已變更，這次要求未套用。請讓 AI 助理重新開啟時間選擇器。',
  'The phone rejected this request. {reason} Ask your agent to open a new picker.':
    '手機未接受這次要求。{reason}請讓 AI 助理重新開啟時間選擇器。',
  'The command expired before phone acknowledgement. Ask your agent for a new picker.':
    '要求已逾時，未收到手機確認。請讓 AI 助理重新開啟時間選擇器。',
  'Choose {min}–{max} minutes for your maximum.': '時間上限須介於 {min} 至 {max} 分鐘。',
  'Choose {min}–{max} minutes. To change your maximum, ask your agent separately.':
    '請選擇 {min} 至 {max} 分鐘。如需變更時間上限，請另外告訴 AI 助理。',
  'Open this timeline from your agent’s focus selection tool in an MCP Apps-compatible client.':
    '請從支援 MCP Apps 的聊天工具，讓 AI 助理開啟時間選擇器。',
  'Open a new picker with your agent.': '請讓 AI 助理重新開啟時間選擇器。',
  'This selection expired. Ask your agent for a new picker.': '此設定已過期，請讓 AI 助理重新開啟。',
  'This proposal changed. Review the latest value before confirming.': '設定已更新，請確認最新的時間後再送出。',
  'This request was already submitted. Its duration cannot be changed.': '這次要求已送出，無法再修改時間。',
  'Open DO Card to sync its approved settings.': '請開啟 DO Card，同步你已確認的設定。',
  'A session is already active. Check its status with your agent.': '目前已有專注進行中，請讓 AI 助理確認狀態。',
  'Close an old picker and ask your agent to open a new one.': '請先關閉不再使用的時間選擇器，再讓 AI 助理重新開啟。',
  'Unable to confirm the result. Refresh or try again later.': '無法確認這次操作的結果。請重新整理，或稍後再試。',
  'The duration exceeds your approved maximum.': '時間超過你設定的上限。',
  'The session falls outside your approved hours.': '專注時間超出你允許的時段。',
  'A new confirmation is required before starting again.': '再次開始前，需要你重新確認。',
  'The request is no longer valid.': '這次要求已失效。',
  'The phone could not apply the settings.': '手機無法套用設定。',
  'The phone settings changed.': '手機上的設定已變更。',
  'Please check the session and try again.': '請確認目前的專注狀態後再試一次。',
};

export function resolveLocale(preferred, fallbacks = []) {
  for (const locale of [preferred, ...fallbacks]) {
    if (typeof locale !== 'string') continue;
    const normalized = locale.toLowerCase().replaceAll('_', '-');
    if (/^zh(?:-|$)/.test(normalized) && !/(?:hans|(?:^|-)cn(?:-|$)|(?:^|-)sg(?:-|$))/.test(normalized)) return 'zh-Hant';
    if (/^en(?:-|$)/.test(normalized)) return 'en';
  }
  return 'en';
}
export function translate(locale, message, values = {}) {
  const template = locale === 'zh-Hant' ? traditional[message] ?? message : message;
  return template.replace(/\{(\w+)\}/g, (match, key) => Object.hasOwn(values, key) ? String(values[key]) : match);
}
export function errorMessage(error) {
  const raw = error instanceof Error ? error.message : String(error);
  const code = raw.match(/\b(selection_missing|selection_expired|selection_changed|policy_changed|selection_already_submitted|phone_setup_required|session_active|duration_exceeds_approval|app_group_not_approved|too_many_open_pickers)\b/)?.[1];
  return ({
    selection_missing: 'Open a new picker with your agent.',
    selection_expired: 'This selection expired. Ask your agent for a new picker.',
    selection_changed: 'This proposal changed. Review the latest value before confirming.',
    policy_changed: 'The phone settings changed.',
    selection_already_submitted: 'This request was already submitted. Its duration cannot be changed.',
    phone_setup_required: 'Open DO Card to sync its approved settings.',
    session_active: 'A session is already active. Check its status with your agent.',
    app_group_not_approved: 'The selected app changed. Refresh apps and review your choice.',
    duration_exceeds_approval: 'The duration exceeds your approved maximum.',
    too_many_open_pickers: 'Close an old picker and ask your agent to open a new one.',
  })[code] ?? 'Unable to confirm the result. Refresh or try again later.';
}
export function rejectionMessage(reason) {
  return ({
    app_group_not_approved: 'The selected app changed. Refresh apps and review your choice.',
    duration_exceeds_approval: 'The duration exceeds your approved maximum.',
    outside_approved_hours: 'The session falls outside your approved hours.',
    renewal_approval_required: 'A new confirmation is required before starting again.',
    session_already_active: 'A session is already active. Check its status with your agent.',
    expired_before_application: 'The request is no longer valid.',
    expired_or_future_command: 'The request is no longer valid.',
    issued_before_emergency: 'The request is no longer valid.',
    stale_command: 'The request is no longer valid.',
    execution_failed: 'The phone could not apply the settings.',
    policy_changed: 'The phone settings changed.',
  })[reason] ?? 'Please check the session and try again.';
}
