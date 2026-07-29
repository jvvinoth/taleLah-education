// Locale registry. Each locale ships full native marketing copy plus a
// fully-localised phone mockup (SiteContent type enforces completeness).
import type { Locale, SiteContent } from './types';
import { en } from './en';
import { ta } from './ta';
import { zh } from './zh';
import { ms } from './ms';

export const CONTENT: Record<Locale, SiteContent> = { en, ta, zh, ms };

export const LOCALES: { code: Locale; label: string; cls: string; htmlLang: string }[] = [
  { code: 'en', label: 'EN', cls: 'en', htmlLang: 'en-SG' },
  { code: 'ta', label: 'தமிழ்', cls: 'ta', htmlLang: 'ta-SG' },
  { code: 'zh', label: '中文', cls: 'zh', htmlLang: 'zh-SG' },
  { code: 'ms', label: 'Melayu', cls: 'ms', htmlLang: 'ms-SG' },
];

/** Root-relative path for a locale's home page. */
export function localePath(code: Locale): string {
  return code === 'en' ? '/' : `/${code}/`;
}

export type { Locale, SiteContent } from './types';
