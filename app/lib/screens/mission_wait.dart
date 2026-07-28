/// Mission Wait — F8 (AC-05). Once the room mission starts, the screen gets
/// out of the way: dimmed, animation-free, a single "I'm back!" button.
/// The child is in the ROOM, not on the screen.
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/mina.dart';

class MissionWaitScreen extends StatelessWidget {
  final String missionText;
  final String missionEnglish;

  const MissionWaitScreen({
    super.key,
    required this.missionText,
    this.missionEnglish = '',
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // Deliberately static: no AnimatedContainer, no gradients that pulse,
    // no progress spinners — nothing competes with the real world.
    return PopScope(
      canPop: false, // child mode — system back stays blocked (AC-03)
      child: Scaffold(
        backgroundColor: const Color(0xFF1F2933), // dimmed night surface
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 24, 32, bottomPad + 28),
            child: Column(
              children: [
                const Spacer(),
                const Mina(state: MinaState.waiting, size: 88),
                const SizedBox(height: 28),
                Text(
                  missionText,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (missionEnglish.isNotEmpty &&
                    missionEnglish != missionText) ...[
                  const SizedBox(height: 10),
                  Text(
                    missionEnglish,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.55),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Mina is waiting for you…',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                // The single way back — big, obvious, ≥56 dp.
                GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    height: 64,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: TGradients.mint,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🙌', style: TextStyle(fontSize: 22)),
                          SizedBox(width: 10),
                          Text(
                            "I'm back!",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
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
    );
  }
}
