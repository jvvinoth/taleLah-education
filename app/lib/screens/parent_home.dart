/// Parent Home — premium moment capture + story review.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/live_mic.dart';
import 'add_child_screen.dart';
import 'child_session.dart';
import 'community_events.dart';
import 'family_mode.dart';
import 'parent_review.dart';
import 'profile_screen.dart';
import 'stories_library.dart';

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  final _textController = TextEditingController();
  String _selectedLocale = 'ta-SG';
  int _navIndex = 0;

  // F5 — hands-free voice note capture (≤45 s, enforced again
  // server-side). LiveMic auto-stops when the parent pauses.
  final LiveMic _momentMic = LiveMic();
  final Earcons _earcons = Earcons();
  bool _voiceOverlayVisible = false;
  // Sprint 0 — story engine: 'classic' (untouched) or 'new' (book-first beta).
  String _selectedEngine = 'classic';

  // Between the mic closing and the transcript arriving, this is true so
  // the parent sees work happening rather than a dead text box.
  bool _isTranscribing = false;

  // The compact generation bar can be dismissed; it reappears when the
  // story finishes or the parent taps "Create Story" again.
  bool _progressDismissed = false;
  // Brief green flash when generation completes.
  bool _justCompleted = false;

  static const _locales = [
    ('ta-SG', 'தமிழ்', 'Tamil'),
    ('zh-SG', '中文', 'Chinese'),
    ('ms-SG', 'Melayu', 'Malay'),
  ];

  @override
  void dispose() {
    _momentMic.dispose();
    _earcons.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topPad = MediaQuery.of(context).padding.top;
    _maybeShowCaptureError(app);
    _maybeShowClarification(app);
    _maybeFlashComplete(app);

    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, topPad + 16, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(app),
                  const SizedBox(height: 24),
                  _buildHeroCard(app),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Capture a Moment', 'Turn today into a story'),
                  const SizedBox(height: 12),
                  _buildMomentCapture(app),
                  const SizedBox(height: 24),
                  if (app.latestPackage != null && !app.isGenerating) ...[
                    _buildSectionTitle('Story Ready', 'Review & play together'),
                    const SizedBox(height: 12),
                    _buildPackageCard(app),
                  ],
                ],
              ),
            ),
            // Floating bottom nav
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _buildBottomNav(app),
            ),
            // Hands-free listening overlay — full-screen so the parent
            // knows the mic is live; auto-dismisses when they pause.
            if (_voiceOverlayVisible) _buildVoiceCaptureOverlay(),
            // Compact generation progress bar — sits above the nav so the
            // parent can still browse while the story is woven.
            if ((app.isGenerating || _justCompleted) && !_progressDismissed)
              _buildProgressBar(app),
          ],
        ),
      ),
    );
  }

  /// Capture/generation failures must never end silent — surface the
  /// friendly message the moment AppState reports one.
  void _maybeShowCaptureError(AppState app) {
    final message = app.captureError;
    if (message == null) return;
    app.clearCaptureError();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: TColors.ink,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              const Text('😔', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Detect generation completion and flash the bar green briefly.
  bool _wasGenerating = false;
  void _maybeFlashComplete(AppState app) {
    if (_wasGenerating && !app.isGenerating && app.captureError == null && app.latestPackage != null) {
      _justCompleted = true;
      _progressDismissed = false;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _justCompleted = false);
      });
    }
    _wasGenerating = app.isGenerating;
  }

  /// Pop a dialog when the pipeline pauses for a clarification question.
  bool _clarifyDialogShown = false;
  void _maybeShowClarification(AppState app) {
    if (app.pendingClarification != null && !_clarifyDialogShown) {
      _clarifyDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || app.pendingClarification == null) {
          _clarifyDialogShown = false;
          return;
        }
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ClarificationDialog(
            question: app.pendingClarification!,
            onAnswer: (answer) {
              app.answerClarification(answer);
              _clarifyDialogShown = false;
            },
          ),
        );
      });
    } else if (app.pendingClarification == null) {
      _clarifyDialogShown = false;
    }
  }

  /// Compact progress bar positioned above the bottom nav.
  Widget _buildProgressBar(AppState app) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final activeIdx =
        _agentSteps.indexWhere((s) => s.$1 == app.currentAgent);
    final done = !app.isGenerating && _justCompleted;
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottomPad + 90, // above the floating nav
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(
          color: done ? const Color(0xFF1F7B75) : TColors.ink,
          borderRadius: BorderRadius.circular(22),
          boxShadow: TShadows.soft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        done
                            ? 'Story ready!'
                            : app.generationStatus.isNotEmpty
                                ? app.generationStatus
                                : 'Starting…',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!done && app.progressPct > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${app.progressPct.toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _progressDismissed = true),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            if (!done) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: app.progressPct > 0 ? app.progressPct / 100 : null,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF2F9E97)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_agentSteps.length, (i) {
                  final step = _agentSteps[i];
                  final stepDone = activeIdx > i ||
                      app.progressPct >= ((i + 1) / _agentSteps.length) * 100;
                  final active = activeIdx == i && !stepDone;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: stepDone
                          ? const Color(0xFF3BB8A9)
                          : active
                              ? const Color(0xFF2F9E97)
                              : Colors.white.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: stepDone
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 12)
                          : Text(step.$2,
                              style: const TextStyle(fontSize: 10)),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Pulsing indicator between voice capture and transcript arrival.
  Widget _buildTranscribingStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: TColors.mist,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: TColors.teal.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Listening to what you said…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: TColors.tealDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader(AppState app) {
    return Row(
      children: [
        const TMascot(size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(app),
                style: const TextStyle(
                  fontSize: 14,
                  color: TColors.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'TaleLah',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: TColors.ink,
                ),
              ),
            ],
          ),
        ),
        _iconBubble(Icons.notifications_none_rounded),
      ],
    );
  }

  /// Greeting follows the active child's home language; "Welcome" is the
  /// default when no profile is selected (or the child learns in English).
  String _greeting(AppState app) {
    switch (app.activeProfile?.homeLanguage) {
      case 'ta':
        return 'Vanakkam 👋';
      case 'zh':
        return '欢迎 👋';
      case 'ms':
        return 'Selamat datang 👋';
      default:
        return 'Welcome 👋';
    }
  }

  Widget _iconBubble(IconData icon) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: TShadows.card,
      ),
      child: Icon(icon, color: TColors.ink, size: 22),
    );
  }

  // ── Hero card ───────────────────────────────────────────────────────

  Widget _buildHeroCard(AppState app) {
    final childName = app.activeProfile?.alias;
    return TCard(
      gradient: TGradients.hero,
      radius: 28,
      shadows: TShadows.glowTeal,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "✨ Today's Adventure",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Text('🚂', style: TextStyle(fontSize: 28)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            childName != null
                ? "$childName's mother-tongue\njourney awaits"
                : 'Every moment becomes\na magical story',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '5-minute stories • Real family moments',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          // Child profile pill / add child
          if (app.activeProfile != null)
            _childPill(app)
          else
            _addChildButton(app),
        ],
      ),
    );
  }

  Widget _childPill(AppState app) {
    final p = app.activeProfile!;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              image: p.photoUrl != null && p.photoUrl!.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(app.api.photoUrl(p.photoUrl!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: p.photoUrl == null || p.photoUrl!.isEmpty
                ? Center(
                    child: Text(
                      p.alias.isNotEmpty ? p.alias[0].toUpperCase() : '🙂',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: TColors.tealDeep,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.alias,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Age ${p.ageBand} • ${_localeName(p.targetLocale)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _addChildButton(AppState app) {
    return GestureDetector(
      onTap: () => _showCreateProfileDialog(app),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: TColors.tealDeep, size: 20),
            SizedBox(width: 6),
            Text(
              'Add your child',
              style: TextStyle(
                color: TColors.tealDeep,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section title ───────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: TColors.inkFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Moment capture ──────────────────────────────────────────────────

  Widget _buildMomentCapture(AppState app) {
    return TCard(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text field
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3E9),
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextField(
              controller: _textController,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText:
                    'What did your child do today?\ne.g. Arun saw a red train at the MRT…',
                hintStyle: const TextStyle(
                  color: TColors.inkFaint,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
                counterText: '',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8, bottom: 40),
                  child: Icon(Icons.auto_awesome,
                      color: TColors.teal.withValues(alpha: 0.6), size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // F5 — voice + photo capture chips (hidden while transcribing)
          if (_isTranscribing)
            _buildTranscribingStrip()
          else
            Row(
              children: [
                Expanded(
                  child: _captureChip(
                    emoji: '🎙️',
                    label: _voiceOverlayVisible ? 'Listening…' : 'Speak it',
                    active: _voiceOverlayVisible,
                    onTap: app.isGenerating || _voiceOverlayVisible
                        ? null
                        : app.activeProfile == null
                            ? () => _promptCreateProfile(app)
                            : () => _startVoiceCapture(app),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _captureChip(
                    emoji: '📸',
                    label: 'Snap it',
                    active: false,
                    onTap: app.isGenerating || _voiceOverlayVisible
                        ? null
                        : app.activeProfile == null
                            ? () => _promptCreateProfile(app)
                            : () => _pickPhoto(app),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Language pills
          Row(
            children: _locales.map((l) {
              final selected = _selectedLocale == l.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedLocale = l.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? TColors.ink : const Color(0xFFF0EDE1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Column(
                      children: [
                        Text(
                          l.$2,
                          style: TextStyle(
                            color: selected ? Colors.white : TColors.inkSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          l.$3,
                          style: TextStyle(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.6)
                                : TColors.inkFaint,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _engineToggle(),
          const SizedBox(height: 18),
          // CTA
          GestureDetector(
            onTap: app.activeProfile == null
                ? () => _promptCreateProfile(app)
                : app.isGenerating
                    ? () => setState(() => _progressDismissed = false)
                    : () => _startGeneration(app),
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                gradient: app.activeProfile == null
                    ? null
                    : app.isGenerating
                        ? null
                        : TGradients.coral,
                color: app.activeProfile == null
                    ? const Color(0xFFE8E4D8)
                    : app.isGenerating
                        ? TColors.mist
                        : null,
                borderRadius: BorderRadius.circular(20),
                boxShadow: app.activeProfile == null || app.isGenerating
                    ? null
                    : TShadows.glowCoral,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (app.isGenerating)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: TColors.teal,
                        ),
                      )
                    else
                      Icon(
                        Icons.auto_fix_high_rounded,
                        color: app.activeProfile == null
                            ? TColors.inkFaint
                            : Colors.white,
                        size: 20,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      app.isGenerating ? 'Creating…' : 'Create Story',
                      style: TextStyle(
                        color: app.activeProfile == null
                            ? TColors.inkFaint
                            : app.isGenerating
                                ? TColors.teal
                                : Colors.white,
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
    );
  }

  Widget _captureChip({
    required String emoji,
    required String label,
    required bool active,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? TColors.coral : const Color(0xFFF0EDE1),
          borderRadius: BorderRadius.circular(16),
          boxShadow: active ? TShadows.glowCoral : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : TColors.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Generation progress ─────────────────────────────────────────────

  static const _agentSteps = [
    ('moment_lens', '🔍', 'Understanding'),
    ('learning_planner', '📚', 'Planning'),
    ('story_weaver', '📖', 'Weaving'),
    ('language_guardian', '🗣️', 'Translating'),
    ('family_voice_director', '🎙️', 'Voicing'),
  ];

  // ── Package ready card ──────────────────────────────────────────────

  Widget _buildPackageCard(AppState app) {
    final pkg = app.latestPackage!;
    return TCard(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: pkg.coverIllustrationUrl.isNotEmpty
                      ? Image.network(
                          pkg.coverIllustrationUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: const BoxDecoration(gradient: TGradients.mint),
                            child: const Center(
                              child: Text('📖', style: TextStyle(fontSize: 30)),
                            ),
                          ),
                        )
                      : Container(
                          decoration: const BoxDecoration(gradient: TGradients.mint),
                          child: const Center(
                            child: Text('📖', style: TextStyle(fontSize: 30)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pkg.title.isEmpty ? 'Your Story is Ready!' : pkg.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _miniTag('${pkg.sceneCount} scenes', TColors.mist,
                            TColors.tealDeep),
                        const SizedBox(width: 6),
                        _miniTag(pkg.localeLabel, TColors.mint,
                            const Color(0xFF1F7B75)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pkg.targetPhrase.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TColors.lemon,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎯 TARGET PHRASE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB07E1F),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pkg.targetPhrase,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Review & Edit (F2) — opens the parent review workflow
          GestureDetector(
            onTap: () => _openReview(app),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: TColors.mist,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded,
                        color: TColors.tealDeep, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Review & Edit',
                      style: TextStyle(
                        color: TColors.tealDeep,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _approveAndStart(app),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: TGradients.hero,
                borderRadius: BorderRadius.circular(18),
                boxShadow: TShadows.glowTeal,
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 24),
                    SizedBox(width: 6),
                    Text(
                      'Approve & Play Together',
                      style: TextStyle(
                        color: Colors.white,
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
  }

  Widget _miniTag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  // ── Bottom nav ──────────────────────────────────────────────────────

  Widget _buildBottomNav(AppState app) {
    final items = [
      (Icons.home_rounded, 'Home'),
      (Icons.auto_stories_rounded, 'Stories'),
      (Icons.family_restroom_rounded, 'Family'),
      (Icons.event_rounded, 'Events'),
      (Icons.person_rounded, 'Profile'),
    ];
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: TColors.ink.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final selected = _navIndex == i;
          return GestureDetector(
            onTap: () => _onNavTap(i, app),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              // 5 items now — slimmer pills so the pill row never overflows.
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? TColors.peach : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(
                    items[i].$1,
                    color: selected ? TColors.coral : TColors.inkFaint,
                    size: 24,
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Text(
                      items[i].$2,
                      style: const TextStyle(
                        color: TColors.coral,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  void _onNavTap(int i, AppState app) {
    if (i == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StoriesLibraryScreen()),
      );
      return;
    }
    if (i == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FamilyModeScreen()),
      );
      return;
    }
    if (i == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CommunityEventsScreen()),
      );
      return;
    }
    if (i == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      return;
    }
    setState(() => _navIndex = i);
  }

  // ── Actions ─────────────────────────────────────────────────────────

  String _localeName(String locale) {
    switch (locale) {
      case 'ta-SG':
        return 'Tamil';
      case 'zh-SG':
        return 'Chinese';
      case 'ms-SG':
        return 'Malay';
      default:
        return locale;
    }
  }

  /// Sprint 0 — Classic vs New (beta) story engine. New routes to the
  /// book-first flow; Classic is unchanged. Lets us A/B and demo before/after.
  Widget _engineToggle() {
    Widget opt(String value, String label, String sub) {
      final on = _selectedEngine == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _selectedEngine = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? TColors.teal : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: on ? Colors.white : TColors.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: on
                        ? Colors.white.withValues(alpha: 0.7)
                        : TColors.inkFaint,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEADD),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          opt('classic', 'Classic', "today's flow"),
          opt('new', 'New ✨', 'book-first (beta)'),
        ],
      ),
    );
  }

  void _startGeneration(AppState app) {
    debugPrint('[TL] _startGeneration called, activeProfile=${app.activeProfile?.id}, isGenerating=${app.isGenerating}');
    final text = _textController.text.trim();
    if (text.isEmpty) {
      debugPrint('[TL] text is empty, showing snackbar');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the moment first')),
      );
      return;
    }
    debugPrint('[TL] starting generation with text="$text", locale=$_selectedLocale');
    setState(() {
      _progressDismissed = false;
      _justCompleted = false;
    });
    app
        .captureAndGenerate(
            text: text, locale: _selectedLocale, engine: _selectedEngine)
        .catchError((e) {
      debugPrint('[TL] captureAndGenerate unhandled error: $e');
    });
    _textController.clear();
    FocusScope.of(context).unfocus();
  }

  // ── F5 · voice + photo capture ───────────────────────────────────

  Future<void> _startVoiceCapture(AppState app) async {
    if (_voiceOverlayVisible) return;
    // Tap sound fires FIRST, synchronously inside the tap gesture — an await
    // before play() lets the browser's user-gesture window expire, and web
    // autoplay policy then blocks the sound silently.
    _earcons.start();
    if (!await _momentMic.hasPermission()) {
      _captureError('Microphone not available — try typing instead');
      return;
    }
    if (!mounted) return;
    setState(() => _voiceOverlayVisible = true);
    // Short beat before the mic opens so the bloop isn't captured.
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) {
      _momentMic.cancel();
      return;
    }
    final result = await _momentMic.listen(
      maxDuration: const Duration(seconds: 45),
      // Gentler: a brief pause won't cut you off; ~2.5 s of quiet auto-ends.
      silenceAfter: const Duration(milliseconds: 2500),
      noSpeechTimeout: const Duration(seconds: 8),
    );
    if (!mounted) return;
    setState(() => _voiceOverlayVisible = false);
    if (result == null) return; // cancelled by the parent
    if (!result.heardSpeech) {
      _captureError("Couldn't hear anything — try again closer to the mic");
      return;
    }
    _earcons.done(); // warm "got it" chime — plays after the mic has stopped
    // Transcribe (auto-detects English / Chinese / Tamil / Malay) and PREFILL
    // the text box — the parent reviews and edits, then taps Create.
    setState(() => _isTranscribing = true);
    try {
      final transcript = await app.transcribeMoment(result.wavBytes);
      if (!mounted) return;
      setState(() => _isTranscribing = false);
      if (transcript.trim().isEmpty) {
        _captureError("Couldn't catch that — try again or type it");
        return;
      }
      setState(() {
        final existing = _textController.text.trim();
        _textController.text =
            existing.isEmpty ? transcript : '$existing $transcript';
        _textController.selection =
            TextSelection.collapsed(offset: _textController.text.length);
      });
    } catch (e) {
      // Surface the real reason (server says empty-audio vs format vs API) so
      // we can see exactly what's wrong. Revert to a friendly message later.
      if (mounted) setState(() => _isTranscribing = false);
      _captureError('Voice: ${e.toString()}');
    }
  }

  /// Full-screen “I'm listening” moment — aura pulses with the parent's
  /// voice and the capture ends by itself when they pause.
  Widget _buildVoiceCaptureOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(gradient: TGradients.hero),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              VoiceAura(
                level: _momentMic.level,
                color: Colors.white,
                size: 132,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 2),
                  ),
                  child: const Center(
                      child: Text('🎙️', style: TextStyle(fontSize: 52))),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                "I'm listening — just talk",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: _momentMic.heardSpeech,
                builder: (_, heard, __) => Text(
                  heard
                      ? "Great — keep going, or tap Done when you're finished"
                      : 'Tell me about your moment today…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              // Primary — finish now and use what was captured. Enabled once
              // we've actually heard speech (so you can't submit silence).
              ValueListenableBuilder<bool>(
                valueListenable: _momentMic.heardSpeech,
                builder: (_, heard, __) => AnimatedOpacity(
                  opacity: heard ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 250),
                  child: GestureDetector(
                    onTap: heard ? () => _momentMic.finishNow() : null,
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 46),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              color: Color(0xFF243039), size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Done',
                            style: TextStyle(
                              color: Color(0xFF243039),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: GestureDetector(
                  onTap: () => _momentMic.cancel(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto(AppState app) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _captureError('Photo too large — max 10 MB');
        return;
      }
      setState(() {
        _progressDismissed = false;
        _justCompleted = false;
      });
      await app.captureAndGeneratePhoto(
        imageBytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
        locale: _selectedLocale,
        engine: _selectedEngine,
      );
    } catch (e) {
      debugPrint('[TL] _pickPhoto error: $e');
      _captureError('Could not read that photo — try typing instead');
    }
  }

  void _captureError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The capture controls look dimmed without a child profile — a tap must
  /// explain why and open the fix, never silently ignore the parent.
  void _promptCreateProfile(AppState app) {
    _captureError("Add your child first — let's set up their profile");
    _showCreateProfileDialog(app);
  }

  Future<void> _approveAndStart(AppState app) async {
    await app.approvePackage();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChildSessionScreen()),
    );
  }

  Future<void> _openReview(AppState app) async {
    final pkg = app.latestPackage;
    if (pkg == null) return;
    final approved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ParentReviewScreen(packageId: pkg.id),
      ),
    );
    if (approved == true && mounted) {
      // Review screen approves via raw API — load the approved package so
      // child mode gets the real scenes + F4 audio manifest.
      await app.loadApprovedStory(pkg.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChildSessionScreen()),
      );
    }
  }

  void _showCreateProfileDialog(AppState app) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddChildScreen()),
    );
  }
}

// ── Clarification dialog (F3) ─────────────────────────────────────────────

class _ClarificationDialog extends StatefulWidget {
  final String question;
  final ValueChanged<String> onAnswer;
  const _ClarificationDialog({
    required this.question,
    required this.onAnswer,
  });

  @override
  State<_ClarificationDialog> createState() => _ClarificationDialogState();
}

class _ClarificationDialogState extends State<_ClarificationDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TColors.lemon,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('\ud83e\udd14', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'One quick question',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: TColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.question,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: TColors.inkSoft,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F3E9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 2,
                maxLength: 300,
                autofocus: true,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: 'Add the missing detail\u2026',
                  hintStyle: TextStyle(
                    color: TColors.inkFaint,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () {
                  final answer = _controller.text.trim();
                  if (answer.isEmpty) return;
                  widget.onAnswer(answer);
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: TColors.teal,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Send answer',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
