/// TaleLah data models matching backend Story Package contract.

class ChildProfile {
  final String id;
  final String alias;
  final String ageBand;
  final String targetLocale;
  final String understandingLevel;
  final String speakingLevel;
  final List<String> interests;
  final String homeLanguage;
  final String? photoUrl;

  ChildProfile({
    required this.id,
    required this.alias,
    required this.ageBand,
    this.targetLocale = 'ta-SG',
    this.understandingLevel = 'emerging',
    this.speakingLevel = 'emerging',
    this.interests = const [],
    this.homeLanguage = 'en',
    this.photoUrl,
  });

  factory ChildProfile.fromJson(Map<String, dynamic> json) => ChildProfile(
        id: json['id'] as String,
        alias: json['alias'] as String,
        ageBand: json['age_band'] as String,
        targetLocale: json['target_locale'] as String? ?? 'ta-SG',
        understandingLevel: json['understanding_level'] as String? ?? 'emerging',
        speakingLevel: json['speaking_level'] as String? ?? 'emerging',
        interests: (json['interests'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        homeLanguage: json['home_language'] as String? ?? 'en',
        photoUrl: json['photo_url'] as String?,
      );
}

class Moment {
  final String id;
  final String childProfileId;
  final String parentText;
  final String status;
  final String createdAt;

  Moment({
    required this.id,
    required this.childProfileId,
    required this.parentText,
    this.status = 'captured',
    this.createdAt = '',
  });

  factory Moment.fromJson(Map<String, dynamic> json) => Moment(
        id: json['id'] as String,
        childProfileId: json['child_profile_id'] as String,
        parentText: json['parent_text'] as String? ?? '',
        status: json['status'] as String? ?? 'captured',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class StoryScene {
  final int index;
  final String title;
  final String narrationEnglish;
  final String narrationTargetLang;
  final String? audioUrl;
  final String interactionType;
  final String? promptText;
  final List<String> expectedResponses;

  StoryScene({
    required this.index,
    required this.title,
    this.narrationEnglish = '',
    this.narrationTargetLang = '',
    this.audioUrl,
    this.interactionType = 'listen',
    this.promptText,
    this.expectedResponses = const [],
  });

  factory StoryScene.fromJson(Map<String, dynamic> json) => StoryScene(
        index: json['index'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        narrationEnglish: json['narration_english'] as String? ?? '',
        narrationTargetLang: json['narration_target_lang'] as String? ?? '',
        audioUrl: json['audio_data_uri'] as String?,
        interactionType: json['interaction_type'] as String? ?? 'listen',
        promptText: json['prompt_text'] as String?,
        expectedResponses: (json['expected_responses'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

class StoryPackageSummary {
  final String id;
  final String status;
  final String childProfileId;
  final String languageLocale;
  final String title;
  final String speakingGoal;
  final String targetPhrase;
  final int sceneCount;
  final bool hasMission;
  final bool hasHandoff;
  final String validationLanguage;
  final String validationSafety;
  final String createdAt;
  /// Cover illustration URL (first scene's Wanx illustration).
  final String coverIllustrationUrl;

  StoryPackageSummary({
    required this.id,
    required this.status,
    required this.childProfileId,
    this.languageLocale = 'ta-SG',
    this.title = '',
    this.speakingGoal = '',
    this.targetPhrase = '',
    this.sceneCount = 0,
    this.hasMission = false,
    this.hasHandoff = false,
    this.validationLanguage = 'pending',
    this.validationSafety = 'pending',
    this.createdAt = '',
    this.coverIllustrationUrl = '',
  });

  factory StoryPackageSummary.fromJson(Map<String, dynamic> json) =>
      StoryPackageSummary(
        id: json['id'] as String,
        status: json['status'] as String,
        childProfileId: json['child_profile_id'] as String,
        languageLocale: json['language_locale'] as String? ?? 'ta-SG',
        title: json['title'] as String? ?? '',
        speakingGoal: json['speaking_goal'] as String? ?? '',
        targetPhrase: json['target_phrase'] as String? ?? '',
        sceneCount: json['scene_count'] as int? ?? 0,
        hasMission: json['has_mission'] as bool? ?? false,
        hasHandoff: json['has_handoff'] as bool? ?? false,
        validationLanguage: json['validation_language'] as String? ?? 'pending',
        validationSafety: json['validation_safety'] as String? ?? 'pending',
        createdAt: json['created_at'] as String? ?? '',
      );

  String get localeLabel {
    switch (languageLocale) {
      case 'ta-SG':
        return 'Tamil';
      case 'zh-SG':
        return 'Chinese';
      case 'ms-SG':
        return 'Malay';
      default:
        return languageLocale;
    }
  }
}

/// F4 — one pre-generated audio asset from the media manifest.
/// Empty [url] means parent-read fallback (adult reads the text aloud).
class MediaAsset {
  final String id;
  final String kind; // scene | mission | handoff
  final int sceneIndex;
  final String url;
  final int durationMs;
  final String ttsProvider;
  final String text;
  final String textTargetLang;

  MediaAsset({
    required this.id,
    required this.kind,
    this.sceneIndex = -1,
    this.url = '',
    this.durationMs = 0,
    this.ttsProvider = 'text_only',
    this.text = '',
    this.textTargetLang = '',
  });

  bool get hasAudio => url.isNotEmpty;

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        sceneIndex: json['scene_index'] as int? ?? -1,
        url: json['url'] as String? ?? '',
        durationMs: json['duration_ms'] as int? ?? 0,
        ttsProvider: json['tts_provider'] as String? ?? 'text_only',
        text: json['text'] as String? ?? '',
        textTargetLang: json['text_target_lang'] as String? ?? '',
      );
}

/// F4 — a real approved scene for child-mode playback.
class ApprovedScene {
  final int index;
  /// Chapter name the way a storybook has one — the writer chose it for this
  /// beat, so it is shown above the page instead of "Chapter 2".
  final String title;
  final String titleTargetLang;
  /// The picture for this beat, chosen to match what happens here.
  final String emoji;
  final String narration;
  final String narrationTargetLang;
  final String interactionType; // choice | speak | listen
  final List<String> options;
  final String expectedIntent;
  /// Wanx-generated illustration URL (empty = use emoji fallback).
  final String illustrationUrl;

  /// Progressive generation: pending | generating | ready | failed.
  /// Classic stories are always 'ready'.
  final String status;

  ApprovedScene({
    required this.index,
    this.title = '',
    this.titleTargetLang = '',
    this.emoji = '',
    this.narration = '',
    this.narrationTargetLang = '',
    this.interactionType = 'listen',
    this.options = const [],
    this.expectedIntent = '',
    this.illustrationUrl = '',
    this.status = 'ready',
  });

  bool get isReady => status == 'ready';

  factory ApprovedScene.fromJson(Map<String, dynamic> json) {
    final interaction = json['interaction'] as Map<String, dynamic>? ?? {};
    return ApprovedScene(
      index: json['index'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      titleTargetLang: json['title_target_lang'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      narration: json['narration'] as String? ?? '',
      narrationTargetLang: json['narration_target_lang'] as String? ?? '',
      interactionType: interaction['type'] as String? ?? 'listen',
      options: (interaction['options'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      expectedIntent: interaction['expected_intent'] as String? ?? '',
      illustrationUrl: json['illustration_url'] as String? ?? '',
      status: json['status'] as String? ?? 'ready',
    );
  }
}

/// A "word to learn" — Mina speaks it (vocab_N asset), the child repeats.
class VocabWord {
  final String word; // English
  final String wordTargetLang;
  final String romanised;

  VocabWord({
    required this.word,
    this.wordTargetLang = '',
    this.romanised = '',
  });

  factory VocabWord.fromJson(Map<String, dynamic> json) => VocabWord(
        word: json['word'] as String? ?? '',
        wordTargetLang: json['word_target_lang'] as String? ?? '',
        romanised: json['romanised'] as String? ?? '',
      );
}

/// F4 — the full approved story + media manifest for child mode.
class ApprovedStory {
  final String packageId;
  final String locale;
  final String title;
  final String titleTargetLang;
  final List<ApprovedScene> scenes;
  final String mission;
  final String missionTargetLang;
  final String handoffPrompt;
  final String handoffPromptTargetLang;
  final String handoffResponseSuggestion;
  final String familyVoiceMode; // F9 — confident_speaker | learning_parent
  final String speakingGoal;
  final String targetPhrase;
  final List<String> targetWords;
  final List<VocabWord> vocabulary;
  /// The chant that comes back every scene — the child joins in on it.
  final String refrain;
  final String refrainTargetLang;
  final List<MediaAsset> manifest;

  ApprovedStory({
    required this.packageId,
    this.locale = 'ta-SG',
    this.title = '',
    this.titleTargetLang = '',
    this.scenes = const [],
    this.mission = '',
    this.missionTargetLang = '',
    this.handoffPrompt = '',
    this.handoffPromptTargetLang = '',
    this.handoffResponseSuggestion = '',
    this.familyVoiceMode = 'confident_speaker',
    this.speakingGoal = '',
    this.targetPhrase = '',
    this.targetWords = const [],
    this.vocabulary = const [],
    this.refrain = '',
    this.refrainTargetLang = '',
    this.manifest = const [],
  });

  MediaAsset? assetFor(String id) {
    for (final a in manifest) {
      if (a.id == id) return a;
    }
    return null;
  }

  factory ApprovedStory.fromPackageJson(Map<String, dynamic> pkg) {
    final story = pkg['story'] as Map<String, dynamic>? ?? {};
    final mission = story['room_mission'] as Map<String, dynamic>? ?? {};
    final handoff = story['family_handoff'] as Map<String, dynamic>? ?? {};
    final media = pkg['media'] as Map<String, dynamic>? ?? {};
    final language = pkg['language'] as Map<String, dynamic>? ?? {};
    final familyVoice = pkg['family_voice'] as Map<String, dynamic>? ?? {};
    final plan = pkg['learning_plan'] as Map<String, dynamic>? ?? {};
    return ApprovedStory(
      packageId: pkg['id'] as String? ?? '',
      locale: language['locale'] as String? ?? 'ta-SG',
      title: story['title'] as String? ?? '',
      titleTargetLang: story['title_target_lang'] as String? ?? '',
      scenes: (story['scenes'] as List<dynamic>?)
              ?.map((e) => ApprovedScene.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      mission: mission['instruction'] as String? ?? '',
      missionTargetLang: mission['instruction_target_lang'] as String? ?? '',
      handoffPrompt: handoff['prompt'] as String? ?? '',
      handoffPromptTargetLang:
          handoff['prompt_target_lang'] as String? ?? '',
      handoffResponseSuggestion:
          handoff['response_suggestion'] as String? ?? '',
      familyVoiceMode: familyVoice['mode'] as String? ??
          handoff['mode'] as String? ??
          'confident_speaker',
      speakingGoal: plan['speaking_goal'] as String? ?? '',
      targetPhrase: plan['target_phrase'] as String? ?? '',
      targetWords: (plan['target_words'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      vocabulary: (story['vocabulary'] as List<dynamic>?)
              ?.map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      refrain: story['refrain'] as String? ?? '',
      refrainTargetLang: story['refrain_target_lang'] as String? ?? '',
      manifest: (media['manifest'] as List<dynamic>?)
              ?.map((e) => MediaAsset.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SSEEvent {
  final String type;
  final String agent;
  final double progressPct;
  final String status;
  final String error;
  final String packageId;
  final String question; // F3 — needs_clarification
  // Book engine: how many pages are written so far, out of how many.
  final int cardsReady;
  final int cardsTotal;

  SSEEvent({
    required this.type,
    this.agent = '',
    this.progressPct = 0.0,
    this.status = '',
    this.error = '',
    this.packageId = '',
    this.question = '',
    this.cardsReady = 0,
    this.cardsTotal = 0,
  });

  factory SSEEvent.fromJson(Map<String, dynamic> json) => SSEEvent(
        type: json['type'] as String? ?? '',
        agent: json['agent'] as String? ?? '',
        progressPct: (json['progress_pct'] as num?)?.toDouble() ?? 0.0,
        status: json['status'] as String? ?? '',
        error: json['error'] as String? ?? '',
        packageId: json['package_id'] as String? ?? '',
        question: json['question'] as String? ?? '',
        cardsReady: (json['ready_cards'] as num?)?.toInt() ?? 0,
        cardsTotal: (json['total_cards'] as num?)?.toInt() ?? 0,
      );
}
