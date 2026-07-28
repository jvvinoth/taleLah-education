/// Child Session — premium interactive story playback with narration and choices.
/// F4: plays the real approved story with pre-generated TTS audio (preloaded
/// before the session starts); missing audio → parent-read fallback.
/// F6: bounded child speech turn — record a short clip, backend matches it
/// against the scene's expected intent only; miss 1 → replay slower,
/// miss 2 → picture-choice fallback. Never says "wrong" (AC-04).
/// F7: child-mode lockdown — hold-to-exit gate, blocked back-nav, ≥56dp
/// targets, Mina's 8 states (AC-03). F8: mission wait screen (AC-05).
/// F9: family handoff modes (AC-06). F10: memory consent on goodbye.
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../models/story_package.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/mina.dart';
import 'mission_wait.dart';

class ChildSessionScreen extends StatefulWidget {
  const ChildSessionScreen({super.key});

  @override
  State<ChildSessionScreen> createState() => _ChildSessionScreenState();
}

class _ChildSessionScreenState extends State<ChildSessionScreen> {
  int _currentScene = 0;
  bool _sessionComplete = false;

  // F6 — bounded speech turn state (per scene)
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _autoStopTimer;
  String _speechPhase = 'idle'; // idle|recording|processing|celebrate|retry|fallback
  int _attempt = 1;
  String _feedbackCopy = '';
  List<Map<String, dynamic>> _fallbackOptions = [];

  // F7 — hold-to-exit gate (AC-03): 3 s continuous press opens the parent gate
  Timer? _holdTimer;
  double _holdProgress = 0;

  // F8 — room mission milestone
  bool _missionDone = false;

  // F10 — memory consent on the goodbye screen (default OFF, hard rule)
  bool _memoryConsent = false;
  bool _memorySaved = false;
  bool _savingMemory = false;

  // F4 — real approved story + preloaded audio players (assetId → player)
  ApprovedStory? _story;
  final Map<String, AudioPlayer> _players = {};
  bool _preloading = true;
  double _preloadProgress = 0;
  late List<_DemoScene> _scenes;

