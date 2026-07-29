// English page's phone mockup: Tamil story demo with English UI chrome.
// (ta/zh/ms pages define their own fully-native mocks in ta.ts/zh.ts/ms.ts.)
import type { MockStrings } from './types';

export const mockTa: MockStrings = {
  script: 'ta',
  childChip: 'Arjun · தமிழ்',
  hero: {
    line: 'இது என்ன நிறம்?',
    rom: 'Idhu enna niram?',
    en: '“What colour is this?”',
    micBtn: '🎙 Tap to speak with Mina',
    stickerTop: '✨ 5-min story',
    stickerBottom: '🎙 She listens & replies',
  },
  capture: {
    chip: 'Parent',
    kick: "Today's moment",
    note: '“built an MRT track from blocks”',
    btn: "Create today's adventure ✨",
  },
  story: { chip: 'தமிழ்', line: 'அடுத்து எது வரும்?', rom: 'Aduthu edhu varum?' },
  mic: { chip: '● Listening', line: 'சிவப்பு ரயில்!', rom: 'Sivappu rayil!' },
  handoff: {
    chip: 'Family',
    kick: 'Hand to a family speaker',
    line: 'அவனிடம் கேளுங்கள்…',
    note: 'One prompt · one big button',
  },
};
