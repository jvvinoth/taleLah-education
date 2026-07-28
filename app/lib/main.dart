/// TaleLah — Family Language Companion
/// Everyday moments. Mother-tongue magic.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
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

/// Gate that waits for initialization then shows parent home.
class SplashGate extends StatelessWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.isLoggedIn) {
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
