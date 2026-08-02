/// App-wide state management using Provider.
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/community_event.dart';
import '../models/story_package.dart';
import '../services/api_client.dart';

class AppState extends ChangeNotifier {
  final ApiClient api;

  AppState({required this.api});

  // ── Auth state ────────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  String? _adultId;
  String _displayName = '';
  String _accountEmail = '';
  bool get isLoggedIn => _isLoggedIn;
  String? get adultId => _adultId;
  String get displayName => _displayName;
  String get accountEmail => _accountEmail;

  // ── Child profiles ────────────────────────────────────────────────────
  List<ChildProfile> _profiles = [];
  ChildProfile? _activeProfile;
  List<ChildProfile> get profiles => _profiles;
  ChildProfile? get activeProfile => _activeProfile;

  // ── Current generation ────────────────────────────────────────────────
  bool _isGenerating = false;
  double _progressPct = 0.0;
  String _currentAgent = '';
  String _generationStatus = '';
  bool get isGenerating => _isGenerating;
  double get progressPct => _progressPct;
  String get currentAgent => _currentAgent;
  String get generationStatus => _generationStatus;

  // ── Generated package ─────────────────────────────────────────────────
  StoryPackageSummary? _latestPackage;
  StoryPackageSummary? get latestPackage => _latestPackage;

  // ── Capture/generation failure — the UI must always surface this ────
  String? _captureError;
  String? get captureError => _captureError;
  void clearCaptureError() {
    _captureError = null;
  }

  // ── Approved story + media manifest (F4) ────────────────────────
  ApprovedStory? _approvedStory;
  ApprovedStory? get approvedStory => _approvedStory;

  /// Absolute URL for a manifest-relative media path.
  String mediaUrl(String relativeUrl) => '${api.baseUrl}/$relativeUrl';

  // ── Init ──────────────────────────────────────────────────────────────

  /// Splash gate state — the UI must never spin forever. On failure we
  /// expose [initError] so SplashGate can show a message + Retry button.
  bool _isInitializing = false;
  String? _initError;
  bool get isInitializing => _isInitializing;
  String? get initError => _initError;

  Future<void> initialize() async {
    // Restore a saved session; without one the SplashGate routes to Login.
    _isInitializing = true;
    _initError = null;
    notifyListeners();
    try {
      final hasSession = await api.restoreSession();
      if (!hasSession) {
        _isLoggedIn = false;
        _isInitializing = false;
        notifyListeners();
        return;
      }
      await _enterSession();
    } catch (e) {
      debugPrint('Init error: $e');
      _isInitializing = false;
      if (e is ApiException && e.statusCode == 401) {
        // Stale/expired token — clear it and show Login (not an error).
        await api.clearSession();
        _isLoggedIn = false;
      } else {
        _initError = e is ApiException
            ? e.detail
            : "Can't reach TaleLah right now. Check your connection and try again.";
      }
      notifyListeners();
    }
  }

  /// Session is set on the ApiClient — validate it and load the home data.
  Future<void> _enterSession() async {
    final account = await api.me();
    _adultId = account['id'] as String?;
    _displayName = account['display_name'] as String? ?? '';
    _accountEmail = account['email'] as String? ?? '';
    _isLoggedIn = true;
    notifyListeners();

    _profiles = await api.getProfiles();
    if (_profiles.isNotEmpty) {
      _activeProfile = _profiles.first;
    }
    _isInitializing = false;
    notifyListeners();
  }

  // ── Auth actions (throw ApiException with a friendly detail) ─────────

  Future<void> login({required String email, required String password}) async {
    await api.login(email: email, password: password);
    await _enterSession();
  }

  Future<void> signup({
    required String email,
    required String password,
    required String displayName,
  }) =>
      api.signup(email: email, password: password, displayName: displayName);

  Future<void> verifyEmail({required String email, required String code}) async {
    await api.verifyEmail(email: email, code: code);
    await _enterSession();
  }

  Future<void> forgotPassword(String email) => api.forgotPassword(email);

