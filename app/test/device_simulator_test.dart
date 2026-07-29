/// Device simulator (web demo frame) — verifies the desktop-web-only
/// phone/tablet controls actually resize the app's MediaQuery.
/// Run with: flutter test --platform chrome
///
/// On the VM (non-web) this suite is skipped: the simulator must never
/// activate off desktop web, which is itself asserted here.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talelah/theme/mobile_frame.dart';

/// Probe that records the MediaQuery size the framed app actually receives.
class _SizeProbe extends StatelessWidget {
  static Size? lastSize;
  const _SizeProbe();

  @override
  Widget build(BuildContext context) {
    lastSize = MediaQuery.of(context).size;
    return const ColoredBox(color: Colors.white);
  }
}

/// The test binding forces defaultTargetPlatform to android; the simulator
/// gates on it, so desktop-web cases must override to a desktop platform.
/// The override is reset in a finally block — the binding verifies foundation
/// vars before package:test teardowns run, so addTearDown is too late.
Future<void> _withPlatform(
  WidgetTester tester,
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MobileFrame(child: _SizeProbe()),
      ),
    );
    await tester.pumpAndSettle();
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
  }
}

void main() {
  group('Device simulator frame', () {
    testWidgets('hidden on mobile (native app / iOS-Android browser)',
        (tester) async {
      // A mobile browser reports iOS/Android as target platform on web,
      // so this asserts both the native and mobile-browser cases.
      await _withPlatform(tester, TargetPlatform.iOS, () async {
        expect(find.text('Phone'), findsNothing);
        expect(find.text('Tablet'), findsNothing);
      });
    });

    testWidgets('desktop web: controls shown, defaults to phone portrait',
        (tester) async {
      if (!kIsWeb) return;
      await _withPlatform(tester, TargetPlatform.macOS, () async {
        expect(find.text('Phone'), findsOneWidget);
        expect(find.text('Tablet'), findsOneWidget);
        expect(_SizeProbe.lastSize, const Size(390, 844));
      });
    });

    testWidgets('desktop web: switch to tablet and back to phone',
        (tester) async {
      if (!kIsWeb) return;
      await _withPlatform(tester, TargetPlatform.macOS, () async {
        await tester.tap(find.text('Tablet'));
        await tester.pumpAndSettle();
        expect(_SizeProbe.lastSize, const Size(820, 1180));

        await tester.tap(find.text('Phone'));
        await tester.pumpAndSettle();
        expect(_SizeProbe.lastSize, const Size(390, 844));
      });
    });
  });
}
