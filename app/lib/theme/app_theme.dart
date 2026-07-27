/// TaleLah Design System — premium pastel gradient look.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TColors {
  // Brand
  static const coral = Color(0xFFFF6B4A);
  static const coralDark = Color(0xFFE8512F);
  static const violet = Color(0xFF7C6FF0);
  static const violetDeep = Color(0xFF5B4FD8);
  static const teal = Color(0xFF2EC4B6);
  static const amber = Color(0xFFFFB627);

  // Neutrals
  static const ink = Color(0xFF1E1B33);
  static const inkSoft = Color(0xFF56526E);
  static const inkFaint = Color(0xFF9A96B0);
  static const card = Colors.white;

  // Pastel chips
  static const peach = Color(0xFFFFEDE5);
  static const lavender = Color(0xFFEDEAFF);
  static const mint = Color(0xFFE0F7F1);
  static const lemon = Color(0xFFFFF6DC);
  static const blush = Color(0xFFFFE4EC);
  static const sky = Color(0xFFE3F1FF);

  // Backgrounds
  static const bgTop = Color(0xFFFDF4EF);
  static const bgMid = Color(0xFFF5F0FE);
  static const bgBottom = Color(0xFFEFF6FF);
}

class TGradients {
  static const page = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [TColors.bgTop, TColors.bgMid, TColors.bgBottom],
  );

  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B7CF6), Color(0xFF6C5CE7), Color(0xFF5B4FD8)],
  );

  static const coral = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8A65), Color(0xFFFF6B4A), Color(0xFFF4511E)],
  );

  static const night = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF232046), Color(0xFF191632)],
  );

  static const mint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF43D9B8), Color(0xFF2EC4B6)],
  );
}

class TShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: const Color(0xFF7C6FF0).withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> card = [
    BoxShadow(
      color: const Color(0xFF1E1B33).withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> glowViolet = [
    BoxShadow(
      color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> glowCoral = [
    BoxShadow(
      color: const Color(0xFFFF6B4A).withValues(alpha: 0.35),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
  ];
}

class TaleLahTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TColors.coral,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: TColors.ink, displayColor: TColors.ink);

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: TColors.ink,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

/// Reusable premium card container.
class TCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? color;
  final double radius;
  final List<BoxShadow>? shadows;

  const TCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.color,
    this.radius = 24,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? TColors.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows ?? TShadows.card,
      ),
      child: child,
    );
  }
}
