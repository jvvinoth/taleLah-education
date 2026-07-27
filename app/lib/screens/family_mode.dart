/// Family Mode — premium family participation in the child's learning journey.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class FamilyModeScreen extends StatefulWidget {
  const FamilyModeScreen({super.key});

  @override
  State<FamilyModeScreen> createState() => _FamilyModeScreenState();
}

class _FamilyModeScreenState extends State<FamilyModeScreen> {
  bool _missionComplete = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
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
              // Top bar
              Row(
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
              ),
              const SizedBox(height: 24),

              // Mission hero card
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'ROOM MISSION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Find something RED in your room and say its name in Tamil!',
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
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Phrase card
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: TColors.blush,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Column(
                        children: [
                          Text(
                            '🔴 சிவப்பு',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: TColors.ink,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'sivappu = RED',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: TColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: TColors.lavender,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        '"இது சிவப்பு" — idhu sivappu\n(this is red)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TColors.ink,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Mission complete button / celebration
              if (!_missionComplete)
                GestureDetector(
                  onTap: () => setState(() => _missionComplete = true),
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
                  shadows: TShadows.glowViolet,
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

              // Family talk time
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
                            child: Text('👨‍👩‍👧',
                                style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
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
                              'Ask these in Tamil',
                              style: TextStyle(
                                fontSize: 12,
                                color: TColors.inkFaint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildQuestion('What color is the train?',
                        'ரயில் என்ன நிறம்? (rayil enna niram?)', TColors.peach),
                    _buildQuestion('Where does the train go?',
                        'ரயில் எங்கே போகும்? (rayil enge pogum?)', TColors.mint),
                    _buildQuestion(
                        'Who rides the train?',
                        'யார் ரயிலில் போவார்கள்? (yaar rayilil povaargal?)',
                        TColors.lemon),
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
                            color: TColors.violetDeep, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Back to Story',
                          style: TextStyle(
                            color: TColors.violetDeep,
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
        ),
      ),
    );
  }

  Widget _buildQuestion(String english, String tamil, Color bg) {
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
          const Text('💬', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  english,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: TColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tamil,
                  style: const TextStyle(
                    fontSize: 13,
                    color: TColors.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
