import 'package:flutter/material.dart';

// Change this string (and nothing else) to produce a visible patch.
const String kBuildLabel = 'RELEASE v1';

void main() {
  // Printed to logcat / device console so scripts can verify which code runs.
  // ignore: avoid_print
  print('SAMPLE_APP_BUILD_LABEL=$kBuildLabel');
  runApp(const SampleApp());
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self-hosted code push',
      home: Scaffold(
        appBar: AppBar(title: const Text('Self-hosted code push')),
        body: Center(
          child: Text(
            kBuildLabel,
            key: const Key('build-label'),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
