/// Built-in sample stories -- one per language (Tamil, Chinese, Malay).
///
/// These ship with the app so new users can try the reading experience
/// instantly, without waiting for the 4-5 minute AI generation pipeline.
/// Audio manifest is intentionally empty: the child session gracefully
/// falls back to parent-read mode (the adult reads aloud from the screen).
import '../models/story_package.dart';

/// All three sample stories, keyed by locale for quick lookup.
final Map<String, ApprovedStory> sampleStories = {
  'ta-SG': _tamilPigeonAdventure,
  'zh-SG': _chinesePlaygroundQuest,
  'ms-SG': _malayCookingWithNenek,
};

/// Ordered list for UI rendering (matches the locale pill order on Home).
final List<ApprovedStory> sampleStoryList = [
  _tamilPigeonAdventure,
  _chinesePlaygroundQuest,
  _malayCookingWithNenek,
];

// ── Tamil: The Pigeon Adventure ──────────────────────────────────────────

final _tamilPigeonAdventure = ApprovedStory(
  packageId: 'sample_ta_pigeon',
  locale: 'ta-SG',
  title: 'The Pigeon Adventure',
  titleTargetLang: 'புறா சாகசம்',
  refrain: 'Fly, little pigeon, fly so high!',
  refrainTargetLang: 'பற, சின்ன புறா, வானத்தில் பற!',
  speakingGoal: 'Say the word "pigeon" in Tamil',
  targetPhrase: 'புறா (pura)',
  targetWords: ['புறா', 'அம்மா', 'ரொட்டி'],
  vocabulary: [
    VocabWord(word: 'pigeon', wordTargetLang: 'புறா', romanised: 'pura'),
    VocabWord(word: 'mother', wordTargetLang: 'அம்மா', romanised: 'amma'),
    VocabWord(word: 'bread', wordTargetLang: 'ரொட்டி', romanised: 'rotti'),
    VocabWord(word: 'sky', wordTargetLang: 'வானம்', romanised: 'vaanam'),
  ],
  mission: 'Find something grey in your room and bring it to Amma or Appa!',
  missionTargetLang: 'உன் அறையில் சாம்பல் நிற பொருள் ஒன்றை கண்டுபிடி!',
  handoffPrompt:
      'Ask your child: what did we feed the pigeons? What colour were they?',
  handoffPromptTargetLang:
      'உங்கள் குழந்தையிடம் கேளுங்கள்: புறாக்களுக்கு என்ன கொடுத்தோம்? அவை என்ன நிறம்?',
  handoffResponseSuggestion: 'We fed them bread! They were grey and white.',
  familyVoiceMode: 'confident_speaker',
  scenes: [
    ApprovedScene(
      index: 0,
      title: 'At the Void Deck',
      titleTargetLang: 'வாயில் தளத்தில்',
      emoji: '🏠',
      narration:
          'One sunny morning, Arun and Amma went to the void deck below their flat. '
          'Arun carried a small bag of bread.',
      narrationTargetLang:
          'ஒரு வெயில் காலையில், அருணும் அம்மாவும் அவர்கள் வீட்டின் கீழே வாயில் தளத்திற்கு சென்றார்கள். '
          'அருண் ஒரு சிறிய ரொட்டி பையை கொண்டு சென்றான்.',
      interactionType: 'listen',
    ),
    ApprovedScene(
      index: 1,
      title: 'The Pigeons Arrive',
      titleTargetLang: 'புறாக்கள் வருகின்றன',
      emoji: '🕊️',
      narration:
          'Grey pigeons landed on the ground! One, two, three — so many pigeons! '
          'Arun broke the bread into small pieces and threw them gently.',
      narrationTargetLang:
          'சாம்பல் நிற புறாக்கள் தரையில் இறங்கின! ஒன்று, இரண்டு, மூன்று — எவ்வளவு புறாக்கள்! '
          'அருண் ரொட்டியை சிறிய துண்டுகளாக உடைத்து மெதுவாக வீசினான்.',
      interactionType: 'speak',
      expectedIntent: 'pigeon',
    ),
    ApprovedScene(
      index: 2,
      title: 'One Brave Pigeon',
      titleTargetLang: 'ஒரு தைரியமான புறா',
      emoji: '🐦',
      narration:
          'One brave pigeon came very close to Arun. It pecked the bread right '
          'from his hand! Arun laughed. "Look Amma, it is eating from my hand!"',
      narrationTargetLang:
          'ஒரு தைரியமான புறா அருணின் அருகில் வந்தது. அது அவன் கையிலிருந்தே ரொட்டியை கொத்தியது! '
          'அருண் சிரித்தான். "அம்மா பாரு, அது என் கையிலிருந்து சாப்பிடுகிறது!"',
      interactionType: 'speak',
      expectedIntent: 'bread',
    ),
    ApprovedScene(
      index: 3,
      title: 'Time to Fly Home',
      titleTargetLang: 'வீட்டிற்கு செல்லும் நேரம்',
      emoji: '🌤️',
      narration:
          'The sun went behind the clouds. "Time to go home," said Amma. '
          'Arun waved goodbye. The pigeons flew up into the sky — fly, little pigeon, fly so high!',
      narrationTargetLang:
          'சூரியன் மேகங்களுக்கு பின்னால் சென்றது. "வீட்டிற்கு போகலாம்," என்றாள் அம்மா. '
          'அருண் கையை ஆட்டி விடைபெற்றான். புறாக்கள் வானத்தில் பறந்தன — பற, சின்ன புறா, வானத்தில் பற!',
      interactionType: 'listen',
    ),
  ],
);

