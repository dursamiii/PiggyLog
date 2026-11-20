import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_log/main.dart';

void main() {
  testWidgets('shows PiggyLog empty savings state', (tester) async {
    await tester.pumpWidget(const PiggyLogApp());

    expect(find.text('PiggyLog'), findsOneWidget);
    expect(find.text('No savings yet'), findsOneWidget);
    expect(find.text('Add savings'), findsOneWidget);
  });
}
