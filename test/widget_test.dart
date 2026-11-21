import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_log/main.dart';

void main() {
  testWidgets('shows balance dashboard and asset choices', (tester) async {
    await tester.pumpWidget(const PiggyLogApp());

    expect(find.text('PiggyLog'), findsOneWidget);
    expect(find.text('Rp 0'), findsOneWidget);
    expect(find.text('+0% overall'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('No savings yet'), findsOneWidget);
    expect(find.text('Add savings'), findsWidgets);
  });
}
