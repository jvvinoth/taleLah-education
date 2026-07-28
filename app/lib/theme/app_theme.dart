/// TaleLah Design System — warm storybook look drawn from the myna logo:
/// ink navy, scarf teal, book gold, coral accents on a cream canvas.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TColors {
  // Brand — sampled from the TaleLah myna logo
  static const ink = Color(0xFF2E3A4A); // wordmark navy
  static const teal = Color(0xFF2F9E97); // scarf / speech bubble
  static const tealDeep = Color(0xFF1F7B75);
  static const gold = Color(0xFFF2B843); // book / beak
  static const goldDeep = Color(0xFFB07E1F);
  static const coral = Color(0xFFEE7752); // reading lines / feet
  static const coralDark = Color(0xFFD95C38);

  // Neutrals
  static const inkSoft = Color(0xFF5D6B7A);
  static const inkFaint = Color(0xFF9AA7B2);
  static const card = Colors.white;

  // Pastel chips
  static const peach = Color(0xFFFCE8DE);
  static const mist = Color(0xFFE0F0EE); // soft teal wash
  static const mint = Color(0xFFE2F3EA);
  static const lemon = Color(0xFFFBF0D2);
  static const blush = Color(0xFFFBE3DA);
  static const sky = Color(0xFFE3EEF4);

  // Backgrounds — warm cream like the logo canvas
  static const bgTop = Color(0xFFFBF6EC);
  static const bgMid = Color(0xFFF8F3E7);
  static const bgBottom = Color(0xFFF0F5EE);
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
    colors: [Color(0xFF3BAFA6), Color(0xFF2F9E97), Color(0xFF1F7B75)],
  );

  static const coral = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF69066), Color(0xFFEE7752), Color(0xFFD95C38)],
  );

  static const night = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF33404F), Color(0xFF232D3A)],
  );

  static const mint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3BB8A9), Color(0xFF2F9E97)],
  );

  static const gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF6C55E), Color(0xFFF2B843)],
  );
}

class TShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: const Color(0xFF2F9E97).withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> card = [
    BoxShadow(
      color: const Color(0xFF2E3A4A).withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> glowTeal = [
    BoxShadow(
      color: const Color(0xFF2F9E97).withValues(alpha: 0.35),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> glowCoral = [
    BoxShadow(
      color: const Color(0xFFEE7752).withValues(alpha: 0.35),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
  ];
}

/// Brand assets.
class TBrand {
  static const wordmark = 'assets/images/logo_wordmark.jpg';
  static const mascot = 'assets/images/mascot.jpg';
  static const mascotWave = 'assets/images/mascot_wave.jpg';
}

class TaleLahTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TColors.teal,
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

/// Circular mascot avatar — the TaleLah myna.
class TMascot extends StatelessWidget {
  final double size;
  final bool wave;

  const TMascot({super.key, this.size = 52, this.wave = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: TShadows.glowTeal,
        border: Border.all(color: Colors.white, width: size >= 80 ? 4 : 2.5),
      ),
      child: ClipOval(
        child: Image.asset(
          wave ? TBrand.mascotWave : TBrand.mascot,
          fit: BoxFit.cover,
          alignment: wave ? const Alignment(0, -0.55) : Alignment.center,
        ),
      ),
    );
  }
}
