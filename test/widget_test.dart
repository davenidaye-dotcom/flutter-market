import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:letou_app/app.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LetouApp()));
    await tester.pumpAndSettle();
    expect(find.text('乐投'), findsWidgets);
  });
}
