/// Family Mode — premium family participation in the child's learning journey.
/// Renders the REAL approved Story Package (room mission + family handoff),
/// not a hardcoded sample. Shows a gentle empty state until a story is approved.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story_package.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class FamilyModeScreen extends StatefulWidget {
  const FamilyModeScreen({super.key});

  @override
  State<FamilyModeScreen> createState() => _FamilyModeScreenState();
}

class _FamilyModeScreenState extends State<FamilyModeScreen> {
  bool _missionComplete = false;

  void _completeMission(AppState app) {
    setState(() => _missionComplete = true);
    // Non-blocking — only lands if a live session exists (F8/F9).
    app.reportSessionEvent('mission_completed');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final story = app.approvedStory;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, bottomPad + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(context),
              const SizedBox(height: 24),
              if (story == null)
                _emptyState()
              else
                ..._missionContent(context, app, story),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: TShadows.card,
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: TColors.ink, size: 20),
          ),
        ),
        const Spacer(),
        const Text(
          'Family Mission',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: TColors.ink,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 44),
      ],
    );
  }

  Widget _emptyState() {
    return TCard(
      radius: 28,
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const TMascot(size: 72),
          const SizedBox(height: 16),
          const Text(
            'No family mission yet',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: TColors.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Capture a moment and approve a story — the family mission and '
            'the phrase to say together will appear right here.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: TColors.inkSoft.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _missionContent(
      BuildContext context, AppState app, ApprovedStory story) {
    final missionTarget = story.missionTargetLang.trim();
    final missionEnglish = story.mission.trim();
    final phraseTarget = story.targetPhrase.trim().isNotEmpty
        ? story.targetPhrase.trim()
        : story.handoffPromptTargetLang.trim();
    final phraseEnglish = story.handoffPrompt.trim();
    final responseSuggestion = story.handoffResponseSuggestion.trim();

    return [
      // Mission hero card — the real room mission
      TCard(
        gradient: TGradients.coral,
        radius: 28,
        padding: const EdgeInsets.all(26),
        shadows: TShadows.glowCoral,
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🎯', style: TextStyle(fontSize: 46)),
              ),
            ),
            const SizedBox(height: 16),
            _pill('ROOM MISSION'),
            const SizedBox(height: 12),
            Text(
              missionEnglish.isNotEmpty
                  ? missionEnglish
                  : 'Do this little mission together!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.4,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            if (missionTarget.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                missionTarget,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),

      // Phrase card — the real target phrase + target words
      if (phraseTarget.isNotEmpty || phraseEnglish.isNotEmpty)
        TCard(
          radius: 26,
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Text(
                '🗣️ SAY IT TOGETHER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: TColors.inkFaint,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 14),
              if (phraseTarget.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TColors.blush,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    phraseTarget,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: TColors.ink,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (phraseEnglish.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TColors.mist,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    phraseEnglish,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: TColors.ink,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (story.targetWords.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final w in story.targetWords) _wordChip(w),
                  ],
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: 20),

      // Mission complete button / celebration
      if (!_missionComplete)
        GestureDetector(
          onTap: () => _completeMission(app),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              gradient: TGradients.mint,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: TColors.teal.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Mission Complete!',
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
        )
      else
        TCard(
          gradient: TGradients.night,
          radius: 26,
          padding: const EdgeInsets.all(24),
          shadows: TShadows.glowTeal,
          child: Column(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              const Text(
                'Well done, family!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${app.activeProfile?.alias ?? "Your child"} is learning with your help!',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),

      // Family talk time — the real family handoff prompt + suggestion
      if (phraseEnglish.isNotEmpty || responseSuggestion.isNotEmpty)
        TCard(
          radius: 26,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: TColors.sky,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text('👨‍👩‍👧', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Family Talk Time',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: TColors.ink,
                          ),
                        ),
                        Text(
                          'Chat about the story together',
                          style: TextStyle(
                            fontSize: 12,
                            color: TColors.inkFaint,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (phraseEnglish.isNotEmpty)
                _talkRow(
                  '💬',
                  phraseEnglish,
                  story.handoffPromptTargetLang.trim(),
                  TColors.peach,
                ),
              if (responseSuggestion.isNotEmpty)
                _talkRow(
                  '🌟',
                  'A lovely reply to model',
                  responseSuggestion,
                  TColors.mint,
                ),
            ],
          ),
        ),
      const SizedBox(height: 24),

      // Back button
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: TShadows.card,
          ),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded,
                    color: TColors.tealDeep, size: 20),
                SizedBox(width: 8),
                Text(
                  'Back to Story',
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
    ];
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _wordChip(String word) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: TColors.lemon,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        word,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: TColors.ink,
        ),
      ),
    );
  }

  Widget _talkRow(String emoji, String primary, String secondary, Color bg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: TColors.ink,
                  ),
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    style: const TextStyle(
                      fontSize: 13,
                      color: TColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
