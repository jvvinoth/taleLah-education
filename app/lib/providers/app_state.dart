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
    if (_activeProfile == null) return;

    _isGenerating = true;
    _progressPct = 0.0;
    _currentAgent = '';
    _generationStatus = 'Capturing moment...';
    notifyListeners();

    try {
      // 1. Capture moment
      final moment = await api.captureMoment(
        childProfileId: _activeProfile!.id,
        text: text,
      );

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
      notifyListeners();
    } catch (e) {
      _isGenerating = false;
      _generationStatus = 'Error: $e';
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
    notifyListeners();
  }
}
