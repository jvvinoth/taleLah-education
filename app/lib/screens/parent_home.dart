/// Parent Home — premium moment capture + story review.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/community_event.dart';
import '../models/story_package.dart';
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
  // Story engine: 'new' (book-first — outline in seconds, pages stream in) is
  // the default; 'classic' stays available behind the ⚙ sheet for A/B. This
  // resets on every web reload, so the default IS the product experience.
  String _selectedEngine = 'new';

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

  // Home previews — the child's own books and what's on nearby, so the home
  // screen shows there is a product here, not just a form.
  List<StoryPackageSummary> _recentStories = [];
  List<CommunityEvent> _nearbyEvents = [];
  String _previewProfileId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreviews());
  }

  @override
  void dispose() {
    _momentMic.dispose();
    _earcons.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Best-effort: a preview row that fails just stays hidden.
  Future<void> _loadPreviews() async {
    final app = context.read<AppState>();
    final profileId = app.activeProfile?.id ?? '';
    _previewProfileId = profileId;
    try {
      final stories = await app.api.listPackages(childProfileId: profileId);
      if (mounted) {
        setState(() => _recentStories =
            stories.where((s) => s.status == 'approved').take(6).toList());
      }
    } catch (_) {/* row hides itself */}
    try {
      final events = await app.api.getEvents();
      if (mounted) setState(() => _nearbyEvents = events.take(6).toList());
    } catch (_) {/* row hides itself */}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topPad = MediaQuery.of(context).padding.top;
    _maybeShowCaptureError(app);
    _maybeShowClarification(app);
    _maybeFlashComplete(app);
    // Switching child (or finishing a story) changes what belongs in the
    // preview rows — refresh them once, after this frame.
    final activeId = app.activeProfile?.id ?? '';
    if (activeId != _previewProfileId) {
      _previewProfileId = activeId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreviews());
    }

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
                  const SizedBox(height: 22),
                  _buildGreeting(app),
                  const SizedBox(height: 14),
                  // The prompt is the page — everything else is secondary.
                  _buildMomentCapture(app),
                  const SizedBox(height: 18),
                  _buildStarterChips(app),
                  const SizedBox(height: 22),
                  if (app.latestPackage != null && !app.isGenerating) ...[
                    _buildSectionTitle('Story Ready', 'Review & play together'),
                    const SizedBox(height: 12),
                    _buildPackageCard(app),
                    const SizedBox(height: 22),
                  ],
                  _buildLibraryRow(app),
                  if (_recentStories.isNotEmpty) const SizedBox(height: 22),
                  _buildEventsRow(app),
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

  /// Top bar — brand on the left, the child you're making a story for on the
  /// right. The switcher lives here rather than buried in a card, so twins and
  /// mixed-language homes are always one tap apart.
  Widget _buildHeader(AppState app) {
    return Row(
      children: [
        const TMascot(size: 38),
        const SizedBox(width: 9),
        const Text(
          'TaleLah',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: TColors.ink,
          ),
        ),
        const Spacer(),
        _kidSwitcherButton(app),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _openSettingsSheet(app),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: TShadows.card,
            ),
            child: const Icon(Icons.tune_rounded,
                color: TColors.inkSoft, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _kidSwitcherButton(AppState app) {
    final kid = app.activeProfile;
    final initial =
        (kid?.alias.trim().isNotEmpty ?? false) ? kid!.alias.trim()[0].toUpperCase() : '+';
    return GestureDetector(
      onTap: () => _openKidSwitcher(app),
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: TShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: TColors.gold,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: TColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              kid?.alias ?? 'Add child',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: TColors.ink,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: TColors.inkFaint),
          ],
        ),
      ),
    );
  }

  /// Whose story today — every child, their age band and language, plus a way
  /// to add another. Replaces hunting through the profile tab.
  void _openKidSwitcher(AppState app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3DCCB),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Whose story today?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: TColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            ...app.profiles.map((p) {
              final selected = p.id == app.activeProfile?.id;
              final lang = _locales.firstWhere(
                (l) => l.$1 == p.targetLocale,
                orElse: () => ('', '', ''),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    app.selectProfile(p);
                    setState(() => _selectedLocale = p.targetLocale);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: selected ? TColors.mist : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? TColors.teal : const Color(0xFFEDE8DA),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: TColors.gold,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            p.alias.trim().isNotEmpty
                                ? p.alias.trim()[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: TColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.alias,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: TColors.ink,
                                ),
                              ),
                              Text(
                                'Age ${p.ageBand}'
                                '${lang.$2.isEmpty ? '' : ' · ${lang.$2} ${lang.$3}'}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: TColors.inkFaint,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check_circle_rounded,
                              color: TColors.teal, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _promptCreateProfile(app);
              },
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE3DCCB),
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: TColors.inkSoft),
                    SizedBox(width: 6),
                    Text(
                      'Add another child',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: TColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Story engine is a testing control, not a parenting decision — it lives
  /// behind the tune icon instead of on the home screen.
  void _openSettingsSheet(AppState app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3DCCB),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Story engine',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'New writes the whole book at once and reads faster.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: TColors.inkFaint,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              _engineToggle(onChanged: () => setSheet(() {})),
              const SizedBox(height: 10),
            ],
          ),
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

  /// The prompt box — this IS the home screen. One inviting field, with voice,
  /// photo and language as small controls inside it, and a single Create.
  Widget _buildMomentCapture(AppState app) {
    final busy = app.isGenerating;
    final lang = _locales.firstWhere(
      (l) => l.$1 == _selectedLocale,
      orElse: () => _locales.first,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: TColors.teal, width: 2),
        boxShadow: [
          BoxShadow(
            color: TColors.teal.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isTranscribing)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildTranscribingStrip(),
            )
          else
            TextField(
              controller: _textController,
              maxLines: 4,
              minLines: 2,
              maxLength: 500,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, height: 1.45),
              decoration: const InputDecoration(
                hintText:
                    'Tell me anything…\n“He built an MRT out of blocks”\nor “Explain how frogs live”',
                hintStyle: TextStyle(
                  color: TColors.inkFaint,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
                counterText: '',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          const Divider(height: 18, color: Color(0xFFEDE8DA)),
          Row(
            children: [
              _toolIcon(
                emoji: _voiceOverlayVisible ? '🔴' : '🎙️',
                active: _voiceOverlayVisible,
                onTap: busy || _voiceOverlayVisible
                    ? null
                    : app.activeProfile == null
                        ? () => _promptCreateProfile(app)
                        : () => _startVoiceCapture(app),
              ),
              const SizedBox(width: 7),
              _toolIcon(
                emoji: '📷',
                active: false,
                onTap: busy || _voiceOverlayVisible
                    ? null
                    : app.activeProfile == null
                        ? () => _promptCreateProfile(app)
                        : () => _pickPhoto(app),
              ),
              const SizedBox(width: 7),
              // Language lives here as a compact pill instead of a whole row.
              GestureDetector(
                onTap: busy ? null : () => _openLanguagePicker(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: TColors.mist,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    lang.$2,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: TColors.tealDeep,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: app.activeProfile == null
                    ? () => _promptCreateProfile(app)
                    : busy
                        ? () => setState(() => _progressDismissed = false)
                        : () => _startGeneration(app),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    gradient: app.activeProfile == null || busy
                        ? null
                        : TGradients.coral,
                    color: app.activeProfile == null
                        ? const Color(0xFFE8E4D8)
                        : busy
                            ? TColors.mist
                            : null,
                    borderRadius: BorderRadius.circular(21),
                    boxShadow: app.activeProfile == null || busy
                        ? null
                        : TShadows.glowCoral,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: TColors.teal),
                        )
                      else
                        Icon(Icons.auto_fix_high_rounded,
                            size: 17,
                            color: app.activeProfile == null
                                ? TColors.inkFaint
                                : Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        busy ? 'Creating…' : 'Create',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: app.activeProfile == null
                              ? TColors.inkFaint
                              : busy
                                  ? TColors.teal
                                  : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Personal, and doubles as the instruction — it tells the parent exactly
  /// what to type without a paragraph of marketing copy.
  Widget _buildGreeting(AppState app) {
    final name = app.activeProfile?.alias;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.4,
              color: TColors.ink,
            ),
            children: name == null
                ? const [TextSpan(text: 'What shall we make today?')]
                : [
                    const TextSpan(text: 'What did '),
                    TextSpan(
                      text: name,
                      style: const TextStyle(color: TColors.tealDeep),
                    ),
                    const TextSpan(text: ' do today?'),
                  ],
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Or pick an idea below — a story takes 5 minutes',
          style: TextStyle(
            fontSize: 12.5,
            color: TColors.inkFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// A blank box makes parents freeze. These are the first tap for most
  /// people, so they double as the product's tone of voice.
  static const _starters = [
    ('🐸', 'How frogs live'),
    ('🚉', 'A ride on the MRT'),
    ('🍲', 'Helping in the kitchen'),
    ('🌧️', 'Why does it rain?'),
    ('🦁', 'A brave little lion'),
    ('🌙', 'Going to sleep'),
  ];

  Widget _buildStarterChips(AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TRY ONE OF THESE',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: TColors.inkFaint,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: _starters.map((s) {
            return GestureDetector(
              onTap: app.isGenerating
                  ? null
                  : () {
                      setState(() {
                        _textController.text = s.$2;
                        _textController.selection = TextSelection.collapsed(
                            offset: _textController.text.length);
                      });
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEDE8DA)),
                  boxShadow: TShadows.card,
                ),
                child: Text(
                  '${s.$1}  ${s.$2}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: TColors.inkSoft,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Small header for a preview row, with a tap-through to the full screen.
  Widget _rowHeader(String title, String action, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: Row(
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: TColors.tealDeep,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 17, color: TColors.tealDeep),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The child's own bookshelf — the thing that brings a parent back.
  Widget _buildLibraryRow(AppState app) {
    if (_recentStories.isEmpty) return const SizedBox.shrink();
    const covers = [
      TGradients.mint,
      TGradients.gold,
      TGradients.coral,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowHeader('📚 Story library', 'See all', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StoriesLibraryScreen()),
          );
        }),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: _recentStories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final s = _recentStories[i];
              return GestureDetector(
                onTap: () async {
                  final ok = await app.loadApprovedStory(s.id);
                  if (!mounted) return;
                  if (ok) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ChildSessionScreen()),
                    );
                  }
                },
                child: SizedBox(
                  width: 86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: s.coverIllustrationUrl.isEmpty
                              ? covers[i % covers.length]
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: TShadows.card,
                          image: s.coverIllustrationUrl.isEmpty
                              ? null
                              : DecorationImage(
                                  image:
                                      NetworkImage(s.coverIllustrationUrl),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        alignment: Alignment.center,
                        child: s.coverIllustrationUrl.isEmpty
                            ? const Text('📖',
                                style: TextStyle(fontSize: 28))
                            : null,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        s.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: TColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// What's on nearby — mother tongue lives outside the app too.
  Widget _buildEventsRow(AppState app) {
    if (_nearbyEvents.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowHeader('🎪 Near you', 'See all', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CommunityEventsScreen()),
          );
        }),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: _nearbyEvents.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final e = _nearbyEvents[i];
              return Container(
                width: 168,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEDE8DA)),
                  boxShadow: TShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [e.date, e.time].where((t) => t.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: TColors.coral,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: TColors.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      e.venue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: TColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolIcon({
    required String emoji,
    required bool active,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? TColors.coral : const Color(0xFFF3EFE3),
          shape: BoxShape.circle,
          boxShadow: active ? TShadows.glowCoral : null,
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  void _openLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3DCCB),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Story language',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: TColors.ink),
            ),
            const SizedBox(height: 12),
            ..._locales.map((l) {
              final selected = _selectedLocale == l.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedLocale = l.$1);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected ? TColors.mist : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            selected ? TColors.teal : const Color(0xFFEDE8DA),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(l.$2,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TColors.ink)),
                        const SizedBox(width: 8),
                        Text(l.$3,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: TColors.inkFaint)),
                        const Spacer(),
                        if (selected)
                          const Icon(Icons.check_circle_rounded,
                              color: TColors.teal, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),
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

  /// Sprint 0 — Classic vs New (beta) story engine. New routes to the
  /// book-first flow; Classic is unchanged. Lets us A/B and demo before/after.
  Widget _engineToggle({VoidCallback? onChanged}) {
    Widget opt(String value, String label, String sub) {
      final on = _selectedEngine == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedEngine = value);
            onChanged?.call();
          },
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
      // Ask the picker to re-encode: on iOS this turns a HEIC straight into a
      // JPEG, and the smaller size keeps the upload well inside its timeout.
      // The server sniffs the real format anyway, so this is belt-and-braces.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _captureError('Photo too large — try a smaller one');
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
      // Surface the server's reason (e.g. an unsupported format) instead of a
      // blanket failure the parent can't act on.
      final msg = e.toString().replaceFirst('Exception: ', '');
      _captureError(msg.isEmpty
          ? 'Could not read that photo — try typing instead'
          : msg);
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
