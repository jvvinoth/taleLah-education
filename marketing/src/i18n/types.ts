// TaleLah marketing — single typed content contract.
// Every locale must satisfy SiteContent completely or the build fails,
// which is what makes the later ta/zh/ms copy drops safe.

export type Locale = 'en' | 'ta' | 'zh' | 'ms';

/** Which story language the in-phone mockups demonstrate. */
export type MockScript = 'ta' | 'zh' | 'ms';

/** Strings rendered inside the CSS phone mockups. */
export interface MockStrings {
  script: MockScript;
  childChip: string; // e.g. "Arjun · தமிழ்"
  hero: {
    line: string;
    rom: string;
    en: string;
    micBtn: string;
    stickerTop: string; // e.g. "✨ 5-min story"
    stickerBottom: string; // e.g. "🎙 She listens & replies"
  };
  capture: { chip: string; kick: string; note: string; btn: string };
  story: { chip: string; line: string; rom: string };
  mic: { chip: string; line: string; rom: string };
  handoff: { chip: string; kick: string; line: string; note: string };
}

export interface SiteContent {
  meta: { title: string; description: string };
  nav: { problem: string; how: string; languages: string; cta: string };
  hero: {
    eyebrow: string;
    titleA: string;
    titleB: string; // italic coral line
    lede: string;
    ctaPrimary: string;
    ctaSecondary: string;
    trust: [string, string, string];
  };
  problem: {
    eyebrow: string;
    title: string;
    statLabel: string;
    statValue: string;
    lede: string;
    source: string;
    /** Comparison chart: the shift is the story, not a single number. */
    statDelta?: string; // e.g. "+9.8 points in five years"
  };
  insight: { eyebrow: string; title: string; body: string };
  how: {
    eyebrow: string;
    title: string;
    lede: string;
    steps: { num: string; title: string; body: string }[];
  };
  screens: {
    eyebrow: string;
    title: string;
    lede: string;
    caps: [string, string, string, string];
    note: string;
  };
  difference: {
    eyebrow: string;
    title: string;
    head: [string, string, string];
    rows: { who: string; what: string; talelah: string }[];
  };
  trust: {
    eyebrow: string;
    title: string;
    cards: { icon: string; title: string; body: string }[];
  };
  languages: {
    eyebrow: string;
    title: string;
    items: { cls: MockScript; script: string; name: string; body: string }[];
    english: { badge: string; title: string; body: string };
    note: string;
  };
  builtWith: { eyebrow: string; title: string; lede: string };
  finalCta: {
    eyebrow: string;
    title: string;
    body: string;
    ctaPrimary: string;
    ctaSecondary: string;
  };
  footer: { tagline: string };
  mock: MockStrings;
}
