// Chinese (Simplified, Singapore) — full native marketing copy + fully
// Chinese in-phone mockups. Drafted for launch; flagged for a native-speaker
// pass before public release.
import type { MockStrings, SiteContent } from './types';

/** Chinese page shows the app the way a Chinese-speaking family would meet it. */
const mock: MockStrings = {
  script: 'zh',
  childChip: '美玲 · 中文',
  hero: {
    line: '这是什么颜色？',
    rom: 'Zhè shì shénme yánsè?',
    en: '“What colour is this?”',
    micBtn: '🎙 点一下，和 Mina 说话',
    stickerTop: '✨ 5 分钟故事',
    stickerBottom: '🎙 会听、会回应',
  },
  capture: {
    chip: '家长',
    kick: '今天的时刻',
    note: '“用积木搭了地铁轨道”',
    btn: '生成今天的冒险 ✨',
  },
  story: { chip: '中文', line: '接下来是什么？', rom: 'Jiē xiàlái shì shénme?' },
  mic: { chip: '● 聆听中', line: '红色的火车！', rom: 'Hóngsè de huǒchē!' },
  handoff: {
    chip: '家人',
    kick: '交给会说华语的家人',
    line: '问问他吧……',
    note: '一句提示 · 一个大按钮',
  },
};

export const zh: SiteContent = {
  meta: {
    title: 'TaleLah — 日常时刻，母语魔法。',
    description:
      'TaleLah 把孩子今天做过的事，变成一段五分钟的华语小冒险——结尾不是屏幕，而是全家开口聊天。',
  },
  nav: {
    problem: '问题所在',
    how: '如何运作',
    languages: '语言',
    cta: '立即试用',
  },
  hero: {
    eyebrow: '新加坡 · 为有 4–8 岁孩子的家庭而做',
    titleA: '日常时刻。',
    titleB: '母语魔法。',
    lede: 'TaleLah 把孩子今天真实做过的一件事，变成五分钟的华语小冒险——结尾不是屏幕，而是全家一起<b>开口说话</b>。',
    ctaPrimary: '立即试用 →',
    ctaSecondary: '看看怎么运作',
    trust: ['家长逐一审核', '没有屏幕时间焦虑', '2 分钟即可上手'],
  },
  problem: {
    eyebrow: '问题所在',
    title: '母语正在变成一门学校科目——而不是家里的语言。',
    statLabel: '在家最常说英语的家庭',
    statDelta: '五年内上升 9.8 个百分点',
    statValue: '58',
    lede: '2020 年，<b>48.3%</b> 的居民在家最常说英语；到 2025 年已是 <b>58.1%</b>——在幼童中比例更高。孩子在学校学母语，日常生活却在英语里。',
    source: '来源：新加坡统计局 · Census 2020 与 General Household Survey 2025。',
  },
  insight: {
    eyebrow: '为什么更多 App 没有用',
    title: '学校给的是课程，家里给的才是使用。',
    body: '更多练习册、更多刷题、更多屏幕课——只是把本来就不奏效的事做得更多。语言要活下去，孩子放学后得有一个真正<b>开口说</b>的理由。TaleLah 就是造出这个理由。',
  },
  how: {
    eyebrow: '解决方案',
    title: '一个真实时刻。一段五分钟冒险。<br>一次全家对话。',
    lede: '你记录孩子今天做的事，TaleLah 围绕它写一个迷你母语故事，孩子一路开口说完，最后故事走下屏幕、走进家里。',
    steps: [
      {
        num: '第 1 步',
        title: '记录一个时刻',
        body: '拍张照、录段语音、或打一行字——“美玲用积木搭了地铁轨道。”不到两分钟。',
      },
      {
        num: '第 2 步',
        title: '审核这个故事',
        body: 'TaleLah 提议一个短故事、一个开口目标和确切的句子。你查看、修改、批准——没审核过的内容不会出现在孩子面前。',
      },
      {
        num: '第 3 步',
        title: '孩子开口说',
        body: '八哥 Mina 带着孩子走过 4 个场景，聆听一句真实的口语表达——温柔引导，绝不打分。',
      },
      {
        num: '第 4 步',
        title: '交给家人',
        body: '一个离屏小任务，然后手机交给你或阿嬷，完成一次温暖的母语对话。屏幕就此退场。',
      },
    ],
  },
  screens: {
    eyebrow: '走进 App',
    title: '为家长而建，孩子会爱上。',
    lede: '家长模式安静、有文字辅助；孩子模式以图为主，每屏只做一件事。',
    caps: ['1 · 记录', '2 · 孩子的故事', '3 · 孩子开口', '4 · 家人接力'],
    note: '示意屏幕 · 真实截图将放在这里。',
  },
  difference: {
    eyebrow: '为什么选 TaleLah',
    title: '不是又一个故事生成器，也不是又一个刷题 App。',
    head: ['市面上的产品', '它们做什么', 'TaleLah'],
    rows: [
      {
        who: 'AI 故事生成器',
        what: '用定制故事哄孩子开心',
        talelah: '从孩子真实的一天出发，目标是真正开口说',
      },
      {
        who: '语言学习 App',
        what: '靠刷题教词汇',
        talelah: '创造的是全家对话，不是练习册',
      },
      {
        who: '有声书与播放器',
        what: '被动地听',
        talelah: '需要孩子开口、家人加入',
      },
      {
        who: '补习与评估册',
        what: '为考试优化',
        talelah: '建立自信与日常使用——没有分数',
      },
    ],
  },
  trust: {
    eyebrow: '为幼童而建',
    title: '安全为先——一款属于家长的产品。',
    cards: [
      {
        icon: '✓',
        title: '每个故事都经家长审核',
        body: '你审核批准之前，什么都不会出现在孩子面前。没有开放式聊天机器人，没有意外。',
      },
      {
        icon: '🔒',
        title: '不保留孩子的原始录音',
        body: '孩子的声音会被转成简单的回应后默认删除。保存与否，由你决定。',
      },
      {
        icon: '☺',
        title: '没有分数，没有排名',
        body: 'TaleLah 庆祝开口说话——从不给孩子打分，也不贴“落后”的标签。',
      },
      {
        icon: '🛡',
        title: '注重隐私，符合 PDPA 精神',
        body: '只用孩子昵称——不需要全名、学校或人脸。儿童模式没有广告、链接和聊天。',
      },
    ],
  },
  languages: {
    eyebrow: '新加坡的母语——在家一律平等',
    title: '一个家。三种母语。生生不息。',
    items: [
      {
        cls: 'ta',
        script: 'தமிழ்',
        name: '泰米尔语',
        body: '温暖地道的新加坡口语泰米尔语，每句配罗马拼音和英文释义。',
      },
      {
        cls: 'zh',
        script: '中文',
        name: '华语',
        body: '简体字 + 汉语拼音，按孩子的水平量身调整。',
      },
      {
        cls: 'ms',
        script: 'Melayu',
        name: '马来语',
        body: '日常马来语，需要时配英文释义。',
      },
    ],
    english: {
      badge: '当然——也有英语',
      title: '英语故事这里也可以。',
      body: 'TaleLah 也能用英语讲同一个冒险。但我们始终会温柔地把你引向家里的母语——因为英语无处不在，而祖辈的语言，只会在家里延续，或在家里消失。',
    },
    note: '语言由你的家庭选择——绝不会从姓名或背景来推断。',
  },
  builtWith: {
    eyebrow: '技术底座',
    title: 'Agentic AI，新加坡制造',
    lede: '六个协作的 AI 智能体为每个故事进行创作、翻译与安全审查——由规格驱动的工作流编排，由区域语言模型驱动。',
  },
  finalCta: {
    eyebrow: '今晚就试试',
    title: '把今天的时刻，变成今晚的母语对话。',
    body: '记录孩子今天做的一件事。五分钟后，听他们说出华语——看全家一起加入。',
    ctaPrimary: '立即试用 →',
    ctaSecondary: '看看这个故事',
  },
  footer: { tagline: '日常时刻，母语魔法。· 新加坡制造，2026' },
  mock,
};
