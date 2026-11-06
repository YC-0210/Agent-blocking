import instagram from './icons/instagram.svg';
import tiktok from './icons/tiktok.svg';
import youtube from './icons/youtube.svg';
import facebook from './icons/facebook.svg';
import reddit from './icons/reddit.svg';
import x from './icons/x.svg';
const icons = { instagram, tiktok, youtube, facebook, reddit, x };
export function appIcon(key) {
  return Object.hasOwn(icons, key) ? icons[key] : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 3h7v7H3zm11 0h7v7h-7zM3 14h7v7H3zm11 0h7v7h-7z"/></svg>';
}
