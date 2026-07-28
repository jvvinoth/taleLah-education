/// Device simulator frame — desktop web browsers only.
/// Shows the app inside a phone or tablet frame with portrait/landscape
/// switching for demos. On native mobile AND mobile browsers (iOS/Android
/// user agents) the app renders full-bleed and none of this UI appears.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

enum _SimDevice { phone, tablet }

class MobileFrame extends StatefulWidget {
  final Widget child;
  const MobileFrame({super.key, required this.child});

  @override
  State<MobileFrame> createState() => _MobileFrameState();
}

class _MobileFrameState extends State<MobileFrame> {
  _SimDevice _device = _SimDevice.phone;
  bool _landscape = false;

  // Logical device sizes (portrait) — iPhone 14 / iPad Air class.
  static const Size _phoneSize = Size(390, 844);
  static const Size _tabletSize = Size(820, 1180);

  /// Desktop web browser only — a mobile browser reports iOS/Android
  /// as its target platform, so it (and native mobile) is excluded.
  static bool get _isDesktopWeb {
    if (!kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
    }
  }

  Size get _logicalSize {
    final base = _device == _SimDevice.phone ? _phoneSize : _tabletSize;
    return _landscape ? Size(base.height, base.width) : base;
  }

  EdgeInsets get _simPadding {
    if (_device == _SimDevice.tablet) {
      return const EdgeInsets.only(top: 28, bottom: 16);
    }
    return _landscape
        ? const EdgeInsets.only(left: 36, top: 12, bottom: 16)
        : const EdgeInsets.only(top: 36, bottom: 20);
  }

  @override
  Widget build(BuildContext context) {
    // Real mobile device or mobile browser → full bleed, no simulator.
    if (!_isDesktopWeb) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Very narrow desktop window → behave like mobile.
        if (constraints.maxWidth < 560) return widget.child;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6EFE0), Color(0xFFFBF5EA), Color(0xFFE7F2EE)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 76, 24, 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _deviceShell(context),
                  ),
                ),
              ),
              // Simulator controls — top-right pill
              Positioned(top: 16, right: 20, child: _controls()),
            ],
          ),
        );
      },
    );
  }

  // ── Device shell (bezel + screen at true logical size) ────────────────

  Widget _deviceShell(BuildContext context) {
    final size = _logicalSize;
    final isPhone = _device == _SimDevice.phone;
    final bezel = isPhone ? 10.0 : 14.0;
    final outerRadius = isPhone ? 48.0 : 36.0;
    final innerRadius = isPhone ? 38.0 : 22.0;

    return Container(
      width: size.width + bezel * 2,
      height: size.height + bezel * 2,
      decoration: BoxDecoration(
        color: const Color(0xFF232D3A),
        borderRadius: BorderRadius.circular(outerRadius),
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
      padding: EdgeInsets.all(bezel),
      child: Stack(
        children: [
          // Screen
          ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: MediaQuery(
              // Report true device metrics so screens lay out natively
              data: MediaQuery.of(context).copyWith(
                size: size,
                padding: _simPadding,
              ),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: widget.child,
              ),
            ),
          ),
          if (isPhone) _notch() else _cameraDot(),
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
    );
  }

  Widget _notch() {
    final pill = Container(
      width: _landscape ? 26 : 110,
      height: _landscape ? 110 : 26,
      decoration: BoxDecoration(
        color: const Color(0xFF232D3A),
        borderRadius: BorderRadius.circular(20),
      ),
    );
    return _landscape
        ? Positioned(left: 10, top: 0, bottom: 0, child: Center(child: pill))
        : Positioned(top: 10, left: 0, right: 0, child: Center(child: pill));
  }

  Widget _cameraDot() {
    final dot = Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFF10161F),
        shape: BoxShape.circle,
      ),
    );
    return _landscape
        ? Positioned(left: 6, top: 0, bottom: 0, child: Center(child: dot))
        : Positioned(top: 6, left: 0, right: 0, child: Center(child: dot));
  }

  // ── Simulator controls ────────────────────────────────────────────────

  Widget _controls() {
    // The frame sits above MaterialApp's content (builder:), so the pill
    // needs its own Material for InkWell ripples and hit-testing.
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(999),
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E3A4A).withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segButton(
            icon: Icons.phone_iphone_rounded,
            label: 'Phone',
            selected: _device == _SimDevice.phone,
            onTap: () => setState(() => _device = _SimDevice.phone),
          ),
          _segButton(
            icon: Icons.tablet_mac_rounded,
            label: 'Tablet',
            selected: _device == _SimDevice.tablet,
            onTap: () => setState(() => _device = _SimDevice.tablet),
          ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: TColors.ink.withValues(alpha: 0.10),
          ),
          Tooltip(
            message:
                _landscape ? 'Switch to portrait' : 'Switch to landscape',
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _landscape = !_landscape),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _landscape
                      ? TColors.teal.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  Icons.screen_rotation_rounded,
                  size: 18,
                  color: _landscape
                      ? TColors.teal
                      : TColors.ink.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _segButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? TColors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? Colors.white
                  : TColors.ink.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : TColors.ink.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
