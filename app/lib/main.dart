/// TaleLah — Family Language Companion
/// Everyday moments. Mother-tongue magic.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/parent_home.dart';
import 'services/api_client.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.light,
        ),
        fontFamily: 'Nunito',
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
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
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🐦', style: TextStyle(fontSize: 64)),
              SizedBox(height: 16),
              Text('TaleLah',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Everyday moments. Mother-tongue magic.',
                  style: TextStyle(color: Colors.grey)),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFFFF6B35)),
            ],
          ),
        ),
      );
    }

    return const ParentHomeScreen();
  }
}
