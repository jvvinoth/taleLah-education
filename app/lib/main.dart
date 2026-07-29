/// TaleLah — Family Language Companion
/// Everyday moments. Mother-tongue magic.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/auth/login_screen.dart';
import 'screens/parent_home.dart';
import 'services/api_client.dart';
import 'theme/app_theme.dart';
import 'theme/mobile_frame.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // API base URL — change for production
  const apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  final apiClient = ApiClient(baseUrl: apiBase);

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(api: apiClient)..initialize(),
      child: const TaleLahApp(),
    ),
  );
}

class TaleLahApp extends StatelessWidget {
  const TaleLahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaleLah',
      debugShowCheckedModeBanner: false,
      theme: TaleLahTheme.light(),
      // Show as a phone frame preview on wide (desktop browser) screens
      builder: (context, child) => MobileFrame(child: child!),
      home: const SplashGate(),
    );
  }
}

/// Gate that routes on auth state: spinner while restoring the session,
/// Login when there is none, ParentHome once signed in.
class SplashGate extends StatelessWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.isLoggedIn) {
      // Session restore finished without a login → show the Login screen.
      if (!app.isInitializing && app.initError == null) {
        return const LoginScreen();
      }
      final hasError = app.initError != null;
      return Container(
        decoration: const BoxDecoration(gradient: TGradients.page),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const TMascot(size: 116, wave: true),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    TBrand.wordmark,
                    width: 220,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Everyday moments. Mother-tongue magic.',
                  style: TextStyle(
                    color: TColors.inkSoft,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 36),
                if (hasError)
                  _RetryPanel(
                    message: app.initError!,
                    onRetry: app.initialize,
                  )
                else
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: TColors.teal,
                      strokeWidth: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return const ParentHomeScreen();
  }
}

/// Splash error state — a clear message plus a Retry button so a failed
/// backend health check / register never leaves the user on a dead spinner.
class _RetryPanel extends StatelessWidget {
  const _RetryPanel({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                gradient: TGradients.mint,
                borderRadius: BorderRadius.circular(18),
                boxShadow: TShadows.glowTeal,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Retry',
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
        ],
      ),
    );
  }
}
