// English — master copy (approved preview text, verbatim).
import type { SiteContent } from './types';
import { mockTa } from './mocks';

export const en: SiteContent = {
  meta: {
    title: 'TaleLah — Everyday moments. Mother-tongue magic.',
    description:
      "TaleLah turns what your child did today into a five-minute Tamil, Chinese or Malay adventure — one that ends with your family talking, not a screen.",
  },
  nav: {
    problem: 'The problem',
    how: 'How it works',
    languages: 'Languages',
    cta: 'Try Now',
  },
  hero: {
    eyebrow: 'Singapore · for families of 4–8 year olds',
    titleA: 'Everyday moments.',
    titleB: 'Mother-tongue magic.',
    lede: 'TaleLah turns something your child really did today into a five-minute Tamil, Chinese or Malay adventure — one that ends with your family <b>talking</b>, not a screen.',
    ctaPrimary: 'Try Now →',
    ctaSecondary: 'See how it works',
    trust: ['Parent-approved', 'No screen-time guilt', 'Under 2 min to set up'],
  },
  problem: {
    eyebrow: 'The problem',
    title: 'Mother tongue is becoming a school subject — not a home language.',
    statLabel: 'Homes where English is spoken most often',
    statDelta: '+9.8 points in five years',
    statValue: '58',
    lede: "In 2020, English was the language most spoken at home by <b>48.3%</b> of residents. By 2025 that's <b>58.1%</b> — and higher among young children. Your child learns their mother tongue in school, but lives daily life in English.",
    source: 'Source: Singapore Dept. of Statistics · Census 2020 & General Household Survey 2025.',
  },
  insight: {
    eyebrow: "Why more apps won't fix it",
    title: 'School gives lessons. Only home gives use.',
    body: "More worksheets, more drills, more screen-time lessons — it's more of exactly what already isn't working. A language survives when a child has a real reason to <b>speak</b> it after school. TaleLah makes that reason.",
  },
  how: {
    eyebrow: 'The solution',
    title: 'One real moment. One five-minute adventure.<br>One family conversation.',
    lede: 'You capture what your child did today. TaleLah writes a tiny mother-tongue story around it, your child speaks their way through it, then it steps off the screen and into your home.',
    steps: [
      {
        num: 'STEP 01',
        title: 'Capture a moment',
        body: 'Snap a photo, record a voice note, or type a line — "Arjun built an MRT track from blocks." Under two minutes.',
      },
      {
        num: 'STEP 02',
        title: 'Approve the story',
        body: 'TaleLah proposes a short story, a speaking goal and the exact words. You review, tweak and approve — nothing reaches your child unseen.',
      },
      {
        num: 'STEP 03',
        title: 'Your child speaks',
        body: 'Mina the Myna guides a 4-scene adventure and listens for one real spoken line — with gentle help, never a score.',
      },
      {
        num: 'STEP 04',
        title: 'Family takes over',
        body: 'An off-screen mission, then the phone passes to you or grandma for one warm mother-tongue exchange. The screen disappears.',
      },
    ],
  },
  screens: {
    eyebrow: 'Inside the app',
    title: 'Built for parents. Loved by kids.',
    lede: 'A calm, text-supported parent mode. A picture-first child mode with one thing to do per screen.',
    caps: ['1 · Capture', "2 · Child's story", '3 · Child speaks', '4 · Family handoff'],
    note: 'Illustrative screens · real screenshots drop in here.',
  },
  difference: {
    eyebrow: 'Why TaleLah',
    title: 'Not another story generator. Not another lesson app.',
    head: ['What else exists', 'What it does', 'TaleLah'],
    rows: [
      {
        who: 'AI story generators',
        what: 'Entertain with a custom story',
        talelah: "Starts from your child's real day, aims at real speaking",
      },
      {
        who: 'Language-learning apps',
        what: 'Teach vocabulary through drills',
        talelah: 'Creates a family conversation, not a worksheet',
      },
      {
        who: 'Audiobooks & players',
        what: 'Passive listening',
        talelah: 'Requires your child to speak and your family to join',
      },
      {
        who: 'Tuition & assessment books',
        what: 'Optimise for the exam',
        talelah: 'Builds confidence and everyday use — no scores',
      },
    ],
  },
  trust: {
    eyebrow: 'Built for young children',
    title: "Safe by design — a parent's product.",
    cards: [
      {
        icon: '✓',
        title: 'Every story is parent-approved',
        body: "Nothing reaches your child until you've reviewed and approved it. No open chatbot, no surprises.",
      },
      {
        icon: '🔒',
        title: 'No raw child audio kept',
        body: "Your child's voice is turned into a simple response and discarded by default. You choose what to save.",
      },
      {
        icon: '☺',
        title: 'No scores, no rankings',
        body: 'TaleLah celebrates speaking — it never grades your child or labels them "behind".',
      },
      {
        icon: '🛡',
        title: 'Privacy-minded, PDPA-aware',
        body: 'Child aliases only — no full name, school or face needed. No ads, no links, no messaging in child mode.',
      },
    ],
  },
  languages: {
    eyebrow: "Singapore's mother tongues — equal at home",
    title: 'One home. Three tongues. Kept alive.',
    items: [
      {
        cls: 'ta',
        script: 'தமிழ்',
        name: 'Tamil',
        body: 'Warm spoken Singapore Tamil, with romanisation and English meaning for every line.',
      },
      {
        cls: 'zh',
        script: '中文',
        name: 'Chinese',
        body: "Simplified characters + Hanyu Pinyin, pitched to your child's level.",
      },
      {
        cls: 'ms',
        script: 'Melayu',
        name: 'Malay',
        body: 'Everyday Bahasa Melayu, with English meaning where you want it.',
      },
    ],
    english: {
      badge: 'And yes — English too',
      title: 'English stories work here as well.',
      body: "TaleLah can tell the same adventure in English. But we'll always gently nudge you toward your home language — because English is everywhere, while the language of your grandparents lives or fades at home.",
    },
    note: 'Language is chosen by your family — never assumed from your name or background.',
  },
  builtWith: {
    eyebrow: 'Built with',
    title: 'Agentic AI, made in Singapore',
    lede: 'Six coordinated AI agents craft, translate and safety-check every story — orchestrated with a spec-driven workflow and powered by regional language models.',
  },
  finalCta: {
    eyebrow: 'Try it tonight',
    title: "Turn today's moment into tonight's mother-tongue conversation.",
    body: 'Capture one thing your child did today. In five minutes, hear them speak Tamil, Chinese or Malay — and watch your family join in.',
    ctaPrimary: 'Try Now →',
    ctaSecondary: 'Watch the story',
  },
  footer: { tagline: 'Everyday moments. Mother-tongue magic. · Made in Singapore, 2026' },
  mock: mockTa,
};