  Future<void> resendVerificationCode(String email) =>
      api.resendVerificationCode(email);

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await api.resetPassword(email: email, code: code, newPassword: newPassword);
    await _enterSession();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      api.changePassword(
          currentPassword: currentPassword, newPassword: newPassword);

  /// One-tap judge/demo flow — the seeded demo account.
  Future<void> tryDemo() async {
    await api.register(
        email: 'demo@talelah.app', displayName: 'Demo Parent');
    await _enterSession();
  }

  Future<void> logout() async {
    await api.clearSession();
    _isLoggedIn = false;
    _adultId = null;
    _displayName = '';
    _accountEmail = '';
    _profiles = [];
    _activeProfile = null;
    _latestPackage = null;
    _approvedStory = null;
    notifyListeners();
  }

  // ── Profile management ────────────────────────────────────────────────

  Future<ChildProfile> createProfile({
    required String alias,
    required String ageBand,
    String targetLocale = 'ta-SG',
    String homeLanguage = 'en',
  }) async {
    final profile = await api.createProfile(
      alias: alias,
      ageBand: ageBand,
      targetLocale: targetLocale,
      homeLanguage: homeLanguage,
    );
    _profiles.add(profile);
    _activeProfile = profile;
    notifyListeners();
    return profile;
  }

  Future<void> updateProfile(
    String profileId, {
    String? alias,
    String? ageBand,
    String? homeLanguage,
  }) async {
    final updated = await api.updateProfile(
      profileId,
      alias: alias,
      ageBand: ageBand,
      homeLanguage: homeLanguage,
    );
    final i = _profiles.indexWhere((p) => p.id == profileId);
    if (i >= 0) _profiles[i] = updated;
    if (_activeProfile?.id == profileId) _activeProfile = updated;
    notifyListeners();
  }

