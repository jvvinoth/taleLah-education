/// TaleLah data models matching backend Story Package contract.

class ChildProfile {
  final String id;
  final String alias;
  final String ageBand;
  final String targetLocale;
  final String understandingLevel;
  final String speakingLevel;
  final List<String> interests;

  ChildProfile({
    required this.id,
    required this.alias,
    required this.ageBand,
    this.targetLocale = 'ta-SG',
    this.understandingLevel = 'emerging',
    this.speakingLevel = 'emerging',
    this.interests = const [],
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

class SSEEvent {
  final String type;
  final String agent;
  final double progressPct;
  final String status;
  final String error;
  final String packageId;

  SSEEvent({
    required this.type,
    this.agent = '',
    this.progressPct = 0.0,
    this.status = '',
    this.error = '',
    this.packageId = '',
  });

  factory SSEEvent.fromJson(Map<String, dynamic> json) => SSEEvent(
        type: json['type'] as String? ?? '',
        agent: json['agent'] as String? ?? '',
        progressPct: (json['progress_pct'] as num?)?.toDouble() ?? 0.0,
        status: json['status'] as String? ?? '',
        error: json['error'] as String? ?? '',
        packageId: json['package_id'] as String? ?? '',
      );
}
