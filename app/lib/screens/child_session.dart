/// Child Session — interactive story playback with narration and choices.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
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
      color: const Color(0xFFFFE0E0),
    ),
    _DemoScene(
      title: 'At the Station',
      narration: 'ரயில் நிலையத்தில் அருண் காத்திருந்தான்.',
      english: 'Arun waited at the station.',
      emoji: '🚉',
      interaction: 'choice',
      prompt: 'What color is the train? Red or Blue?',
      choices: ['Red (சிவப்பு)', 'Blue (நீலம்)'],
      color: const Color(0xFFE0F0FF),
    ),
    _DemoScene(
      title: 'The Journey',
      narration: 'ரயில் வேகமாக சென்றது! மஞ்சள் பூக்கள் தெரிந்தன.',
      english: 'The train went fast! Yellow flowers were visible.',
      emoji: '🌻',
      interaction: 'speak',
      prompt: 'Say "மஞ்சள்" (manjal — yellow)!',
      color: const Color(0xFFFFF8E0),
    ),
    _DemoScene(
      title: 'Mission Time!',
      narration: 'உன் அறையில் சிவப்பு பொருள் கண்டுபிடி!',
      english: 'Find something RED in your room!',
      emoji: '🎯',
      interaction: 'mission',
      prompt: 'Go find something red and show it to Amma/Appa!',
      color: const Color(0xFFE8F5E9),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (_sessionComplete) {
      return _buildCompleteScreen(app);
    }

    final scene = _demoScenes[_currentScene];

    return Scaffold(
      backgroundColor: scene.color,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_currentScene + 1) / _demoScenes.length,
                      backgroundColor: Colors.white60,
                      color: const Color(0xFFFF6B35),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_currentScene + 1}/${_demoScenes.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            // Scene content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Big emoji
                    Text(
                      scene.emoji,
                      style: const TextStyle(fontSize: 80),
                    ),
                    const SizedBox(height: 16),

                    // Scene title
                    Text(
                      scene.title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Target language narration
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            scene.narration,
                            style: const TextStyle(fontSize: 22),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            scene.english,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Interaction area
                    _buildInteraction(scene),
                  ],
                ),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentScene > 0)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _currentScene--),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton.icon(
                    onPressed: () => _nextScene(),
                    icon: Icon(_currentScene == _demoScenes.length - 1
                        ? Icons.check
                        : Icons.arrow_forward),
                    label: Text(_currentScene == _demoScenes.length - 1
                        ? 'Finish!'
                        : 'Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
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

  Widget _buildInteraction(_DemoScene scene) {
    switch (scene.interaction) {
      case 'speak':
        return Column(
          children: [
            Text(
              scene.prompt,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _isPlaying = !_isPlaying),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isPlaying
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFF2E86AB),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isPlaying ? 'Listening...' : 'Tap to speak',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        );

      case 'choice':
        return Column(
          children: [
            Text(
              scene.prompt,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...?scene.choices?.map((choice) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _nextScene(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(
                            color: Color(0xFF2E86AB), width: 2),
                      ),
                      child: Text(choice,
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                )),
          ],
        );

      case 'mission':
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.explore, color: Colors.white, size: 48),
              const SizedBox(height: 8),
              Text(
                scene.prompt,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FamilyModeScreen()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFFF6B35),
                ),
                child: const Text('Start Family Mission'),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF0FFF0),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 80)),
                const SizedBox(height: 16),
                const Text(
                  'Great job today!',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${app.activeProfile?.alias ?? "Little one"} learned new Tamil words!',
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Text('🌱 Next time, try:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Describe the color of your favorite toy in Tamil!',
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.home),
                  label: const Text('Back to Home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
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
  final Color color;

  const _DemoScene({
    required this.title,
    required this.narration,
    required this.english,
    required this.emoji,
    required this.interaction,
    required this.prompt,
    this.choices,
    this.color = Colors.white,
  });
}
