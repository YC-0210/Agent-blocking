// Exact bundle IDs only. No fuzzy name matching or requests to external icon services.
const apps = new Map([
  ['com.burbn.instagram', { name: 'Instagram', iconKey: 'instagram' }],
  ['com.supercell.laser', { name: 'Brawl Stars', iconKey: 'brawl-stars' }],
]);
export const selectedApps = ids => (ids ?? []).map(id => ({ id, ...(apps.get(id) ?? { name: id }) }));
