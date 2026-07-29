// Malay (Bahasa Melayu, Singapore) — full native marketing copy + fully
// Malay in-phone mockups. Drafted for launch; flagged for a native-speaker
// pass before public release.
import type { MockStrings, SiteContent } from './types';

/** Malay page shows the app the way a Malay-speaking family would meet it. */
const mock: MockStrings = {
  script: 'ms',
  childChip: 'Aisyah · Melayu',
  hero: {
    line: 'Ini warna apa?',
    rom: 'Ini warna apa?',
    en: '“What colour is this?”',
    micBtn: '🎙 Tekan & cakap dengan Mina',
    stickerTop: '✨ Cerita 5 minit',
    stickerBottom: '🎙 Dia dengar & membalas',
  },
  capture: {
    chip: 'Ibu bapa',
    kick: 'Detik hari ini',
    note: '“bina trek MRT daripada blok”',
    btn: 'Cipta pengembaraan hari ini ✨',
  },
  story: { chip: 'Melayu', line: 'Apa yang datang seterusnya?', rom: 'Apa seterusnya?' },
  mic: { chip: '● Mendengar', line: 'Kereta api merah!', rom: 'Kereta api merah!' },
  handoff: {
    chip: 'Keluarga',
    kick: 'Serahkan kepada ahli keluarga',
    line: 'Tanyalah dia…',
    note: 'Satu ayat · satu butang besar',
  },
};

