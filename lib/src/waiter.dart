import 'dart:async';

import 'package:flutter/widgets.dart';

import 'finder.dart';

/// Wait for pending frames to settle after an action.
Future<void> settleFrames({int maxFrames = 10}) async {
  final binding = WidgetsBinding.instance;

  for (var i = 0; i < maxFrames; i++) {
    final completer = Completer<void>();
    binding.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    binding.scheduleFrame();
    await completer.future;

    if (!binding.hasScheduledFrame) break;
  }
}

class WaitResult {
  final bool found;
  final int elapsedMs;
  final List<Element> matches;

  WaitResult({required this.found, required this.elapsedMs, required this.matches});
}

/// Poll each frame until a widget matching [query] appears or timeout.
Future<WaitResult> waitForElement(FindQuery query, {int timeoutMs = 5000}) async {
  final binding = WidgetsBinding.instance;
  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsedMilliseconds < timeoutMs) {
    final matches = findElements(query);
    if (matches.isNotEmpty) {
      stopwatch.stop();
      return WaitResult(
        found: true,
        elapsedMs: stopwatch.elapsedMilliseconds,
        matches: matches,
      );
    }

    // Wait for next frame
    final completer = Completer<void>();
    binding.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    binding.scheduleFrame();
    await completer.future;
  }

  stopwatch.stop();
  return WaitResult(
    found: false,
    elapsedMs: stopwatch.elapsedMilliseconds,
    matches: const [],
  );
}
