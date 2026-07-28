/// Mobile frame — shows the app inside a phone-like frame on wide screens
/// (desktop browser), and full-bleed on actual mobile devices.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

class MobileFrame extends StatelessWidget {
  final Widget child;
  const MobileFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Real mobile / narrow window → full bleed
        if (constraints.maxWidth < 560) return child;

        // Desktop browser → centered phone frame
        final frameHeight = math.min(constraints.maxHeight - 48.0, 880.0);
        final frameWidth = math.min(frameHeight * 0.487, 420.0);

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6EFE0), Color(0xFFFBF5EA), Color(0xFFE7F2EE)],
            ),
          ),
          child: Center(
            child: Container(
              width: frameWidth,
              height: frameHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF232D3A),
                borderRadius: BorderRadius.circular(48),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E3A4A).withValues(alpha: 0.30),
                    blurRadius: 60,
                    offset: const Offset(0, 24),
                  ),
                  BoxShadow(
                    color: TColors.teal.withValues(alpha: 0.18),
                    blurRadius: 100,
                    offset: const Offset(0, 40),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: Stack(
                children: [
                  // Screen
                  ClipRRect(
                    borderRadius: BorderRadius.circular(38),
                    child: MediaQuery(
                      // Report the frame size so screens lay out as mobile
                      data: MediaQuery.of(context).copyWith(
                        size: Size(frameWidth - 20, frameHeight - 20),
                        padding: const EdgeInsets.only(top: 36, bottom: 20),
                      ),
                      child: child,
                    ),
                  ),
                  // Notch / Dynamic island
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 110,
                        height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFF232D3A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // Home indicator
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 120,
                        height: 5,
                        decoration: BoxDecoration(
                          color: TColors.ink.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
