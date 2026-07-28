/// App-wide state management using Provider.
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/story_package.dart';
import '../services/api_client.dart';

class AppState extends ChangeNotifier {
  final ApiClient api;

  AppState({required this.api});

  // ── Auth state ────────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  String? _adultId;
  bool get isLoggedIn => _isLoggedIn;
  String? get adultId => _adultId;

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

  // ── Approved story + media manifest (F4) ────────────────────────
  ApprovedStory? _approvedStory;
  ApprovedStory? get approvedStory => _approvedStory;

  /// Absolute URL for a manifest-relative media path.
  String mediaUrl(String relativeUrl) => '${api.baseUrl}/$relativeUrl';

  // ── Init ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // Auto-register a demo user for hackathon
    try {
      final healthOk = await api.checkHealth();
      if (!healthOk) return;
      _adultId = await api.register(
        email: 'demo@talelah.app',
        displayName: 'Demo Parent',
      );
      _isLoggedIn = true;
      notifyListeners();

      // Load existing profiles
      _profiles = await api.getProfiles();
      if (_profiles.isNotEmpty) {
        _activeProfile = _profiles.first;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  // ── Profile management ────────────────────────────────────────────────

  Future<ChildProfile> createProfile({
    required String alias,
    required String ageBand,
    String targetLocale = 'ta-SG',
  }) async {
    final profile = await api.createProfile(
      alias: alias,
      ageBand: ageBand,
      targetLocale: targetLocale,
    );
    _profiles.add(profile);
    _activeProfile = profile;
    notifyListeners();
    return profile;
  }

  void selectProfile(ChildProfile profile) {
    _activeProfile = profile;
    notifyListeners();
  }

  // ── Story generation ──────────────────────────────────────────────────

  Future<void> captureAndGenerate({
    required String text,
    String locale = 'ta-SG',
  }) async {
    await _captureAndGenerate(
      locale: locale,
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

  /// F5 — photo ≤10 MB; Qwen-VL-Max reads it, then the same pipeline runs.
  Future<void> captureAndGeneratePhoto({
    required List<int> imageBytes,
    String contentType = 'image/jpeg',
    String locale = 'ta-SG',
  }) async {
    await _captureAndGenerate(
      locale: locale,
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
  }) async {
    if (_activeProfile == null) return;

    _isGenerating = true;
    _progressPct = 0.0;
    _currentAgent = '';
    _pendingClarification = null;
    _clarifyPackageId = null;
    _generationStatus = capturingStatus;
    notifyListeners();

    try {
      // 1. Capture moment (text / voice / photo)
      final moment = await capture();

      _generationStatus = 'Starting generation...';
      notifyListeners();

      // 2. Start async generation
      final packageId = await api.generatePackageAsync(
        momentId: moment.id,
        locale: locale,
      );

      // 3. Subscribe to SSE events
      _generationStatus = 'Streaming progress...';
      notifyListeners();

      await for (final event in api.streamPackageEvents(packageId)) {
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
          _generationStatus = 'Error: ${event.error}';
        }
        notifyListeners();
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
        );
      }

      _isGenerating = false;
      _pendingClarification = null;
      notifyListeners();
    } catch (e) {
      _isGenerating = false;
      _pendingClarification = null;
      _generationStatus = 'Error: $e';
      notifyListeners();
    }
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
      _generationStatus = 'Error: $e';
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

  // ── F6 · Child session ──────────────────────────────────────────

  String? _sessionId;
  String? get sessionId => _sessionId;

  /// Start a backend session for the approved story so the bounded speech
  /// turn can transcribe + match. Failure is non-fatal — the story plays
  /// without a live speech turn (degradation ladder).
  Future<void> startChildSession() async {
    _sessionId = null;
    final story = _approvedStory;
    if (story == null) return;
    try {
      _sessionId = await api.startSession(story.packageId);
    } catch (e) {
      debugPrint('Session start failed: $e');
    }
  }
}