  static const _sceneEmojis = ['✨', '🌈', '🌟', '🎈', '🪁', '🎨'];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _story = app.approvedStory;
    _scenes = _buildScenes();
    app.startChildSession(); // F6 — non-fatal if it fails
    _preloadAudio(app);
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _holdTimer?.cancel();
    _recorder.dispose();
    for (final p in _players.values) {
      p.dispose();
    }
    super.dispose();
  }

  /// Real approved scenes when available; demo scenes as the degradation path.
  List<_DemoScene> _buildScenes() {
    final story = _story;
    if (story == null || story.scenes.isEmpty) return _demoScenes;

    final scenes = <_DemoScene>[];
    for (var i = 0; i < story.scenes.length; i++) {
      final s = story.scenes[i];
      final palette = _demoScenes[i % _demoScenes.length];
      final isChoice = s.interactionType == 'choice' && s.options.isNotEmpty;
      scenes.add(_DemoScene(
        title: i == 0 && story.title.isNotEmpty
            ? story.title
            : 'Chapter ${i + 1}',
        narration: s.narrationTargetLang.isNotEmpty
            ? s.narrationTargetLang
            : s.narration,
        english: s.narration,
        emoji: _sceneEmojis[i % _sceneEmojis.length],
        interaction: isChoice ? 'choice' : 'speak',
        prompt: isChoice
            ? 'What do you choose?'
            : 'Your turn — say it out loud!',
        choices: isChoice ? s.options : null,
        gradient: palette.gradient,
        accent: palette.accent,
        assetId: 'scene_${s.index}',
        expectedIntent: s.expectedIntent,
      ));
    }
    if (story.mission.isNotEmpty || story.missionTargetLang.isNotEmpty) {
      final palette = _demoScenes[3];
      scenes.add(_DemoScene(
        title: 'Mission Time!',
        narration: story.missionTargetLang.isNotEmpty
            ? story.missionTargetLang
            : story.mission,
        english: story.mission,
        emoji: '🎯',
        interaction: 'mission',
        prompt: story.mission,
        gradient: palette.gradient,
        accent: palette.accent,
        assetId: 'mission',
      ));
    }
    if (story.handoffPrompt.isNotEmpty ||
        story.handoffPromptTargetLang.isNotEmpty) {
      final palette = _demoScenes[1];
      scenes.add(_DemoScene(
        title: 'Family Time!',
        narration: story.handoffPromptTargetLang.isNotEmpty
            ? story.handoffPromptTargetLang
            : story.handoffPrompt,
        english: story.handoffPrompt,
        emoji: '👨‍👩‍👧',
        interaction: 'handoff',
        prompt: story.handoffPrompt,
        gradient: palette.gradient,
        accent: palette.accent,
        assetId: 'handoff',
      ));
    }
    return scenes;
  }

  /// F4 — preload every manifest audio asset before the session starts.
  Future<void> _preloadAudio(AppState app) async {
    final story = _story;
    final audioAssets =
        story?.manifest.where((a) => a.hasAudio).toList() ?? [];
    if (audioAssets.isEmpty) {
      setState(() => _preloading = false);
      return;
    }
    var done = 0;
    for (final asset in audioAssets) {
      final player = AudioPlayer();
      try {
        await player
            .setSourceUrl(app.mediaUrl(asset.url))
            .timeout(const Duration(seconds: 12));
        _players[asset.id] = player;
      } catch (_) {
        // This asset falls back to parent-read (text + English).
        player.dispose();
      }
      done++;
      if (mounted) {
        setState(() => _preloadProgress = done / audioAssets.length);
      }
    }
    if (!mounted) return;
    setState(() => _preloading = false);
    _playScene(0);
  }

  bool _hasAudio(_DemoScene scene) =>
      scene.assetId != null && _players.containsKey(scene.assetId);

  Future<void> _playScene(int index) async {
    for (final p in _players.values) {
      p.stop();
    }
    final assetId = _scenes[index].assetId;
    final player = assetId == null ? null : _players[assetId];
    if (player == null) return;
    try {
      await player.setPlaybackRate(1.0);
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {
      // Autoplay may be blocked until first tap — the LISTEN chip covers it.
    }
  }

  // ── F6 — bounded speech turn ─────────────────────────────────────────

  Future<void> _onMicTap() async {
    if (_speechPhase == 'recording') {
      await _stopAndSubmit();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _celebrateLocally(); // no mic → story never blocks
        return;
      }
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: 'clip.wav', // ignored on web (blob URL)
      );
      if (!mounted) return;
      setState(() => _speechPhase = 'recording');
      _autoStopTimer = Timer(const Duration(seconds: 6), _stopAndSubmit);
    } catch (_) {
      _celebrateLocally();
    }
  }

  Future<void> _stopAndSubmit() async {
    _autoStopTimer?.cancel();
    if (_speechPhase != 'recording') return;
    final app = context.read<AppState>();
    setState(() => _speechPhase = 'processing');
    try {
      final path = await _recorder.stop();
      final sessionId = app.sessionId;
      if (path == null || sessionId == null) {
        _celebrateLocally();
        return;
      }
      final bytes = await http.readBytes(Uri.parse(path));
      final result = await app.api.speechTurn(
        sessionId: sessionId,
        audioBytes: bytes,
        expectedIntent: _scenes[_currentScene].expectedIntent ?? '',
        attempt: _attempt,
      );
      if (!mounted) return;
      _handleSpeechResult(result);
    } catch (_) {
      _celebrateLocally();
    }
  }

  void _handleSpeechResult(Map<String, dynamic> r) {
    final action = r['next_action'] as String? ?? 'celebrate';
    if (action == 'retry_slower') {
      setState(() {
        _speechPhase = 'retry';
        _attempt = (r['attempt'] as int? ?? _attempt) + 1;
        _feedbackCopy =
            r['encourage_copy'] as String? ?? 'மீண்டும் சொல்லலாம்! 💪';
      });
      _playSceneSlow();
    } else if (action == 'picture_choice') {
      final options = (r['fallback_options'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (options.isEmpty) {
        _celebrateLocally();
        return;
      }
      setState(() {
        _speechPhase = 'fallback';
        _fallbackOptions = options;
      });
    } else {
      setState(() {
        _speechPhase = 'celebrate';
        _feedbackCopy = r['celebration_copy'] as String? ?? 'அருமை! 🎉';
      });
    }
  }

  Future<void> _chooseFallback(Map<String, dynamic> option) async {
    final app = context.read<AppState>();
    setState(() => _speechPhase = 'processing');
    var copy = 'அருமை! (Super!) 🎉';
    try {
      final sessionId = app.sessionId;
      if (sessionId != null) {
        final r = await app.api
            .speechFallback(sessionId, option['word'] as String? ?? '');
        copy = r['celebration_copy'] as String? ?? copy;
      }
    } catch (_) {
      // Any tap celebrates regardless — the story never blocks.
    }
    if (!mounted) return;
    setState(() {
      _speechPhase = 'celebrate';
      _feedbackCopy = copy;
    });
  }

  void _celebrateLocally() {
    if (!mounted) return;
    setState(() {
      _speechPhase = 'celebrate';
      _feedbackCopy = 'அருமை! (Super!) 🎉';
    });
  }

  /// Miss 1 → replay the scene narration a little slower (AC-04 ladder).
  Future<void> _playSceneSlow() async {
    final assetId = _scenes[_currentScene].assetId;
    final player = assetId == null ? null : _players[assetId];
    if (player == null) return;
    try {
      await player.setPlaybackRate(0.8);
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {}
  }

  void _resetSpeechState() {
    _autoStopTimer?.cancel();
    _recorder.stop().catchError((_) => null);
    _speechPhase = 'idle';
    _attempt = 1;
    _feedbackCopy = '';
    _fallbackOptions = [];
  }

  // ── F7 · child-mode lockdown (AC-03) ──────────────────────

  /// Reduced motion — respect MediaQuery.disableAnimations.
  Duration _anim(int ms) => MediaQuery.of(context).disableAnimations
      ? Duration.zero
      : Duration(milliseconds: ms);

  void _startHold(PointerDownEvent _) {
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() => _holdProgress = (t.tick * 100) / 3000);
      if (_holdProgress >= 1.0) {
        t.cancel();
        setState(() => _holdProgress = 0);
        _openParentGate();
      }
    });
  }

  void _endHold([PointerEvent? _]) {
    _holdTimer?.cancel();
    if (_holdProgress > 0 && mounted) {
      setState(() => _holdProgress = 0);
    }
  }

  /// The gate a grown-up reaches after 3 s of holding — exit or skip.
  void _openParentGate() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '👋 Grown-ups only',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TColors.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _gateAction(sheetCtx, Icons.logout_rounded,
                  'Exit child mode', TColors.coral, () {
                Navigator.pop(sheetCtx);
                Navigator.pop(context);
              }),
              const SizedBox(height: 10),
              _gateAction(sheetCtx, Icons.fast_forward_rounded,
                  'Skip family mission', TColors.tealDeep, () {
                Navigator.pop(sheetCtx);
                _skipMission();
              }),
              const SizedBox(height: 10),
              _gateAction(sheetCtx, Icons.auto_stories_rounded,
                  'Stay in the story', TColors.ink,
                  () => Navigator.pop(sheetCtx)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gateAction(BuildContext sheetCtx, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// F8 — parent-skip from the hold gate: the mission never blocks anyone.
  void _skipMission() {
    setState(() => _missionDone = true);
    if (_scenes[_currentScene].interaction == 'mission') {
      _nextScene();
    }
  }

  // ── F8 · room mission (AC-05) ───────────────────────────

  Future<void> _startMission(_DemoScene scene) async {
    final app = context.read<AppState>();
    for (final p in _players.values) {
      p.stop();
    }
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MissionWaitScreen(
          missionText: scene.narration,
          missionEnglish: scene.english,
        ),
      ),
    );
    if (done == true && mounted) {
      setState(() => _missionDone = true);
      app.reportSessionEvent('mission_completed');
    }
  }

  // ── F9 · family handoff (AC-06) ──────────────────────────

  void _completeHandoff() {
    context.read<AppState>().reportSessionEvent('handoff_completed');
    _nextScene();
  }

  // ── F10 · session summary + memory consent ───────────────────

  void _finishSession() {
    for (final p in _players.values) {
      p.stop();
    }
    setState(() => _sessionComplete = true);
    context.read<AppState>().completeChildSession();
  }

  Future<void> _saveMemory() async {
    if (!_memoryConsent || _savingMemory) return;
    setState(() => _savingMemory = true);
    final ok = await context.read<AppState>().saveSessionMemory();
    if (!mounted) return;
    setState(() {
      _savingMemory = false;
      _memorySaved = ok;
    });
  }

  /// F7 — Mina reacts to what the child is doing (8 states, no more).
  MinaState _minaState(_DemoScene scene) {
    switch (_speechPhase) {
      case 'recording':
        return MinaState.listening;
      case 'processing':
        return MinaState.thinking;
      case 'retry':
      case 'fallback':
        return MinaState.encouraging;
      case 'celebrate':
        return MinaState.celebrating;
    }
    if (scene.interaction == 'mission') return MinaState.waiting;
    if (scene.interaction == 'speak') return MinaState.demonstrating;
    return MinaState.idle;
  }

  // Demo scenes for Sprint 1 shell (will be replaced by real data)
  final List<_DemoScene> _demoScenes = [
    _DemoScene(
      title: 'The Red Train',
      narration: 'ஒரு நாள், அருண் சிவப்பு ரயிலை பார்த்தான்!',
      english: 'One day, Arun saw a red train!',
      emoji: '🚂',
      interaction: 'speak',
      prompt: 'Can you say "சிவப்பு" (sivappu — red)?',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFCEBDF), Color(0xFFFBEFE4), Color(0xFFFDF4E9)],
      ),
      accent: TColors.coral,
    ),
    _DemoScene(
      title: 'At the Station',
      narration: 'ரயில் நிலையத்தில் அருண் காத்திருந்தான்.',
      english: 'Arun waited at the station.',
      emoji: '🚉',
      interaction: 'choice',
      prompt: 'What color is the train?',
      choices: ['🔴 Red (சிவப்பு)', '🔵 Blue (நீலம்)'],
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE0F2F0), Color(0xFFEBF7F3), Color(0xFFF2FAF6)],
      ),
      accent: TColors.teal,
    ),
    _DemoScene(
      title: 'The Journey',
      narration: 'ரயில் வேகமாக சென்றது! மஞ்சள் பூக்கள் தெரிந்தன.',
      english: 'The train went fast! Yellow flowers were visible.',
      emoji: '🌻',
      interaction: 'speak',
      prompt: 'Say "மஞ்சள்" (manjal — yellow)!',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFBF0D2), Color(0xFFFBEFDD), Color(0xFFFDF7E4)],
      ),
      accent: TColors.gold,
    ),
    _DemoScene(
      title: 'Mission Time!',
      narration: 'உன் அறையில் சிவப்பு பொருள் கண்டுபிடி!',
      english: 'Find something RED in your room!',
      emoji: '🎯',
      interaction: 'mission',
      prompt: 'Go find something red and show it to Amma/Appa!',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE2F3EA), Color(0xFFE9F7EF), Color(0xFFF1FBF4)],
      ),
      accent: TColors.teal,
    ),
    _DemoScene(
      title: 'Family Time!',
      narration: 'கதையைப் பற்றி குடும்பத்திடம் கேளு!',
      english: 'Ask your family about the story!',
      emoji: '👨‍👩‍👧',
      interaction: 'handoff',
      prompt: 'Ask the child what colour the train was.',
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE0F2F0), Color(0xFFEBF7F3), Color(0xFFF2FAF6)],
      ),
      accent: TColors.teal,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (_sessionComplete) {
      return _buildCompleteScreen(app);
    }

    if (_preloading) {
      return _buildPreloadScreen();
    }

    final scene = _scenes[_currentScene];
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnimatedContainer(
      duration: _anim(400),
      decoration: BoxDecoration(gradient: scene.gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // AC-03 — system back never exits child mode; only the hold gate does.
        body: PopScope(
            canPop: false,
            child: Column(
          children: [
            // Top bar — hold-to-exit gate + progress dots
            Padding(
              padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 0),
              child: Row(
                children: [
                  _holdExitButton(),
                  const Spacer(),
                  ...List.generate(_scenes.length, (i) {
                    final active = i == _currentScene;
                    final done = i < _currentScene;
                    return AnimatedContainer(
                      duration: _anim(300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? scene.accent
                            : done
                                ? scene.accent.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    );
                  }),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: TShadows.card,
                    ),
                    child: Text(
                      '${_currentScene + 1}/${_scenes.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: TColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scene content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Big emoji in soft bubble
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scene.accent.withValues(alpha: 0.25),
                            blurRadius: 40,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(scene.emoji,
                            style: const TextStyle(fontSize: 64)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Scene title
                    Text(
                      scene.title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: TColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),

                    // Glass narration card
                    TCard(
                      radius: 26,
                      padding: const EdgeInsets.all(22),
                      shadows: TShadows.soft,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _hasAudio(scene)
                                    ? () => _playScene(_currentScene)
                                    : null,
                                // Padding grows the hit area to ≥56 dp
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 17),
                                  decoration: BoxDecoration(
                                    color: _hasAudio(scene)
                                        ? TColors.mist
                                        : TColors.lemon,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _hasAudio(scene)
                                        ? '🔊 LISTEN'
                                        : '📖 READ ALOUD',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _hasAudio(scene)
                                          ? TColors.tealDeep
                                          : TColors.goldDeep,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            scene.narration,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                              color: TColors.ink,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            scene.english,
                            style: const TextStyle(
                              fontSize: 13,
                              color: TColors.inkFaint,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // F7 — Mina reacts to the child (8 states)
                    Mina(state: _minaState(scene), size: 56),
                    const SizedBox(height: 14),

                    // Interaction area
                    _buildInteraction(scene),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPad + 20),
              child: Row(
                children: [
                  if (_currentScene > 0)
                    _roundButton(
                      Icons.arrow_back_rounded,
                      onTap: () {
                        setState(() {
                          _currentScene--;
                          _resetSpeechState();
                        });
                        _playScene(_currentScene);
                      },
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _nextScene,
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        gradient: _currentScene == _scenes.length - 1
                            ? TGradients.mint
                            : TGradients.coral,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _currentScene == _scenes.length - 1
                            ? [
                                BoxShadow(
                                  color: TColors.teal.withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ]
                            : TShadows.glowCoral,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentScene == _scenes.length - 1
                                ? 'Finish!'
                                : 'Next',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _currentScene == _scenes.length - 1
                                ? Icons.celebration_rounded
                                : Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        )),
      ),
    );
  }

  /// F7 — press-and-hold 3 s to reach the parent gate. A quick tap does
  /// nothing — the child cannot leave (or skip) by accident.
  Widget _holdExitButton() {
    return Listener(
      onPointerDown: _startHold,
      onPointerUp: _endHold,
      onPointerCancel: _endHold,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: TShadows.card,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_holdProgress > 0)
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  value: _holdProgress.clamp(0.0, 1.0),
                  strokeWidth: 3.5,
                  color: TColors.coral,
                  backgroundColor: TColors.mist,
                ),
              ),
            const Icon(Icons.lock_outline_rounded,
                color: TColors.ink, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, // AC-03 — child touch targets ≥56 dp
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: TShadows.card,
        ),
        child: Icon(icon, color: TColors.ink, size: 22),
      ),
    );
  }

  Widget _buildInteraction(_DemoScene scene) {
    switch (scene.interaction) {
      case 'speak':
        return _buildSpeechTurn(scene);

      case 'choice':
        return Column(
          children: [
            Text(
              scene.prompt,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: TColors.inkSoft,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ...?scene.choices?.map(
              (choice) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: GestureDetector(
                  onTap: _nextScene,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: TShadows.card,
                      border: Border.all(
                        color: scene.accent.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      choice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: TColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

      case 'mission':
        return TCard(
          gradient: TGradients.night,
          radius: 26,
          padding: const EdgeInsets.all(24),
          shadows: TShadows.glowTeal,
          child: Column(
            children: [
              const Text('🧭', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                scene.prompt,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_missionDone)
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🎉', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text(
                        'Mission done — well done!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _startMission(scene),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🎯', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 8),
                        Text(
                          'Start the Mission',
                          style: TextStyle(
                            color: TColors.tealDeep,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
            ],
          ),
        );

      case 'handoff':
        return _buildHandoff(scene);

      default:
        return const SizedBox.shrink();
    }
  }

  /// F9 — family handoff (AC-06). Confident speaker: phrase + prompt,
  /// minimal chrome. Learning parent: the coach card — script, audio,
  /// meaning and tip on one screen. Copy comes from the pack.
  Widget _buildHandoff(_DemoScene scene) {
    final app = context.watch<AppState>();
    final copy = app.familyCopy;
    final learning =
        (_story?.familyVoiceMode ?? '') == 'learning_parent';
    final response = _story?.handoffResponseSuggestion ?? '';
    String packCopy(String key, String fallback) {
      final v = copy[key] as String? ?? '';
      return v.isNotEmpty ? v : fallback;
    }

    return TCard(
      radius: 26,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Text(
            packCopy('say_together', '👨‍👩‍👧 Say it together!'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (learning) ...[
            // Coach card — everything a learning parent needs, one screen.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TColors.lemon,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                packCopy('learning_intro',
                    'Follow along — script, sound and meaning below.'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TColors.goldDeep,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            if (_hasAudio(scene))
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _playScene(_currentScene),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: TColors.mist,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volume_up_rounded,
                          color: TColors.tealDeep, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Hear it first',
                        style: TextStyle(
                          color: TColors.tealDeep,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TColors.blush,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                packCopy('coach_tip',
                    'Listen once, then say it slowly together.'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TColors.ink,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ] else
            Text(
              packCopy('confident_hint',
                  'Ask away and let the story do the rest.'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TColors.inkFaint,
              ),
              textAlign: TextAlign.center,
            ),
          if (response.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TColors.mint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    packCopy('response_label', 'If they answer, you can say'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: TColors.tealDeep,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    response,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TColors.ink,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _completeHandoff,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: TGradients.mint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text(
                  'We did it! 🙌',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// F6 — the bounded speech turn UI, phased by _speechPhase.
  Widget _buildSpeechTurn(_DemoScene scene) {
    // Celebration chip — matched, fallback tap, or graceful degradation.
    if (_speechPhase == 'celebrate') {
      return TCard(
        radius: 26,
        padding: const EdgeInsets.all(22),
        shadows: TShadows.glowTeal,
        child: Column(
          children: [
            const Text('🎉', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text(
              _feedbackCopy,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: TColors.ink,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Picture-choice fallback — second miss; any tap celebrates.
    if (_speechPhase == 'fallback') {
      return Column(
        children: [
          const Text(
            'Tap the word you like! 👇',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: TColors.inkSoft,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ..._fallbackOptions.map(
            (o) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: GestureDetector(
                onTap: () => _chooseFallback(o),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: TShadows.card,
                    border: Border.all(
                      color: scene.accent.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        o['word'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: TColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${o['romanised'] ?? ''} · ${o['english'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: TColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // idle | recording | processing | retry — mic ring with status copy.
    final recording = _speechPhase == 'recording';
    final processing = _speechPhase == 'processing';
    return Column(
      children: [
        Text(
          _speechPhase == 'retry' && _feedbackCopy.isNotEmpty
              ? _feedbackCopy
              : scene.prompt,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: TColors.inkSoft,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Gradient mic ring
        GestureDetector(
          onTap: processing ? null : _onMicTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: recording ? TGradients.coral : TGradients.hero,
              shape: BoxShape.circle,
              boxShadow:
                  recording ? TShadows.glowCoral : TShadows.glowTeal,
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: processing
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Icon(
                      recording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          recording
              ? 'Listening… tap when done'
              : processing
                  ? 'One moment…'
                  : _speechPhase == 'retry'
                      ? 'Listen again, then tap to speak'
                      : 'Tap to speak',
          style: const TextStyle(
            color: TColors.inkFaint,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  void _nextScene() {
    if (_currentScene < _scenes.length - 1) {
      setState(() {
        _currentScene++;
        _resetSpeechState();
      });
      _playScene(_currentScene);
    } else {
      _finishSession();
    }
  }

  Widget _buildPreloadScreen() {
    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: PopScope(
          canPop: false, // AC-03 — blocked during preload too
          child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Mina(state: MinaState.thinking, size: 96),
                const SizedBox(height: 24),
                const Text(
                  'Getting your story ready…',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: TColors.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Loading every sound so nothing has to wait',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TColors.inkSoft,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _preloadProgress > 0 ? _preloadProgress : null,
                    minHeight: 8,
                    backgroundColor: TColors.mist,
                    color: TColors.teal,
                  ),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }

  Widget _buildCompleteScreen(AppState app) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final summary = app.sessionSummary;
    final targetPhrase = summary?['target_phrase'] as String? ?? '';
    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // AC-03 — the goodbye screen still blocks system back; the big
        // button below is the only exit.
        body: PopScope(
          canPop: false,
          child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(28, 24, 28, bottomPad + 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Mina(state: MinaState.goodbye, size: 120),
                  const SizedBox(height: 24),
                  const Text(
                    'Great job today!',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: TColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${app.activeProfile?.alias ?? "Little one"} learned new Tamil words!',
                    style: const TextStyle(
                      fontSize: 15,
                      color: TColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // F10 — celebration, no grades: what happened, not a score.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _statChip('🗣️', 'Spoke up', TColors.peach),
                      _statChip('🎯',
                          _missionDone ? 'Mission done' : 'Mission try',
                          TColors.mint),
                      _statChip('👨‍👩‍👧', 'Family moment', TColors.mist),
                    ],
                  ),
                  if (targetPhrase.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    TCard(
                      radius: 24,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const Text(
                            "🌟 TODAY'S PHRASE",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: TColors.inkFaint,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            targetPhrase,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: TColors.ink,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  // F10 — memory consent: explicit tick, default OFF.
                  TCard(
                    radius: 24,
                    padding: const EdgeInsets.all(18),
                    child: _memorySaved
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('📖', style: TextStyle(fontSize: 20)),
                              SizedBox(width: 8),
                              Text(
                                'Memory saved for your family',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: TColors.tealDeep,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() =>
                                    _memoryConsent = !_memoryConsent),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Checkbox(
                                        value: _memoryConsent,
                                        activeColor: TColors.teal,
                                        onChanged: (v) => setState(() =>
                                            _memoryConsent = v ?? false),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Save this story as a family memory. '
                                        'Nothing is kept without this tick.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: TColors.inkSoft,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _memoryConsent ? _saveMemory : null,
                                child: Container(
                                  height: 48,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: _memoryConsent
                                        ? TColors.tealDeep
                                        : TColors.mist,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Center(
                                    child: _savingMemory
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            'Save memory',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: _memoryConsent
                                                  ? Colors.white
                                                  : TColors.inkFaint,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  TCard(
                    radius: 24,
                    padding: const EdgeInsets.all(20),
                    child: const Column(
                      children: [
                        Text(
                          '🌱 NEXT TIME, TRY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TColors.inkFaint,
                            letterSpacing: 1.0,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Describe the color of your favorite toy in Tamil!',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TColors.ink,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 58,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: TGradients.coral,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: TShadows.glowCoral,
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.home_rounded,
                                color: Colors.white, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Back to Home',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )),
      ),
    );
  }

  Widget _statChip(String emoji, String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoScene {
  final String title;
  final String narration;
  final String english;
  final String emoji;
  final String interaction;
  final String prompt;
  final List<String>? choices;
  final Gradient gradient;
  final Color accent;
  final String? assetId; // F4 — media manifest asset for this scene
  final String? expectedIntent; // F6 — the only intent the matcher may score

  const _DemoScene({
    required this.title,
    required this.narration,
    required this.english,
    required this.emoji,
    required this.interaction,
    required this.prompt,
    this.choices,
    required this.gradient,
    required this.accent,
    this.assetId,
    this.expectedIntent,
  });
}
