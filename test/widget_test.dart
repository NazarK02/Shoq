import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoq/services/theme_service.dart';

void main() {
  testWidgets('light theme renders a basic scaffold', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeService.lightTheme,
        home: const Scaffold(body: Center(child: Text('Shoq'))),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
    expect(find.text('Shoq'), findsOneWidget);
  });
}