// ── Chinese: The Playground Quest ─────────────────────────────────────────

final _chinesePlaygroundQuest = ApprovedStory(
  packageId: 'sample_zh_playground',
  locale: 'zh-SG',
  title: 'The Playground Quest',
  titleTargetLang: '游乐场探险',
  refrain: 'Higher, higher, touch the sky!',
  refrainTargetLang: '更高，更高，摸到天！',
  speakingGoal: 'Say the word "slide" in Chinese',
  targetPhrase: '滑梯 (huá tī)',
  targetWords: ['滑梯', '红色', '朋友'],
  vocabulary: [
    VocabWord(word: 'slide', wordTargetLang: '滑梯', romanised: 'hua ti'),
    VocabWord(word: 'red', wordTargetLang: '红色', romanised: 'hong se'),
    VocabWord(word: 'friend', wordTargetLang: '朋友', romanised: 'peng you'),
    VocabWord(word: 'swing', wordTargetLang: '秋千', romanised: 'qiu qian'),
  ],
  mission: 'Count three things in your room that are red and tell Amma or Baba!',
  missionTargetLang: '在你的房间里数三个红色的东西，告诉妈妈或爸爸！',
  handoffPrompt:
      'Ask your child: what was your favourite thing at the playground? The slide or the swing?',
  handoffPromptTargetLang: '问你的孩子：游乐场里你最喜欢什么？滑梯还是秋千？',
  handoffResponseSuggestion: 'I liked the red slide! I went down so fast!',
  familyVoiceMode: 'confident_speaker',
  scenes: [
    ApprovedScene(
      index: 0,
      title: 'Off to the Playground',
      titleTargetLang: '出发去游乐场',
      emoji: '🏃',
      narration:
          'After lunch, Mei Ling and Baba walked to the playground. '
          'Mei Ling ran ahead — she could see the big red slide from far away!',
      narrationTargetLang:
          '午饭后，美玲和爸爸走路去游乐场。'
          '美玲跑在前面——她从远处就能看到那个红色的大滑梯！',
      interactionType: 'listen',
    ),
    ApprovedScene(
      index: 1,
      title: 'The Big Red Slide',
      titleTargetLang: '红色的大滑梯',
      emoji: '🛝',
      narration:
          'Mei Ling climbed the stairs — one, two, three, four steps! '
          'She sat at the top and pushed off. Wheee! She slid down so fast, her hair flew in the wind.',
      narrationTargetLang:
          '美玲爬上了楼梯——一、二、三、四步！'
          '她坐在顶上，用力一推。哇！她滑得好快，头发都飞起来了。',
      interactionType: 'speak',
      expectedIntent: 'slide',
    ),
    ApprovedScene(
      index: 2,
      title: 'A New Friend',
      titleTargetLang: '新朋友',
      emoji: '👧',
      narration:
          'At the swings, a boy was swinging high. "Can I swing too?" asked Mei Ling. '
          '"Of course!" said the boy. "I am Kai Wen. Let us be friends!"',
      narrationTargetLang:
          '在秋千旁，一个男孩荡得好高。"我也可以荡吗？"美玲问。'
          '"当然可以！"男孩说。"我叫凯文。我们做朋友吧！"',
      interactionType: 'speak',
      expectedIntent: 'friend',
    ),
    ApprovedScene(
      index: 3,
      title: 'Higher and Higher',
      titleTargetLang: '更高更高',
      emoji: '🌈',
      narration:
          'Mei Ling and Kai Wen swung together — higher, higher, touch the sky! '
          'Baba clapped and cheered. What a wonderful day at the playground!',
      narrationTargetLang:
          '美玲和凯文一起荡秋千——更高，更高，摸到天！'
          '爸爸拍手欢呼。今天在游乐场玩得好开心！',
      interactionType: 'listen',
    ),
  ],
);

