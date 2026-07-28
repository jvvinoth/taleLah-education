/// Child Session — premium interactive story playback with narration and choices.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'family_mode.dart';

class ChildSessionScreen extends StatefulWidget {
  const ChildSessionScreen({super.key});

  @override
  State<ChildSessionScreen> createState() => _ChildSessionScreenState();
}

class _ChildSessionScreenState extends State<ChildSessionScreen> {
  int _currentScene = 0;
  bool _isPlaying = false;
  bool _sessionComplete = false;

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
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (_sessionComplete) {
      return _buildCompleteScreen(app);
    }

    final scene = _demoScenes[_currentScene];
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(gradient: scene.gradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // Top bar — close + progress dots
            Padding(
              padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 0),
              child: Row(
                children: [
                  _roundButton(
                    Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  ...List.generate(_demoScenes.length, (i) {
                    final active = i == _currentScene;
                    final done = i < _currentScene;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
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
                      '${_currentScene + 1}/${_demoScenes.length}',
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: TColors.mist,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '🔊 LISTEN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: TColors.tealDeep,
                                    letterSpacing: 0.8,
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
                      onTap: () => setState(() => _currentScene--),
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _nextScene,
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        gradient: _currentScene == _demoScenes.length - 1
                            ? TGradients.mint
                            : TGradients.coral,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _currentScene == _demoScenes.length - 1
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
                            _currentScene == _demoScenes.length - 1
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
                            _currentScene == _demoScenes.length - 1
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
      ),
    );
  }

  Widget _roundButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: TShadows.card,
        ),
        child: Icon(icon, color: TColors.ink, size: 20),
      ),
    );
  }

  Widget _buildInteraction(_DemoScene scene) {
    switch (scene.interaction) {
      case 'speak':
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
            const SizedBox(height: 16),
            // Gradient mic ring
            GestureDetector(
              onTap: () => setState(() => _isPlaying = !_isPlaying),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  gradient:
                      _isPlaying ? TGradients.coral : TGradients.hero,
                  shape: BoxShape.circle,
                  boxShadow: _isPlaying
                      ? TShadows.glowCoral
                      : TShadows.glowTeal,
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
                  child: Icon(
                    _isPlaying ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isPlaying ? 'Listening…' : 'Tap to speak',
              style: const TextStyle(
                color: TColors.inkFaint,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );

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
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FamilyModeScreen()),
                ),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('👨‍👩‍👧', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text(
                        'Start Family Mission',
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
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  void _nextScene() {
    if (_currentScene < _demoScenes.length - 1) {
      setState(() {
        _currentScene++;
        _isPlaying = false;
      });
    } else {
      setState(() => _sessionComplete = true);
    }
  }

  Widget _buildCompleteScreen(AppState app) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(gradient: TGradients.page),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(28, 24, 28, bottomPad + 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: TGradients.mint,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TColors.teal.withValues(alpha: 0.35),
                          blurRadius: 50,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('🎉', style: TextStyle(fontSize: 64)),
                    ),
                  ),
                  const SizedBox(height: 28),
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
                  // Stat chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _statChip('🗣️', '2 words', TColors.peach),
                      const SizedBox(width: 10),
                      _statChip('📖', '4 scenes', TColors.mist),
                      const SizedBox(width: 10),
                      _statChip('🎯', '1 mission', TColors.mint),
                    ],
                  ),
                  const SizedBox(height: 24),
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
        ),
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
  });
}
