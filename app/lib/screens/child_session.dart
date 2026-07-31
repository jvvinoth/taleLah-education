/// Child Session — premium interactive story playback with narration and choices.
/// F4: plays the real approved story with pre-generated TTS audio (preloaded
/// before the session starts); missing audio → parent-read fallback.
/// F6: bounded child speech turn — hands-free: Mina listens on her own
/// after the narration, voice-activity detection closes the turn on
/// silence, the backend matches the clip against the scene's expected
/// intent only; miss 1 → replay slower, miss 2 → picture-choice fallback.
/// Never says "wrong" (AC-04).
/// F7: child-mode lockdown — hold-to-exit gate, blocked back-nav, ≥56dp
/// targets, Mina's 8 states (AC-03). F8: mission wait screen (AC-05).
/// F9: family handoff modes (AC-06). F10: memory consent on goodbye.
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story_package.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/live_mic.dart';
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

  // F6 — bounded speech turn state (per scene). Hands-free 1-1 loop:
  // Mina narrates → listens (VAD ends the turn on silence — no stop
  // button) → thinks → answers → listens again.
  final LiveMic _liveMic = LiveMic();
  Timer? _autoListenTimer;
  // idle|listening|processing|nudge|celebrate|retry|fallback
  String _speechPhase = 'idle';
  int _attempt = 1;
  String _feedbackCopy = '';
  List<Map<String, dynamic>> _fallbackOptions = [];

  // Story control — Mina reads (default) or the child reads by themself
  // ("I read": Mina listens to the reading and appreciates it); narration
  // can be paused mid-scene like a parent pausing the book.
  bool _iRead = false;
  bool _readingTurn = false;
  bool _narrationPaused = false;

  // Narration speed — playback multiplier over the storyteller-paced audio
  // (generated at ~0.8 pace). Parents pick what their child follows best.
  double _paceRate = 1.0;
  // How fast she tells it is a grown-up's dial, not a child's, so it stays
  // folded away until someone asks for it.
  bool _showPace = false;

  // Which way the last page turn went, so the new page slides in from the
  // side the child pushed from.
  bool _pageForward = true;

  // Words to learn — tap a chip: Mina says the word, the child repeats,
  // and Mina TUTORS the attempt: she hears it, cross-checks it against the
  // letters of the word, and answers what was actually said. No stock
  // praise — a near miss names the one sound to fix and models it again.
  int _vocabActive = -1; // index into story.vocabulary
  // idle | speaking | listening | thinking | coach | celebrate
  String _vocabPhase = 'idle';
  String _vocabVerdict = ''; // perfect | close | different | unclear
  String _vocabFeedback = ''; // Mina's answer to THIS attempt
  String _vocabFocus = ''; // the one syllable worth another go
  int _vocabAttempt = 0;
  static const _vocabMaxTries = 3;

  // Coaching lines are composed per attempt, so they can't come from the
  // pre-generated manifest — they're synthesized on demand and played here.
  final AudioPlayer _livePlayer = AudioPlayer();

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
    _startAndPreload(app);
  }

  /// F6 + F4 — start the backend session first: its response carries the
  /// self-healed manifest (audio regenerated if approval-time TTS failed),
  /// so preloading must run on the refreshed story, not the stale snapshot.
  Future<void> _startAndPreload(AppState app) async {
    await app.startChildSession(); // non-fatal if it fails
    if (!mounted) return;
    final refreshed = app.approvedStory;
    if (refreshed != null && !identical(refreshed, _story)) {
      setState(() {
        _story = refreshed;
        _scenes = _buildScenes();
      });
    }
    _preloadAudio(app);
  }

  @override
  void dispose() {
    _autoListenTimer?.cancel();
    _holdTimer?.cancel();
    _liveMic.dispose();
    _livePlayer.dispose();
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
      // The writer named this chapter and chose its picture, so use theirs.
      // Home-language title first — it sits above home-language narration.
      final chapter = s.titleTargetLang.isNotEmpty
          ? s.titleTargetLang
          : s.title.isNotEmpty
              ? s.title
              : i == 0 && story.title.isNotEmpty
                  ? story.title
                  : 'Chapter ${i + 1}';
      scenes.add(_DemoScene(
        title: chapter,
        kicker: 'Chapter ${i + 1}',
        narration: s.narrationTargetLang.isNotEmpty
            ? s.narrationTargetLang
            : s.narration,
        english: s.narration,
        emoji: s.emoji.isNotEmpty
            ? s.emoji
            : _sceneEmojis[i % _sceneEmojis.length],
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
        kicker: 'Mission',
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
        kicker: 'Family',
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
        // Keep the source loaded across stop() calls — the default
        // ReleaseMode.release drops it, and a later seek()/resume() on a
        // source-less player hangs forever (web).
        await player.setReleaseMode(ReleaseMode.stop);
        await player
            .setSourceUrl(app.mediaUrl(asset.url))
            .timeout(const Duration(seconds: 12));
        _players[asset.id] = player;
      } catch (e) {
        // This asset falls back to parent-read (text + English).
        debugPrint('Preload failed for ${asset.id}: $e');
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

  bool _isStoryScene(int index) =>
      _scenes[index].assetId?.startsWith('scene_') ?? false;

  /// Backend scene index behind this card ('scene_N' → N); null for
  /// mission/handoff/demo cards.
  int? _storySceneIndex(int index) {
    final assetId = _scenes[index].assetId;
    if (assetId == null || !assetId.startsWith('scene_')) return null;
    return int.tryParse(assetId.substring('scene_'.length));
  }

  Future<void> _playScene(int index) async {
    if (_narrationPaused) setState(() => _narrationPaused = false);
    if (_iRead && _isStoryScene(index)) {
      // "I read" — the child reads this scene aloud; Mina just listens.
      for (final p in _players.values) {
        p.stop();
      }
      _scheduleReading(index);
      return;
    }
    await _playNarration(index);
  }

  Future<void> _playNarration(int index) async {
    for (final p in _players.values) {
      p.stop();
    }
    final assetId = _scenes[index].assetId;
    final player = assetId == null ? null : _players[assetId];
    if (player == null) {
      // Parent-read fallback — Mina still opens her ears after a beat so
      // the conversation loop survives the no-audio path.
      _scheduleAutoListen(index, delay: const Duration(seconds: 3));
      return;
    }
    try {
      await player.setPlaybackRate(_paceRate);
      // Web: the seek-complete event may never fire (e.g. already at 0) —
      // never let it stall the narration.
      await player
          .seek(Duration.zero)
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      await player.resume();
      // Half-duplex conversation: the mic opens when Mina stops talking —
      // in "I read" mode she hands the book over instead.
      player.onPlayerComplete.first.then((_) {
        if (_iRead && _isStoryScene(index)) {
          _scheduleReading(index);
        } else {
          _autoListen(index);
        }
      });
    } catch (e) {
      // Autoplay may be blocked until first tap — the LISTEN chip covers it.
      debugPrint('Play failed for scene $index: $e');
    }
  }

  /// Pause / resume the current narration — the "parent pausing the book"
  /// control (≥56 dp chip next to LISTEN).
  Future<void> _togglePause() async {
    final assetId = _scenes[_currentScene].assetId;
    final player = assetId == null ? null : _players[assetId];
    if (player == null) return;
    try {
      if (_narrationPaused) {
        await player.resume();
      } else {
        await player.pause();
      }
      setState(() => _narrationPaused = !_narrationPaused);
    } catch (e) {
      debugPrint('Pause toggle failed: $e');
    }
  }

  /// Mina speaks her feedback out loud (celebrate / encourage /
  /// praise_reading / correction_N — pre-generated pack copy).
  Future<void> _playFeedback(String assetId) async {
    final player = _players[assetId];
    if (player == null) return;
    try {
      for (final p in _players.values) {
        p.stop();
      }
      await player.setPlaybackRate(1.0);
      await player
          .seek(Duration.zero)
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      await player.resume();
    } catch (e) {
      debugPrint('Feedback play failed for $assetId: $e');
    }
  }

  /// Switch who reads the story — Mina (narration + answer turns) or the
  /// child ("I read": Mina listens to the reading and appreciates it).
  void _setIRead(bool value) {
    if (_iRead == value) return;
    for (final p in _players.values) {
      p.stop();
    }
    setState(() {
      _iRead = value;
      _resetSpeechState();
    });
    _playScene(_currentScene);
  }

  // ── F6 — bounded speech turn ─────────────────────────────────────────

  void _scheduleAutoListen(int index, {Duration delay = Duration.zero}) {
    _autoListenTimer?.cancel();
    _autoListenTimer = Timer(delay, () => _autoListen(index));
  }

  /// Hands-free entry — open the mic only if this speak-scene is still
  /// the one on screen and no turn is already underway.
  void _autoListen(int index) {
    if (!mounted || _sessionComplete) return;
    if (_currentScene != index) return;
    if (_scenes[index].interaction != 'speak') return;
    if (_speechPhase != 'idle' && _speechPhase != 'retry') return;
    _startListening();
  }

  Future<void> _startListening() async {
    if (_speechPhase == 'listening' || _speechPhase == 'processing') return;
    _readingTurn = false;
    if (!await _liveMic.hasPermission()) {
      _celebrateLocally(); // no mic → story never blocks
      return;
    }
    if (!mounted) return;
    for (final p in _players.values) {
      p.stop(); // never listen while Mina is speaking
    }
    setState(() => _speechPhase = 'listening');
    final result = await _liveMic.listen(
      maxDuration: const Duration(seconds: 6),
      silenceAfter: const Duration(milliseconds: 900),
      noSpeechTimeout: const Duration(seconds: 8),
    );
    if (!mounted || _speechPhase != 'listening') return;
    if (result == null) {
      setState(() => _speechPhase = 'idle');
      return;
    }
    if (!result.heardSpeech) {
      // Silence — a gentle nudge, never a fail (AC-04).
      setState(() => _speechPhase = 'nudge');
      _playFeedback('encourage');
      return;
    }
    await _submitClip(result.wavBytes);
  }

  // ── "I read" mode — the child reads the scene, Mina listens ────────

  void _scheduleReading(int index) {
    _autoListenTimer?.cancel();
    _autoListenTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _sessionComplete) return;
      if (_currentScene != index || !_iRead) return;
      if (_speechPhase != 'idle' && _speechPhase != 'retry') return;
      _startReading();
    });
  }

  /// Open the mic for a whole-scene reading — longer window than the
  /// one-word answer turn, closed by a longer silence.
  Future<void> _startReading() async {
    if (_speechPhase == 'listening' || _speechPhase == 'processing') return;
    if (!await _liveMic.hasPermission()) return; // reading still works aloud
    if (!mounted) return;
    for (final p in _players.values) {
      p.stop();
    }
    _readingTurn = true;
    setState(() => _speechPhase = 'listening');
    final result = await _liveMic.listen(
      maxDuration: const Duration(seconds: 20),
      silenceAfter: const Duration(milliseconds: 1600),
      noSpeechTimeout: const Duration(seconds: 10),
    );
    if (!mounted || _speechPhase != 'listening') return;
    if (result == null) {
      setState(() => _speechPhase = 'idle');
      return;
    }
    if (!result.heardSpeech) {
      setState(() => _speechPhase = 'nudge');
      _playFeedback('encourage');
      return;
    }
    await _submitReading(result.wavBytes);
  }

  Future<void> _submitReading(List<int> bytes) async {
    final app = context.read<AppState>();
    setState(() => _speechPhase = 'processing');
    try {
      final sessionId = app.sessionId;
      final sceneIndex = _storySceneIndex(_currentScene);
      if (sessionId == null || sceneIndex == null) {
        _celebrateLocally();
        return;
      }
      final r = await app.api.readAloudTurn(
        sessionId: sessionId,
        audioBytes: bytes,
        sceneIndex: sceneIndex,
      );
      if (!mounted) return;
      // Appreciation first, always — but WHAT is said follows the reading:
      // how much actually landed, and the one sound worth another go.
      final praise = r['praise_copy'] as String? ?? '🌟';
      final practice = r['practice_copy'] as String? ?? '';
      final verdict = r['verdict'] as String? ?? 'unclear';
      final focus = r['focus_part'] as String? ?? '';
      final read = r['words_read'] as int? ?? 0;
      final total = r['words_total'] as int? ?? 0;
      final lines = <String>[];
      if (verdict == 'unclear') {
        // We heard nothing — no praise for a reading we can't vouch for,
        // and no blame either.
        lines.add(r['encourage_copy'] as String? ?? "Let's try once more!");
      } else {
        lines.add(praise);
        if (verdict == 'fluent') {
          lines.add('🌟 You read the whole thing!');
        } else if (total > 0) {
          lines.add('📖 You read $read of $total words');
        }
        if (practice.isNotEmpty) {
          lines.add(focus.isNotEmpty ? '$practice  →  $focus' : practice);
        }
      }
      setState(() {
        _speechPhase = 'celebrate';
        _feedbackCopy = lines.join('\n');
      });
      _playFeedback(verdict == 'unclear' ? 'encourage' : 'praise_reading');
    } catch (_) {
      _celebrateLocally();
    }
  }

  /// The overlay's "Try again" — reopen whichever turn was underway.
  void _micRetry() {
    if (_readingTurn) {
      _startReading();
    } else {
      _startListening();
    }
  }

  Future<void> _submitClip(List<int> bytes) async {
    final app = context.read<AppState>();
    setState(() => _speechPhase = 'processing');
    try {
      final sessionId = app.sessionId;
      if (sessionId == null) {
        _celebrateLocally();
        return;
      }
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
      // Constructive feedback — teach the expected word politely, then
      // replay the narration a little slower (AC-04 ladder).
      final correction = r['correction_copy'] as String? ?? '';
      setState(() {
        _speechPhase = 'retry';
        _attempt = (r['attempt'] as int? ?? _attempt) + 1;
        _feedbackCopy = correction.isNotEmpty
            ? correction
            : r['encourage_copy'] as String? ?? 'மீண்டும் சொல்லலாம்! 💪';
      });
      _playCorrectionThenReplay();
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
      _playFeedback('celebrate'); // Mina says it out loud, like a parent
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
    _playFeedback('celebrate');
  }

  void _celebrateLocally() {
    if (!mounted) return;
    setState(() {
      _speechPhase = 'celebrate';
      _feedbackCopy = 'அருமை! (Super!) 🎉';
    });
    _playFeedback('celebrate');
  }

  /// Miss 1 — Mina first SAYS the gentle correction ("good try — the word
  /// is …, once more!"), then replays the narration slower and listens
  /// again. Falls through to the slow replay if the audio isn't loaded.
  Future<void> _playCorrectionThenReplay() async {
    final index = _currentScene;
    final sceneIndex = _storySceneIndex(index);
    final player = (sceneIndex == null
            ? null
            : _players['correction_$sceneIndex']) ??
        _players['encourage'];
    if (player != null) {
      try {
        for (final p in _players.values) {
          p.stop();
        }
        await player.setPlaybackRate(1.0);
        await player
            .seek(Duration.zero)
            .timeout(const Duration(seconds: 2), onTimeout: () {});
        await player.resume();
        await player.onPlayerComplete.first
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('Correction play failed: $e');
      }
    }
    if (!mounted || _currentScene != index) return;
    _playSceneSlow();
  }

  /// Miss 1 → replay the scene narration a little slower (AC-04 ladder),
  /// then Mina listens again by herself — the loop keeps flowing.
  Future<void> _playSceneSlow() async {
    final index = _currentScene;
    final assetId = _scenes[index].assetId;
    final player = assetId == null ? null : _players[assetId];
    if (player == null) {
      _scheduleAutoListen(index, delay: const Duration(seconds: 3));
      return;
    }
    try {
      // Base narration is already generated at a storyteller pace (~0.8),
      // so the retry replay only dips a little further.
      await player.setPlaybackRate((0.9 * _paceRate).clamp(0.65, 1.5));
      await player
          .seek(Duration.zero)
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      await player.resume();
      player.onPlayerComplete.first.then((_) => _autoListen(index));
    } catch (_) {}
  }

  void _resetSpeechState() {
    _autoListenTimer?.cancel();
    _liveMic.cancel();
    _speechPhase = 'idle';
    _attempt = 1;
    _feedbackCopy = '';
    _fallbackOptions = [];
    _readingTurn = false;
    _narrationPaused = false;
    _vocabActive = -1;
    _vocabPhase = 'idle';
    _vocabVerdict = '';
    _vocabFeedback = '';
    _vocabFocus = '';
    _vocabAttempt = 0;
  }

  // ── Words to learn — hear → analyse → cross-check → correct ─────

  /// Child taps a word chip: Mina models the word, opens her ears, then
  /// judges the attempt against the letters of the word and answers what
  /// was actually said. Tapping again while she's coaching is a retry.
  Future<void> _practiceWord(int i) async {
    if (_vocabPhase == 'speaking' ||
        _vocabPhase == 'listening' ||
        _vocabPhase == 'thinking') {
      return;
    }
    _autoListenTimer?.cancel();
    _livePlayer.stop();
    for (final p in _players.values) {
      p.stop();
    }
    // A different word — or a settled one — starts the count over; tapping
    // mid-coaching keeps it, so three goes really means three.
    final retry = _vocabActive == i && _vocabPhase == 'coach';
    setState(() {
      _vocabActive = i;
      _vocabPhase = 'speaking';
      if (!retry) {
        _vocabAttempt = 0;
        _vocabVerdict = '';
        _vocabFeedback = '';
        _vocabFocus = '';
      }
    });
    await _modelWord(i);
    if (!mounted || _vocabActive != i) return;
    await _listenForWord(i);
  }

  /// Mina says the word on its own — a touch slower than the story, since
  /// this is modelling rather than narration.
  Future<void> _modelWord(int i) async {
    final player = _players['vocab_$i'];
    if (player == null) return;
    try {
      await player.setPlaybackRate((0.9 * _paceRate).clamp(0.65, 1.5));
      await player
          .seek(Duration.zero)
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      await player.resume();
      await player.onPlayerComplete.first
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Vocab play failed for vocab_$i: $e');
    }
  }

  /// The child's turn — one short window, closed by silence. Every mic
  /// opening counts as a go, whether the child tapped for it or Mina looped
  /// back after a correction.
  Future<void> _listenForWord(int i) async {
    setState(() {
      _vocabPhase = 'listening';
      _vocabAttempt += 1;
    });
    if (!await _liveMic.hasPermission()) {
      // No mic: we can't judge what we never heard, so we don't pretend to.
      if (!mounted || _vocabActive != i) return;
      setState(() {
        _vocabPhase = 'coach';
        _vocabVerdict = 'unclear';
        _vocabFeedback = 'Say it out loud with Mina — tap to hear it again!';
      });
      return;
    }
    final result = await _liveMic.listen(
      maxDuration: const Duration(seconds: 6),
      silenceAfter: const Duration(milliseconds: 1200),
      noSpeechTimeout: const Duration(seconds: 5),
    );
    if (!mounted || _vocabActive != i || _vocabPhase != 'listening') return;
    if (result == null || !result.heardSpeech) {
      setState(() {
        _vocabPhase = 'coach';
        _vocabVerdict = 'unclear';
        _vocabFeedback = "I didn't catch that — tap the word and say it loud!";
      });
      _playFeedback('encourage');
      return;
    }
    await _judgeWord(i, result.wavBytes);
  }

  /// Hear → analyse → cross-check with the letters → correct with feedback.
  /// The backend returns a verdict for THIS attempt plus the one syllable
  /// that slipped; a miss is answered by naming it and modelling the word
  /// again, not by a stock "Super!".
  Future<void> _judgeWord(int i, List<int> bytes) async {
    final app = context.read<AppState>();
    setState(() => _vocabPhase = 'thinking');
    final sessionId = app.sessionId;
    Map<String, dynamic>? r;
    if (sessionId != null) {
      try {
        r = await app.api.wordPracticeTurn(
          sessionId: sessionId,
          audioBytes: bytes,
          wordIndex: i,
        );
      } catch (e) {
        debugPrint('Word practice failed: $e');
      }
    }
    if (!mounted || _vocabActive != i) return;
    if (r == null) {
      // Backend unreachable — no verdict is honest, a fake one isn't.
      setState(() {
        _vocabPhase = 'coach';
        _vocabVerdict = 'unclear';
        _vocabFeedback = 'Let me hear that once more — tap the word!';
      });
      return;
    }

    final action = r['next_action'] as String? ?? 'model_again';
    final feedback = (r['feedback_copy'] as String? ?? '').trim();
    final verdict = r['verdict'] as String? ?? 'unclear';
    final focus = r['focus_part'] as String? ?? '';
    final word = r['word'] as String? ?? _story?.vocabulary[i].wordTargetLang;
    final lastTry = _vocabAttempt >= _vocabMaxTries;
    setState(() {
      _vocabVerdict = verdict;
      _vocabFocus = focus;
      _vocabFeedback = feedback;
      _vocabPhase = action == 'celebrate' ? 'celebrate' : 'coach';
    });

    if (action == 'celebrate') {
      // Praise that names the word they just nailed — spoken, not canned.
      if (!await _speakLive(feedback)) _playFeedback('celebrate');
      if (!mounted || _vocabActive != i) return;
      Timer(const Duration(milliseconds: 2600), () {
        if (!mounted || _vocabActive != i) return;
        setState(() {
          _vocabActive = -1;
          _vocabPhase = 'idle';
          _vocabVerdict = '';
          _vocabFeedback = '';
          _vocabFocus = '';
        });
      });
      return;
    }

    // Not there yet — say the correction, then model the word again so the
    // fix is heard right after it's named.
    if (!await _speakLive(feedback)) _playFeedback('encourage');
    if (!mounted || _vocabActive != i || _vocabPhase != 'coach') return;
    await _modelWord(i);
    if (!mounted || _vocabActive != i || _vocabPhase != 'coach') return;
    if (lastTry) {
      // Three goes is plenty for one word — always end warmly.
      setState(() => _vocabFeedback =
          'Good trying! We\'ll practise ${word ?? 'it'} again later 💛');
      return;
    }
    await _listenForWord(i);
  }

  /// Speak a line Mina composed live. Returns false when no voice came
  /// back — the text still shows, so feedback never depends on TTS.
  Future<bool> _speakLive(String text) async {
    if (text.isEmpty) return false;
    final app = context.read<AppState>();
    final sessionId = app.sessionId;
    if (sessionId == null) return false;
    final clip = await app.api.speak(sessionId: sessionId, text: text);
    if (clip == null || !mounted) return false;
    try {
      for (final p in _players.values) {
        p.stop();
      }
      await _livePlayer.setReleaseMode(ReleaseMode.stop);
      await _livePlayer.setPlaybackRate(1.0);
      await _livePlayer
          .play(BytesSource(clip.bytes, mimeType: clip.mimeType))
          .timeout(const Duration(seconds: 12));
      await _livePlayer.onPlayerComplete.first
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      debugPrint('Live coaching speech failed: $e');
      return false;
    }
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
            child: Stack(children: [
              Column(
          children: [
            // Top bar — hold-to-exit gate + the trail of pages
            Padding(
              padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 0),
              child: Row(
                children: [
                  _holdExitButton(),
                  const SizedBox(width: 10),
                  // Where the child is in the book, told in pictures. Scales
                  // itself down rather than overflowing on a narrow phone.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          for (var i = 0; i < _scenes.length; i++)
                            _pageBead(i, scene.accent),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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

            // Scene content — one storybook page, turned by swiping.
            Expanded(
              child: GestureDetector(
                // A child turns a page by pushing it aside; the arrows stay for
                // the ones who'd rather tap.
                onHorizontalDragEnd: _onPageSwipe,
                child: AnimatedSwitcher(
                  duration: _anim(320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final dx = _pageForward ? 1.0 : -1.0;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(dx * 0.18, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey(_currentScene),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _storyPage(scene),
                        if (_currentScene == 0 && _scenes.length > 1) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Swipe to turn the page  👉',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: TColors.inkFaint.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // Who reads? — Mina narrates, or the child reads and
                        // Mina listens (story scenes only). How fast she tells
                        // it is a grown-up's dial, so it stays tucked away.
                        if (_isStoryScene(_currentScene)) ...[
                          _readModeToggle(scene),
                          const SizedBox(height: 8),
                          if (_showPace) ...[
                            _paceToggle(scene),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 4),
                        ] else
                          const SizedBox(height: 10),

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
                      onTap: _previousScene,
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
        ),
              // The 1-1 conversation overlay — Mina full screen, listening
              // live, thinking, then answering. Silence ends the turn.
              if (_speechPhase == 'listening' ||
                  _speechPhase == 'processing' ||
                  _speechPhase == 'nudge')
                _buildListeningOverlay(scene),
            ])),
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

  /// One page in the trail across the top. The page being read wears its
  /// own picture; the ones already read keep a small badge, so the child
  /// can see the story filling up behind them.
  Widget _pageBead(int index, Color accent) {
    final active = index == _currentScene;
    final done = index < _currentScene;
    return AnimatedContainer(
      duration: _anim(300),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 34 : 22,
      height: active ? 34 : 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? accent.withValues(alpha: 0.85) : Colors.white,
        shape: BoxShape.circle,
        border: active ? Border.all(color: accent, width: 2.5) : null,
        boxShadow: active ? TShadows.card : null,
      ),
      child: Text(
        done ? '✓' : _scenes[index].emoji,
        style: TextStyle(
          fontSize: active ? 17 : 11,
          fontWeight: FontWeight.w800,
          color: done ? Colors.white : null,
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

  /// Parent picks the narration speed the child follows best — applies
  /// immediately to the scene currently playing too.
  void _setPaceRate(double rate) {
    if (_paceRate == rate) return;
    setState(() => _paceRate = rate);
    final assetId = _scenes[_currentScene].assetId;
    final player = assetId == null ? null : _players[assetId];
    player?.setPlaybackRate(rate);
  }

  /// Who reads this story — a two-way pill: Mina narrates, or the child
  /// reads by themself while Mina listens and appreciates. The speed dial
  /// hides behind the small button beside it.
  Widget _readModeToggle(_DemoScene scene) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(22),
            boxShadow: TShadows.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeChip('🔊 Mina reads', !_iRead, scene.accent,
                  () => _setIRead(false)),
              _modeChip(
                  '🧒 I read', _iRead, scene.accent, () => _setIRead(true)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showPace = !_showPace),
          child: Container(
            width: 56, // AC-03 — ≥56 dp
            height: 56,
            decoration: BoxDecoration(
              color: _showPace
                  ? scene.accent
                  : Colors.white.withValues(alpha: 0.75),
              shape: BoxShape.circle,
              boxShadow: TShadows.card,
            ),
            child: Icon(
              Icons.speed_rounded,
              size: 22,
              color: _showPace ? Colors.white : TColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }

  /// Narration speed pill — 🐢 extra slow · 📖 story pace (default) · 🐇
  /// brisker, on top of the 0.8-pace generated audio.
  Widget _paceToggle(_DemoScene scene) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(22),
        boxShadow: TShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeChip('🐢 Slower', _paceRate == 0.85, scene.accent,
              () => _setPaceRate(0.85)),
          _modeChip('📖 Story', _paceRate == 1.0, scene.accent,
              () => _setPaceRate(1.0)),
          _modeChip('🐇 Faster', _paceRate == 1.15, scene.accent,
              () => _setPaceRate(1.15)),
        ],
      ),
    );
  }

  Widget _modeChip(
      String label, bool selected, Color accent, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // ≥56 dp hit target via padding (AC-03)
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : TColors.inkSoft,
          ),
        ),
      ),
    );
  }

  /// One page of the storybook: a picture panel on top, the words below —
  /// the shape of a board book, so a child looks at the picture first and
  /// the words second.
  Widget _storyPage(_DemoScene scene) {
    final story = _story;
    final refrain = story == null
        ? ''
        : story.refrainTargetLang.isNotEmpty
            ? story.refrainTargetLang
            : story.refrain;
    final gloss = scene.english;
    final showGloss = gloss.isNotEmpty && gloss != scene.narration;
    final onStoryPage = _isStoryScene(_currentScene);

    return TCard(
      radius: 30,
      padding: EdgeInsets.zero,
      shadows: TShadows.soft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Column(
          children: [
            _picturePanel(scene),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                children: [
                  Text(
                    scene.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      color: scene.accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // The story itself, in the home language, set big enough
                  // to follow along with a finger.
                  Text(
                    scene.narration,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.65,
                      fontWeight: FontWeight.w700,
                      color: TColors.ink,
                    ),
                  ),
                  if (showGloss) ...[
                    const SizedBox(height: 12),
                    Text(
                      gloss,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: TColors.inkFaint,
                      ),
                    ),
                  ],
                  if (onStoryPage && refrain.isNotEmpty)
                    _refrainBanner(scene, refrain),
                  if (onStoryPage && (_story?.vocabulary.isNotEmpty ?? false))
                    _vocabSection(scene),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The picture half of the page — the chapter's own emoji, big, with the
  /// chapter label tucked in one corner and the voice buttons in the other.
  Widget _picturePanel(_DemoScene scene) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scene.accent.withValues(alpha: 0.18),
                    scene.accent.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          // Two soft blobs, so the picture sits in a scene and not on a
          // flat wash of colour.
          Positioned(right: -24, top: -28, child: _blob(110, scene.accent)),
          Positioned(left: -20, bottom: -34, child: _blob(92, scene.accent)),
          Center(
            child: Text(scene.emoji, style: const TextStyle(fontSize: 88)),
          ),
          if (scene.kicker.isNotEmpty)
            Positioned(
              left: 14,
              top: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  scene.kicker.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: scene.accent,
                  ),
                ),
              ),
            ),
          if (_hasAudio(scene))
            Positioned(right: 12, bottom: 12, child: _pageVoice(scene)),
        ],
      ),
    );
  }

  Widget _blob(double size, Color accent) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
    );
  }

  /// Read it to me again, or hold it right there — the two things a child
  /// asks for mid-story, on the page itself.
  Widget _pageVoice(_DemoScene scene) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePause,
          child: Container(
            width: 56, // AC-03 — ≥56 dp
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: TShadows.card,
            ),
            child: Icon(
              _narrationPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              color: TColors.ink,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _playNarration(_currentScene),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: scene.accent,
              shape: BoxShape.circle,
              boxShadow: TShadows.card,
            ),
            child: const Icon(Icons.volume_up_rounded,
                color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }

  /// The story's chant. Grandma says it the same way every single night, so
  /// it gets its own line on the page to join in with.
  Widget _refrainBanner(_DemoScene scene, String refrain) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: TColors.lemon.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: TColors.gold.withValues(alpha: 0.6),
          width: 1.4,
        ),
      ),
      child: Column(
        children: [
          const Text(
            '👏 SAY IT WITH ME',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: TColors.goldDeep,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            refrain,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ Words to learn — highlighted chips on the story card. Tap one:
  /// Mina speaks the home-language word, the child repeats it, and Mina
  /// answers the actual attempt — naming the sound to fix when it slipped.
  /// Native script big, English meaning small.
  Widget _vocabSection(_DemoScene scene) {
    final vocab = _story?.vocabulary ?? [];
    return Column(
      children: [
        const SizedBox(height: 14),
        Container(height: 1, color: TColors.mist),
        const SizedBox(height: 12),
        Text(
          '✨ WORDS TO LEARN — TAP & SAY IT!',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: scene.accent,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < vocab.length; i++) _vocabChip(i, scene),
          ],
        ),
        if (_vocabActive >= 0) ...[
          const SizedBox(height: 10),
          Text(
            _vocabStatus(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: scene.accent,
            ),
          ),
          // The one syllable that slipped — shown big, because that is the
          // thing to try again, not the whole word.
          if (_vocabFocus.isNotEmpty && _vocabVerdict == 'close') ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: TColors.lemon.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: TColors.gold.withValues(alpha: 0.7),
                  width: 1.4,
                ),
              ),
              child: Text(
                'this sound → $_vocabFocus',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: TColors.ink,
                ),
              ),
            ),
          ],
          if (_vocabFeedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _vocabFeedback,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: TColors.inkSoft,
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// One line naming where this attempt stands — driven by the verdict, so
  /// it changes with what the child actually said.
  String _vocabStatus() {
    switch (_vocabPhase) {
      case 'speaking':
        return '🔊 Listen…';
      case 'listening':
        return '🎤 Your turn — say it!';
      case 'thinking':
        return '👂 Mina is checking…';
      case 'celebrate':
        return '🌟 You said it right!';
      default:
        switch (_vocabVerdict) {
          case 'close':
            return '👂 So close — one sound to fix';
          case 'different':
            return '🔁 Listen once more, then try';
          default:
            return "🎤 I couldn't hear it clearly";
        }
    }
  }

  Widget _vocabChip(int i, _DemoScene scene) {
    final vw = _story!.vocabulary[i];
    final active = _vocabActive == i;
    // The badge tracks the verdict: nailed it, or worth another go.
    final badge = !active
        ? '🔊'
        : _vocabPhase == 'celebrate'
            ? '🌟'
            : _vocabPhase == 'coach'
                ? '🔁'
                : '🔊';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _practiceWord(i),
      child: AnimatedContainer(
        duration: _anim(200),
        // ≥56 dp hit target via padding (AC-03)
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? scene.accent.withValues(alpha: 0.15)
              : TColors.lemon.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? scene.accent : TColors.gold.withValues(alpha: 0.5),
            width: active ? 2 : 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$badge ${vw.wordTargetLang}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: active ? scene.accent : TColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              vw.word,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: TColors.inkFaint,
              ),
            ),
          ],
        ),
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

    // idle | retry — Mina opens her ears on her own after the narration;
    // the button is the manual way in (and the very first mic-permission
    // gesture). No stop button anywhere — silence closes the turn.
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
        GestureDetector(
          onTap: _startListening,
          child: Container(
            height: 64, // AC-03 — child touch targets ≥56 dp
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              gradient: TGradients.hero,
              borderRadius: BorderRadius.circular(24),
              boxShadow: TShadows.glowTeal,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_rounded, color: Colors.white, size: 26),
                SizedBox(width: 10),
                Text(
                  'Talk to Mina',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'She listens by herself — just speak!',
          style: TextStyle(
            color: TColors.inkFaint,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// The hands-free conversation overlay: full-screen Mina reacting to the
  /// child's live voice (listening), a thinking beat (processing), and a
  /// gentle nudge when nothing was heard — never a dead end (AC-04).
  /// In "I read" turns the story TEXT stays on screen, big and clear —
  /// the child needs to see the words to read them to Mina.
  Widget _buildListeningOverlay(_DemoScene scene) {
    final listening = _speechPhase == 'listening';
    final processing = _speechPhase == 'processing';
    final reading = _readingTurn;
    final minaSize = reading ? 96.0 : 150.0;
    return Positioned.fill(
      child: AnimatedContainer(
        duration: _anim(300),
        decoration: BoxDecoration(
          gradient: listening ? TGradients.hero : TGradients.night,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // The hold-to-exit gate stays reachable at all times (AC-03).
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [_holdExitButton()]),
              ),
              if (reading)
                // The reading card — large storybook text the child reads
                // from while Mina listens below.
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(22, 14, 22, 4),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: TShadows.card,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${scene.emoji}  ${scene.title}',
                              style: TextStyle(
                                color: scene.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              )),
                          const SizedBox(height: 12),
                          Text(
                            scene.narration,
                            style: const TextStyle(
                              color: TColors.ink,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              height: 1.6,
                            ),
                          ),
                          if (scene.english.isNotEmpty &&
                              scene.english != scene.narration) ...[
                            const SizedBox(height: 14),
                            Text(
                              scene.english,
                              style: const TextStyle(
                                color: TColors.inkSoft,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              GestureDetector(
                onTap: listening || processing ? null : _micRetry,
                child: VoiceAura(
                  level: _liveMic.level,
                  color: Colors.white,
                  active: listening,
                  size: minaSize,
                  child: Mina(
                    state: listening
                        ? MinaState.listening
                        : processing
                            ? MinaState.thinking
                            : MinaState.encouraging,
                    size: minaSize,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Text(
                  listening
                      ? (reading
                          ? 'Read the story to Mina! 📖'
                          : scene.prompt)
                      : processing
                          ? 'Mina is thinking…'
                          : "Mina couldn't hear you 🤍",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: reading ? 16 : 20,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 14),
              if (listening)
                ValueListenableBuilder<bool>(
                  valueListenable: _liveMic.heardSpeech,
                  builder: (_, heard, __) => Text(
                    heard
                        ? 'I hear you! Keep going… 🌟'
                        : "Say it out loud — I'm listening",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (processing)
                const ThinkingDots(color: Colors.white)
              else
                // Nudge — try again or keep the story going; never blocks.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _overlayAction(
                      icon: Icons.mic_rounded,
                      label: 'Try again',
                      onTap: _micRetry,
                    ),
                    const SizedBox(width: 14),
                    _overlayAction(
                      icon: Icons.arrow_forward_rounded,
                      label: 'Keep going',
                      onTap: _celebrateLocally,
                    ),
                  ],
                ),
              if (!reading) const Spacer(),
              if (listening)
                Padding(
                  padding: EdgeInsets.only(bottom: reading ? 14 : 28, top: reading ? 8 : 0),
                  child: Text(
                    "I'll answer when you pause",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                SizedBox(height: reading ? 14 : 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlayAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56, // AC-03 — child touch targets ≥56 dp
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _nextScene() {
    if (_currentScene < _scenes.length - 1) {
      setState(() {
        _pageForward = true;
        _currentScene++;
        _resetSpeechState();
      });
      _playScene(_currentScene);
    } else {
      _finishSession();
    }
  }

  void _previousScene() {
    if (_currentScene == 0) return;
    setState(() {
      _pageForward = false;
      _currentScene--;
      _resetSpeechState();
    });
    _playScene(_currentScene);
  }

  /// A page turn. Flick left and the next page comes in; flick right and
  /// the last one comes back. The final swipe stops at the last page —
  /// ending the story stays a deliberate tap on "Finish!", never a flick.
  void _onPageSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 220) return; // a nudge is not a page turn
    if (velocity < 0) {
      if (_currentScene >= _scenes.length - 1) return;
      _nextScene();
    } else {
      _previousScene();
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
  /// Small label above the title — "Chapter 2", "Mission", "Family".
  final String kicker;
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
    this.kicker = '',
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