  /// Upload the kid's photo, then refresh so cards show it immediately.
  Future<void> uploadProfilePhoto({
    required String profileId,
    required List<int> imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    await api.uploadProfilePhoto(
      profileId: profileId,
      imageBytes: imageBytes,
      contentType: contentType,
    );
    _profiles = await api.getProfiles();
    if (_activeProfile != null) {
      _activeProfile = _profiles.firstWhere(
        (p) => p.id == _activeProfile!.id,
        orElse: () => _activeProfile!,
      );
    }
    notifyListeners();
  }

  void selectProfile(ChildProfile profile) {
    _activeProfile = profile;
    notifyListeners();
  }

  // ── Story generation ──────────────────────────────────────────────────

  Future<void> captureAndGenerate({
    required String text,
    String locale = 'ta-SG',
    String engine = 'classic',
  }) async {
    await _captureAndGenerate(
      locale: locale,
      engine: engine,
      capturingStatus: 'Capturing moment...',
      capture: () => api.captureMoment(
        childProfileId: _activeProfile!.id,
        text: text,
      ),
    );
  }

  /// F5 — voice note ≤45 s; backend transcribes, then the same pipeline runs.
  Future<void> captureAndGenerateVoice({
    required List<int> audioBytes,
    String locale = 'ta-SG',
  }) async {
    await _captureAndGenerate(
      locale: locale,
      capturingStatus: 'Listening to your note…',
      capture: () => api.captureMomentVoice(
        childProfileId: _activeProfile!.id,
        audioBytes: audioBytes,
        locale: locale,
      ),
    );
  }

  /// F5 — voice → text only. Auto-detects the spoken language so the parent
  /// can review and edit before generating (does not start the pipeline).
  Future<String> transcribeMoment(List<int> audioBytes) =>
      api.transcribeMoment(audioBytes);

  /// F5 — photo ≤10 MB; Qwen-VL-Max reads it, then the same pipeline runs.
  Future<void> captureAndGeneratePhoto({
    required List<int> imageBytes,
    String contentType = 'image/jpeg',
    String locale = 'ta-SG',
    String engine = 'classic',
  }) async {
    await _captureAndGenerate(
      locale: locale,
      engine: engine,
      capturingStatus: 'Looking at your photo…',
      capture: () => api.captureMomentPhoto(
        childProfileId: _activeProfile!.id,
        imageBytes: imageBytes,
        contentType: contentType,
      ),
    );
  }

  Future<void> _captureAndGenerate({
    required Future<Moment> Function() capture,
    required String locale,
    required String capturingStatus,
    String engine = 'classic',
  }) async {
    if (_activeProfile == null) {
      debugPrint('[TL] _captureAndGenerate: _activeProfile is null, aborting');
      return;
    }
    debugPrint('[TL] _captureAndGenerate: starting, profile=${_activeProfile!.id}, locale=$locale');

    _isGenerating = true;
    _progressPct = 0.0;
    _currentAgent = '';
    _pendingClarification = null;
    _clarifyPackageId = null;
    _captureError = null;
    _generationStatus = capturingStatus;
    notifyListeners();

    try {
      // 1. Capture moment (text / voice / photo)
      debugPrint('[TL] Step 1: Capturing moment...');
      final moment = await capture();
      debugPrint('[TL] Step 1 done: moment_id=${moment.id}');

      _generationStatus = 'Starting generation...';
      notifyListeners();

      // 2. Start async generation
      debugPrint('[TL] Step 2: Starting async generation...');
      final packageId = await api.generatePackageAsync(
        momentId: moment.id,
        locale: locale,
        engine: engine,
      );
      debugPrint('[TL] Step 2 done: packageId=$packageId');

      // 3. Subscribe to SSE events
      _generationStatus = 'Streaming progress...';
      notifyListeners();

      var pipelineError = '';
      await for (final event in api.streamPackageEvents(packageId).timeout(
        const Duration(minutes: 5),
        onTimeout: (sink) {
          // Pipeline took too long — close the stream gracefully.
          sink.close();
        },
      )) {
        _progressPct = event.progressPct;
        _currentAgent = event.agent;

        if (event.type == 'agent_started') {
          _generationStatus = _agentLabel(event.agent);
        } else if (event.type == 'agent_completed') {
          _generationStatus = '${_agentLabel(event.agent)} done';
        } else if (event.type == 'needs_clarification') {
          // F3 — pipeline paused for one parent answer
          _pendingClarification = event.question;
          _clarifyPackageId = packageId;
          _generationStatus = 'One quick question…';
        } else if (event.type == 'generation_complete') {
          _generationStatus = 'Complete!';
        } else if (event.type == 'error') {
          pipelineError = event.error;
        }
        notifyListeners();
      }

      // Pipeline reported failure over SSE — surface it, never end silent.
      if (pipelineError.isNotEmpty) {
        throw ApiException(500, pipelineError);
      }

      // 4. Fetch final package summary
      final detail = await api.getPackageDetail(packageId);
      if (detail['package'] != null) {
        _latestPackage = StoryPackageSummary(
          id: packageId,
          status: detail['package']['status'] ?? 'awaiting_parent',
          childProfileId: _activeProfile!.id,
          title: detail['package']['story']?['title'] ?? '',
          sceneCount: (detail['package']['story']?['scenes'] as List?)?.length ?? 0,
          languageLocale: locale,
          coverIllustrationUrl: _extractCoverIllustration(detail['package']),
        );
      }

      _isGenerating = false;
      _pendingClarification = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[TL] _captureAndGenerate ERROR: $e');
      _isGenerating = false;
      _pendingClarification = null;
      _generationStatus = '';
      // Friendly detail for API errors, generic otherwise — the home
      // screen shows this the moment generation stops.
      _captureError = e is ApiException
          ? e.detail
          : 'Something went wrong — please try again';
      notifyListeners();
    }
  }

  /// Extract the first scene's illustration URL from a package JSON.
  String _extractCoverIllustration(Map<String, dynamic>? pkg) {
    if (pkg == null) return '';
    final scenes = pkg['story']?['scenes'] as List?;
    if (scenes == null || scenes.isEmpty) return '';
    return (scenes[0] as Map<String, dynamic>?)?['illustration_url'] as String? ?? '';
  }

  // ── F3 · needs_clarification ──────────────────────────────────────

  String? _pendingClarification;
  String? _clarifyPackageId;

  /// Non-null while the pipeline is paused waiting for the parent's answer.
  String? get pendingClarification => _pendingClarification;

  /// Send the parent's answer; the paused pipeline resumes over the same SSE stream.
  Future<void> answerClarification(String answer) async {
    final pkgId = _clarifyPackageId;
    if (pkgId == null || answer.trim().isEmpty) return;
    _pendingClarification = null;
    _generationStatus = 'Thanks! Weaving the story…';
    notifyListeners();
    try {
      await api.clarifyPackage(pkgId, answer.trim());
    } catch (e) {
      _generationStatus = '';
      _captureError = e is ApiException
          ? e.detail
          : 'Something went wrong — please try again';
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Sync generation (blocking — simpler, returns when done).
  Future<StoryPackageSummary?> captureAndGenerateSync({
    required String text,
    String locale = 'ta-SG',
  }) async {
    if (_activeProfile == null) return null;

    _isGenerating = true;
    _generationStatus = 'Generating story...';
    notifyListeners();

    try {
      final moment = await api.captureMoment(
        childProfileId: _activeProfile!.id,
        text: text,
      );

      final pkg = await api.generatePackage(momentId: moment.id, locale: locale);
      _latestPackage = pkg;
      _isGenerating = false;
      _generationStatus = 'Done!';
      notifyListeners();
      return pkg;
    } catch (e) {
      _isGenerating = false;
      _generationStatus = 'Error: $e';
      notifyListeners();
      return null;
    }
  }

  String _agentLabel(String agent) {
    switch (agent) {
      case 'moment_lens':
        return '🔍 Understanding moment';
      case 'learning_planner':
        return '📚 Planning learning';
      case 'story_weaver':
        return '📖 Weaving story';
      case 'language_guardian':
        return '🗣️ Translating';
      case 'family_voice_director':
        return '🎙️ Creating audio';
      case 'growth_coach':
        return '🌱 Growth tips';
      default:
        return agent;
    }
  }

  Future<void> approvePackage() async {
    if (_latestPackage == null) return;
    await api.approvePackage(_latestPackage!.id);
    // F4 — approval pre-generates the media manifest; fetch the approved
    // package so child mode can preload every audio asset.
    try {
      final detail = await api.getPackageDetail(_latestPackage!.id);
      final pkg = detail['package'] as Map<String, dynamic>?;
      if (pkg != null) {
        _approvedStory = ApprovedStory.fromPackageJson(pkg);
      }
    } catch (e) {
      debugPrint('Approved story fetch failed: $e');
      _approvedStory = null; // child mode falls back to demo scenes
    }
    notifyListeners();
  }

  /// Load a built-in sample story directly into [approvedStory] — no API
  /// call, no generation wait. The child session falls back to parent-read
  /// mode since sample stories have no audio manifest.
  void loadSampleStory(ApprovedStory story) {
    _approvedStory = story;
    notifyListeners();
  }

  /// Load an already-approved package into [approvedStory] — used by the
  /// story library replay and by review-screen approvals that bypass
  /// [approvePackage].
  Future<bool> loadApprovedStory(String packageId) async {
    try {
      final detail = await api.getPackageDetail(packageId);
      final pkg = detail['package'] as Map<String, dynamic>?;
      if (pkg == null) return false;
      _approvedStory = ApprovedStory.fromPackageJson(pkg);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Approved story load failed: $e');
      return false;
    }
  }

  /// Re-pull the current story and update [approvedStory] if new scene
  /// illustrations have arrived. New-engine art is generated in the background
  /// after approval, so the child screen polls this until the pages fill in.
  /// Returns true when more illustrations are ready than before.
  Future<bool> refreshApprovedStoryArt() async {
    final story = _approvedStory;
    if (story == null) return false;
    try {
      final detail = await api.getPackageDetail(story.packageId);
      final pkg = detail['package'] as Map<String, dynamic>?;
      if (pkg == null) return false;
      final before =
          story.scenes.where((s) => s.illustrationUrl.isNotEmpty).length;
      final refreshed = ApprovedStory.fromPackageJson(pkg);
      final after =
          refreshed.scenes.where((s) => s.illustrationUrl.isNotEmpty).length;
      if (after > before) {
        _approvedStory = refreshed;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Art refresh failed: $e');
    }
    return false;
  }

  // ── F6 · Child session ──────────────────────────────────────────

  String? _sessionId;
  String? get sessionId => _sessionId;

  // F9 — handoff copy from the active language pack (no locale literals here)
  Map<String, dynamic> _familyCopy = {};
  Map<String, dynamic> get familyCopy => _familyCopy;

  // F10 — summary of the finished session (celebration, no grades)
  Map<String, dynamic>? _sessionSummary;
  Map<String, dynamic>? get sessionSummary => _sessionSummary;

  /// Start a backend session for the approved story so the bounded speech
  /// turn can transcribe + match. Failure is non-fatal — the story plays
  /// without a live speech turn (degradation ladder). The response carries
  /// the (possibly self-healed) package — refresh [approvedStory] with it
  /// so the child screen preloads regenerated audio instead of a stale
  /// silent manifest.
  Future<void> startChildSession() async {
    _sessionId = null;
    _sessionSummary = null;
    final story = _approvedStory;
    if (story == null) return;
    try {
      final res = await api.startSession(story.packageId);
      _sessionId = res?['session_id'] as String?;
      final pkg = res?['package'] as Map<String, dynamic>?;
      if (pkg != null) {
        _approvedStory = ApprovedStory.fromPackageJson(pkg);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Session start failed: $e');
    }
    try {
      _familyCopy = await api.getFamilyCopy(story.locale);
    } catch (e) {
      debugPrint('Family copy load failed: $e');
    }
  }

  /// F8/F9 — report a session milestone; never blocks the child.
  Future<void> reportSessionEvent(String kind) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await api.sessionEvent(id, kind);
    } catch (e) {
      debugPrint('Session event failed: $e');
    }
  }

  /// F10 — close the session and keep the summary for the goodbye screen.
  Future<void> completeChildSession() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      _sessionSummary = await api.completeSession(id);
      notifyListeners();
    } catch (e) {
      debugPrint('Session complete failed: $e');
    }
  }

  /// F10 — save the memory; only ever called with an explicit consent tick.
  Future<bool> saveSessionMemory({String note = ''}) async {
    final id = _sessionId;
    if (id == null) return false;
    try {
      await api.saveMemory(sessionId: id, consent: true, note: note);
      return true;
    } catch (e) {
      debugPrint('Memory save failed: $e');
      return false;
    }
  }

  // ── F10 · Progress + saved memories (parent-facing) ───────────

  int _familyMomentsThisWeek = 0;
  int get familyMomentsThisWeek => _familyMomentsThisWeek;
  List<Map<String, dynamic>> _memories = [];
  List<Map<String, dynamic>> get memories => _memories;

  Future<void> refreshProgress() async {
    final profile = _activeProfile;
    if (profile == null) return;
    try {
      _familyMomentsThisWeek = await api.getProgress(profile.id);
      _memories = await api.listMemories(childProfileId: profile.id);
      notifyListeners();
    } catch (e) {
      debugPrint('Progress refresh failed: $e');
    }
  }

  Future<void> deleteMemory(String memoryId) async {
    try {
      await api.deleteMemory(memoryId);
      _memories.removeWhere((m) => m['id'] == memoryId);
      notifyListeners();
    } catch (e) {
      debugPrint('Memory delete failed: $e');
    }
  }

  // ── Community Events ──────────────────────────────────────────────────

  List<CommunityEvent> _events = [];
  bool _eventsLoading = false;
  String? _eventsError;
  List<CommunityEvent> get events => _events;
  bool get eventsLoading => _eventsLoading;
  String? get eventsError => _eventsError;

  Future<void> loadEvents({String language = ''}) async {
    _eventsLoading = true;
    _eventsError = null;
    notifyListeners();
    try {
      _events = await api.getEvents(language: language);
    } catch (e) {
      _eventsError = e is ApiException
          ? e.detail
          : "Couldn't load events — check your connection";
    }
    _eventsLoading = false;
    notifyListeners();
  }
}
