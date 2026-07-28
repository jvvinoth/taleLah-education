/// Mina the Myna — the child-mode companion (F7, AC-03).
/// Exactly 8 states; emoji/shape placeholders until the Sprint-5 art pass.
/// Behaviour is identical whatever the art — the state machine is the spec.
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The full, closed set of Mina states — never add a ninth casually:
/// the purity test asserts this count.
enum MinaState {
  idle,
  listening,
  encouraging,
  celebrating,
  thinking,
  demonstrating,
  waiting,
  goodbye,
}

class Mina extends StatelessWidget {
  final MinaState state;
  final double size;

  const Mina({super.key, this.state = MinaState.idle, this.size = 64});

  static const Map<MinaState, String> _badge = {
    MinaState.idle: '🪶',
    MinaState.listening: '👂',
    MinaState.encouraging: '💪',
    MinaState.celebrating: '🎉',
    MinaState.thinking: '💭',
    MinaState.demonstrating: '🗣️',
    MinaState.waiting: '🌙',
    MinaState.goodbye: '👋',
  };

  static const Map<MinaState, Color> _glow = {
    MinaState.idle: TColors.teal,
    MinaState.listening: TColors.coral,
    MinaState.encouraging: TColors.gold,
    MinaState.celebrating: TColors.teal,
    MinaState.thinking: TColors.tealDeep,
    MinaState.demonstrating: TColors.coral,
    MinaState.waiting: TColors.tealDeep,
    MinaState.goodbye: TColors.gold,
  };

  @override
  Widget build(BuildContext context) {
    final wave =
        state == MinaState.celebrating || state == MinaState.goodbye;
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_glow[state] ?? TColors.teal)
                      .withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                  color: Colors.white, width: size >= 80 ? 4 : 2.5),
            ),
            child: ClipOval(
              child: Image.asset(
                wave ? TBrand.mascotWave : TBrand.mascot,
                fit: BoxFit.cover,
                alignment:
                    wave ? const Alignment(0, -0.55) : Alignment.center,
              ),
            ),
          ),
          // State badge — the placeholder "acting" until real art lands.
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: TShadows.card,
              ),
              child: Text(
                _badge[state] ?? '🪶',
                style: TextStyle(fontSize: size * 0.28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
