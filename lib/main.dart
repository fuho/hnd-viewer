import 'package:flutter/material.dart';

import 'src/viewer_page.dart';

void main() {
  runApp(const HndViewerApp());
}

class HndViewerApp extends StatelessWidget {
  const HndViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hnd-viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ),
      home: const ViewerPage(),
    );
  }
}
