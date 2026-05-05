import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dynamic_pricing_engine/main.dart';

void main() {
  testWidgets('App renders voice home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DynamicPricingApp());

    // Verify the main title is present
    expect(find.text('LogiPrice'), findsOneWidget);

    // Verify the mic button area exists
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });
}
