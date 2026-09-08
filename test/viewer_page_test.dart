import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/src/viewer_page.dart';

void main() {
  testWidgets('viewer renders in the disconnected state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ViewerPage()));
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('No video — connect to the camera'), findsOneWidget);
  });
}