// ── Malay: Cooking with Nenek ─────────────────────────────────────────────

final _malayCookingWithNenek = ApprovedStory(
  packageId: 'sample_ms_cooking',
  locale: 'ms-SG',
  title: 'Cooking with Nenek',
  titleTargetLang: 'Masak Bersama Nenek',
  refrain: 'Stir, stir, stir the pot — yummy kuih, nice and hot!',
  refrainTargetLang: 'Kacau, kacau, kacau periuk — kuih sedap, panas elok!',
  speakingGoal: 'Say the word "kuih" in Malay',
  targetPhrase: 'kuih',
  targetWords: ['kuih', 'nenek', 'sedap'],
  vocabulary: [
    VocabWord(word: 'cake', wordTargetLang: 'kuih', romanised: 'kuih'),
    VocabWord(word: 'grandmother', wordTargetLang: 'nenek', romanised: 'nenek'),
    VocabWord(word: 'delicious', wordTargetLang: 'sedap', romanised: 'sedap'),
    VocabWord(word: 'coconut', wordTargetLang: 'kelapa', romanised: 'kelapa'),
  ],
  mission:
      'Find something sweet-smelling in your kitchen and tell Nenek or Mama what it is!',
  missionTargetLang:
      'Cari sesuatu yang wangi di dapur dan beritahu Nenek atau Mama!',
  handoffPrompt:
      'Ask your child: what did we cook with Nenek? What colour was the kuih?',
  handoffPromptTargetLang:
      'Tanya anak anda: kita masak apa dengan Nenek? Kuih itu warna apa?',
  handoffResponseSuggestion:
      'We made green kuih! It was sweet and yummy.',
  familyVoiceMode: 'confident_speaker',
  scenes: [
    ApprovedScene(
      index: 0,
      title: 'In Nenek\'s Kitchen',
      titleTargetLang: 'Di Dapur Nenek',
      emoji: '👵',
      narration:
          'Today is a special day. Aisyah is helping Nenek make kuih! '
          'Nenek put on a big apron for Aisyah. "Ready, little chef?" she asked.',
      narrationTargetLang:
          'Hari ini hari istimewa. Aisyah tolong Nenek buat kuih! '
          'Nenek pakaikan apron besar untuk Aisyah. "Sedia, tukang masak kecil?" tanya Nenek.',
      interactionType: 'listen',
    ),
    ApprovedScene(
      index: 1,
      title: 'Mixing the Batter',
      titleTargetLang: 'Mengacau Adunan',
      emoji: '🥣',
      narration:
          'Nenek poured coconut milk and green pandan juice into a big bowl. '
          'Aisyah stirred with a wooden spoon — stir, stir, stir the pot! '
          'The batter turned bright green, like the leaves in the garden.',
      narrationTargetLang:
          'Nenek tuangkan santan dan air pandan hijau ke dalam mangkuk besar. '
          'Aisyah kacau dengan sudu kayu — kacau, kacau, kacau periuk! '
          'Adunan itu bertukar hijau terang, macam daun di taman.',
      interactionType: 'speak',
      expectedIntent: 'kuih',
    ),
    ApprovedScene(
      index: 2,
      title: 'Waiting for the Kuih',
      titleTargetLang: 'Menunggu Kuih',
      emoji: '⏰',
      narration:
          'Nenek put the green batter into small moulds and placed them in the steamer. '
          '"Now we wait," she said. Aisyah sat at the table and drew a picture '
          'of Nenek while the kitchen filled with a sweet, yummy smell.',
      narrationTargetLang:
          'Nenek masukkan adunan hijau ke dalam acuan kecil dan letak dalam pengukus. '
          '"Sekarang kita tunggu," kata Nenek. Aisyah duduk di meja dan lukis gambar '
          'Nenek sementara dapur penuh dengan bau yang sedap.',
      interactionType: 'speak',
      expectedIntent: 'delicious',
    ),
    ApprovedScene(
      index: 3,
      title: 'Taste Test!',
      titleTargetLang: 'Rasa!',
      emoji: '🎉',
      narration:
          'The kuih were ready! Nenek placed one on a plate for Aisyah. '
          'She took a small bite. "Sedap!" she said — delicious! '
          'Nenek smiled. "The best kuih is the one we make together."',
      narrationTargetLang:
          'Kuih sudah siap! Nenek letakkan satu di atas pinggan untuk Aisyah. '
          'Dia ambil satu gigitan kecil. "Sedap!" katanya — lazat! '
          'Nenek tersenyum. "Kuih paling sedap ialah kuih yang kita buat bersama."',
      interactionType: 'listen',
    ),
  ],
);
