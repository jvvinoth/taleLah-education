import 'package:flutter_test/flutter_test.dart';
import 'package:talelah/main.dart';

void main() {
  testWidgets('App launches without crashing', (tester) async {
    // Just verify the app widget builds
    await tester.pumpWidget(const TaleLahApp());
    expect(find.text('TaleLah'), findsOneWidget);
  });
}
