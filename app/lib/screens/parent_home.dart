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
  final _clarifyController = TextEditingController();
  String _selectedLocale = 'ta-SG';
  int _navIndex = 0;

  // F5 — hands-free voice note capture (≤45 s, enforced again
  // server-side). LiveMic auto-stops when the parent pauses.
  final LiveMic _momentMic = LiveMic();
  final Earcons _earcons = Earcons();
  bool _voiceOverlayVisible = false;

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
    _clarifyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topPad = MediaQuery.of(context).padding.top;
    _maybeShowCaptureError(app);

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
            // Generation overlay — progress can never be scrolled out of
            // sight; covers the whole screen incl. the bottom nav.
            if (app.isGenerating) _buildGenerationOverlay(app),
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

  /// Full-screen dimmed overlay shown while the story is being woven —
  /// voice, photo and text all land here so the parent always sees
  /// what's happening (and the F3 question when the pipeline pauses).
  Widget _buildGenerationOverlay(AppState app) {
    return Positioned.fill(
      child: Container(
        color: TColors.ink.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (app.pendingClarification != null) ...[
                    _buildClarificationCard(app),
                    const SizedBox(height: 16),
                  ],
                  _buildProgress(app),
                ],
              ),
            ),
          ),
        ),
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
          // F5 — voice + photo capture chips
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
          const SizedBox(height: 18),
          // CTA
          GestureDetector(
            onTap: app.isGenerating
                ? null
                : app.activeProfile == null
                    ? () => _promptCreateProfile(app)
                    : () => _startGeneration(app),
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                gradient: app.activeProfile == null || app.isGenerating
                    ? null
                    : TGradients.coral,
                color: app.activeProfile == null || app.isGenerating
                    ? const Color(0xFFE8E4D8)
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
                    Icon(
                      Icons.auto_fix_high_rounded,
                      color: app.activeProfile == null || app.isGenerating
                          ? TColors.inkFaint
                          : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      app.isGenerating ? 'Weaving magic…' : 'Create Story',
                      style: TextStyle(
                        color: app.activeProfile == null || app.isGenerating
                            ? TColors.inkFaint
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

  // ── F3 · Clarification card ────────────────────────────────────────

  Widget _buildClarificationCard(AppState app) {
    return TCard(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
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
                child: const Text('🤔', style: TextStyle(fontSize: 20)),
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
          const SizedBox(height: 12),
          Text(
            app.pendingClarification ?? '',
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
              controller: _clarifyController,
              maxLines: 2,
              maxLength: 300,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Add the missing detail…',
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                final answer = _clarifyController.text.trim();
                if (answer.isEmpty) return;
                app.answerClarification(answer);
                _clarifyController.clear();
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
    );
  }

  Widget _buildProgress(AppState app) {
    final activeIdx =
        _agentSteps.indexWhere((s) => s.$1 == app.currentAgent);
    return TCard(
      gradient: TGradients.night,
      radius: 28,
      padding: const EdgeInsets.all(24),
      shadows: TShadows.glowTeal,
      child: Column(
        children: [
          Text(
            app.generationStatus,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            app.progressPct > 0
                ? '${app.progressPct.toStringAsFixed(0)}% complete'
                : 'Sending your moment…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              // Indeterminate while uploading/transcribing (0%) — the bar
              // must always visibly move so the parent knows work is live.
              value: app.progressPct > 0 ? app.progressPct / 100 : null,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF2F9E97)),
            ),
          ),
          const SizedBox(height: 20),
          // Agent step chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_agentSteps.length, (i) {
              final step = _agentSteps[i];
              final done = activeIdx > i ||
                  app.progressPct >= ((i + 1) / _agentSteps.length) * 100;
              final active = activeIdx == i && !done;
              return Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: done
                          ? const Color(0xFF3BB8A9)
                          : active
                              ? const Color(0xFF2F9E97)
                              : Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2F9E97)
                                    .withValues(alpha: 0.5),
                                blurRadius: 16,
                              )
                            ]
                          : null,
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 20)
                          : Text(step.$2,
                              style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.$3,
                    style: TextStyle(
                      color: done || active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: TGradients.mint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child:
                    const Center(child: Text('📖', style: TextStyle(fontSize: 30))),
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

  void _startGeneration(AppState app) {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the moment first')),
      );
      return;
    }
    app.captureAndGenerate(text: text, locale: _selectedLocale);
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
    try {
      final transcript = await app.transcribeMoment(result.wavBytes);
      if (!mounted) return;
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
      await app.captureAndGeneratePhoto(
        imageBytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
        locale: _selectedLocale,
      );
    } catch (_) {
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
