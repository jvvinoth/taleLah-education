/// Parent Home — premium moment capture + story review.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'child_session.dart';
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

  static const _locales = [
    ('ta-SG', 'தமிழ்', 'Tamil'),
    ('zh-SG', '中文', 'Chinese'),
    ('ms-SG', 'Melayu', 'Malay'),
  ];

  @override
  void dispose() {
    _textController.dispose();
    _clarifyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topPad = MediaQuery.of(context).padding.top;

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
                  if (app.isGenerating) ...[
                    if (app.pendingClarification != null) ...[
                      _buildClarificationCard(app),
                      const SizedBox(height: 24),
                    ],
                    _buildProgress(app),
                    const SizedBox(height: 24),
                  ],
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
          ],
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
                'Vanakkam 👋',
                style: TextStyle(
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
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                p.alias.isNotEmpty ? p.alias[0].toUpperCase() : '🙂',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TColors.tealDeep,
                ),
              ),
            ),
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
            onTap: app.activeProfile == null || app.isGenerating
                ? null
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
            '${app.progressPct.toStringAsFixed(0)}% complete',
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
              value: app.progressPct / 100,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('👶', style: TextStyle(fontSize: 40),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'Add Your Child',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3E9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: "Child's name (e.g. Arun)",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  await app.createProfile(
                    alias: nameCtrl.text.trim(),
                    ageBand: '5-6',
                    targetLocale: _selectedLocale,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: TGradients.coral,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text(
                      'Add Child',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: TColors.inkFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
