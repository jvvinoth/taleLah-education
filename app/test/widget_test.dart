import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:talelah/main.dart';
import 'package:talelah/providers/app_state.dart';
import 'package:talelah/services/api_client.dart';

void main() {
  testWidgets('App launches without crashing', (tester) async {
    // Just verify the app widget builds (unroutable port → offline splash)
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: ApiClient(baseUrl: 'http://127.0.0.1:9')),
        child: const TaleLahApp(),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