export const ms: SiteContent = {
  meta: {
    title: 'TaleLah — Detik harian. Keajaiban bahasa ibunda.',
    description:
      'TaleLah mengubah apa yang anak anda buat hari ini menjadi pengembaraan Bahasa Melayu lima minit — yang berakhir dengan keluarga berbual, bukan skrin.',
  },
  nav: {
    problem: 'Masalahnya',
    how: 'Cara ia berfungsi',
    languages: 'Bahasa',
    cta: 'Cuba demo',
  },
  hero: {
    eyebrow: 'Singapura · untuk keluarga anak 4–8 tahun',
    titleA: 'Detik harian.',
    titleB: 'Keajaiban bahasa ibunda.',
    lede: 'TaleLah mengubah sesuatu yang benar-benar anak anda lakukan hari ini menjadi pengembaraan Bahasa Melayu lima minit — yang berakhir dengan keluarga anda <b>berbual</b>, bukan skrin.',
    ctaPrimary: 'Cuba demo →',
    ctaSecondary: 'Lihat cara ia berfungsi',
    trust: ['Diluluskan ibu bapa', 'Tiada rasa bersalah skrin', 'Sedia dalam 2 minit'],
  },
  problem: {
    eyebrow: 'Masalahnya',
    title: 'Bahasa ibunda menjadi subjek sekolah — bukan bahasa di rumah.',
    statLabel: 'Rumah yang paling kerap berbahasa Inggeris, 2020 → 2025',
    statValue: '58',
    lede: 'Pada 2020, Bahasa Inggeris ialah bahasa yang paling kerap dituturkan di rumah oleh <b>48.3%</b> penduduk. Menjelang 2025 ia <b>58.1%</b> — lebih tinggi dalam kalangan kanak-kanak kecil. Anak anda belajar bahasa ibunda di sekolah, tetapi menjalani kehidupan harian dalam Bahasa Inggeris.',
    source: 'Sumber: Jabatan Perangkaan Singapura · Banci 2020 & General Household Survey 2025.',
  },
  insight: {
    eyebrow: 'Mengapa lebih banyak aplikasi tidak membantu',
    title: 'Sekolah memberi pelajaran. Hanya rumah memberi penggunaan.',
    body: 'Lebih banyak lembaran kerja, lebih banyak latih tubi, lebih banyak pelajaran skrin — semuanya menambah apa yang memang tidak berkesan. Bahasa terus hidup apabila anak ada sebab sebenar untuk <b>bercakap</b> selepas sekolah. TaleLah mencipta sebab itu.',
  },
  how: {
    eyebrow: 'Penyelesaiannya',
    title: 'Satu detik sebenar. Satu pengembaraan lima minit.<br>Satu perbualan keluarga.',
    lede: 'Anda rakam apa yang anak buat hari ini. TaleLah menulis cerita kecil bahasa ibunda di sekelilingnya, anak anda bercakap sepanjang cerita, kemudian ia melangkah keluar dari skrin ke rumah anda.',
    steps: [
      {
        num: 'LANGKAH 01',
        title: 'Rakam satu detik',
        body: 'Ambil gambar, rakam nota suara, atau taip sebaris — "Aisyah bina trek MRT daripada blok." Bawah dua minit.',
      },
      {
        num: 'LANGKAH 02',
        title: 'Luluskan cerita',
        body: 'TaleLah mencadangkan cerita pendek, matlamat bertutur dan perkataan yang tepat. Anda semak, ubah dan luluskan — tiada apa sampai kepada anak tanpa anda lihat.',
      },
      {
        num: 'LANGKAH 03',
        title: 'Anak anda bercakap',
        body: 'Mina si Tiong membimbing pengembaraan 4 babak dan mendengar satu ayat lisan sebenar — dengan bantuan lembut, tanpa markah.',
      },
      {
        num: 'LANGKAH 04',
        title: 'Keluarga ambil alih',
        body: 'Satu misi luar skrin, kemudian telefon berpindah kepada anda atau nenek untuk satu perbualan bahasa ibunda yang mesra. Skrin pun hilang.',
      },
    ],
  },
  screens: {
    eyebrow: 'Dalam aplikasi',
    title: 'Dibina untuk ibu bapa. Disayangi anak-anak.',
    lede: 'Mod ibu bapa yang tenang dengan sokongan teks. Mod anak yang mengutamakan gambar — satu perkara sahaja setiap skrin.',
    caps: ['1 · Rakam', '2 · Cerita anak', '3 · Anak bercakap', '4 · Serahan keluarga'],
    note: 'Skrin ilustrasi · tangkapan skrin sebenar akan diletakkan di sini.',
  },
  difference: {
    eyebrow: 'Mengapa TaleLah',
    title: 'Bukan satu lagi penjana cerita. Bukan satu lagi aplikasi pelajaran.',
    head: ['Yang sedia ada', 'Apa ia buat', 'TaleLah'],
    rows: [
      {
        who: 'Penjana cerita AI',
        what: 'Menghibur dengan cerita tersuai',
        talelah: 'Bermula daripada hari sebenar anak anda, menyasarkan pertuturan sebenar',
      },
      {
        who: 'Aplikasi belajar bahasa',
        what: 'Mengajar kosa kata melalui latih tubi',
        talelah: 'Mencipta perbualan keluarga, bukan lembaran kerja',
      },
      {
        who: 'Buku audio & pemain',
        what: 'Pendengaran pasif',
        talelah: 'Memerlukan anak bercakap dan keluarga menyertai',
      },
      {
        who: 'Tuisyen & buku penilaian',
        what: 'Dioptimumkan untuk peperiksaan',
        talelah: 'Membina keyakinan dan penggunaan harian — tanpa markah',
      },
    ],
  },
  trust: {
    eyebrow: 'Dibina untuk kanak-kanak kecil',
    title: 'Selamat sejak reka bentuk — produk ibu bapa.',
    cards: [
      {
        icon: '✓',
        title: 'Setiap cerita diluluskan ibu bapa',
        body: 'Tiada apa sampai kepada anak sehingga anda menyemak dan meluluskannya. Tiada chatbot terbuka, tiada kejutan.',
      },
      {
        icon: '🔒',
        title: 'Audio asal anak tidak disimpan',
        body: 'Suara anak ditukar kepada respons ringkas dan dibuang secara lalai. Anda yang pilih apa untuk disimpan.',
      },
      {
        icon: '☺',
        title: 'Tiada markah, tiada ranking',
        body: 'TaleLah meraikan pertuturan — tidak pernah menggred anak anda atau melabel mereka "ketinggalan".',
      },
      {
        icon: '🛡',
        title: 'Mementingkan privasi, peka PDPA',
        body: 'Nama samaran anak sahaja — tiada nama penuh, sekolah atau wajah diperlukan. Tiada iklan, pautan atau mesej dalam mod anak.',
      },
    ],
  },
  languages: {
    eyebrow: 'Bahasa ibunda Singapura — sama rata di rumah',
    title: 'Satu rumah. Tiga bahasa. Terus hidup.',
    items: [
      {
        cls: 'ta',
        script: 'தமிழ்',
        name: 'Tamil',
        body: 'Bahasa Tamil pertuturan Singapura yang mesra, dengan rumi dan makna Inggeris untuk setiap baris.',
      },
      {
        cls: 'zh',
        script: '中文',
        name: 'Cina',
        body: 'Aksara ringkas + Hanyu Pinyin, disesuaikan dengan tahap anak anda.',
      },
      {
        cls: 'ms',
        script: 'Melayu',
        name: 'Melayu',
        body: 'Bahasa Melayu harian, dengan makna Inggeris jika anda mahu.',
      },
    ],
    english: {
      badge: 'Dan ya — Inggeris pun boleh',
      title: 'Cerita Bahasa Inggeris juga berfungsi di sini.',
      body: 'TaleLah boleh menceritakan pengembaraan yang sama dalam Bahasa Inggeris. Tetapi kami akan sentiasa mengajak anda kembali kepada bahasa rumah anda — kerana Bahasa Inggeris ada di mana-mana, manakala bahasa datuk nenek hidup atau pudar di rumah.',
    },
    note: 'Bahasa dipilih oleh keluarga anda — tidak sesekali diandaikan daripada nama atau latar belakang.',
  },
  builtWith: {
    eyebrow: 'Dibina dengan',
    title: 'AI Agentik, buatan Singapura',
    lede: 'Enam ejen AI yang diselaraskan mencipta, menterjemah dan menyemak keselamatan setiap cerita — diatur dengan aliran kerja berpandukan spesifikasi dan dikuasakan model bahasa serantau.',
  },
  finalCta: {
    eyebrow: 'Cuba malam ini',
    title: 'Jadikan detik hari ini perbualan bahasa ibunda malam ini.',
    body: 'Rakam satu perkara yang anak buat hari ini. Dalam lima minit, dengar mereka bertutur Bahasa Melayu — dan lihat keluarga anda menyertai.',
    ctaPrimary: 'Cuba demo →',
    ctaSecondary: 'Tonton ceritanya',
  },
  footer: { tagline: 'Detik harian. Keajaiban bahasa ibunda. · Buatan Singapura, 2026' },
  mock,
};
