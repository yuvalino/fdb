import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'finder.dart';

/// Schedules a frame and waits for it to finish, or for [max] to pass,
/// whichever comes first. The cap matters when the app produces no frames
/// at all (hidden, paused or minimised), where `scheduleFrame()` is a no-op.
Future<void> _nextFrame(Duration max) {
  final completer = Completer<void>();
  final timer = Timer(max, () {
    if (!completer.isCompleted) completer.complete();
  });
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!completer.isCompleted) completer.complete();
  });
  SchedulerBinding.instance.scheduleFrame();
  return completer.future.whenComplete(timer.cancel);
}

/// Waits for the frame the app has scheduled, if any (for up to 100 ms), so
/// what was laid out reflects the latest changes.
Future<void> pendingFrame() async {
  if (SchedulerBinding.instance.hasScheduledFrame) {
    await _nextFrame(const Duration(milliseconds: 100));
  }
}

/// The default cap on [settleFrames].
const Duration defaultSettle = Duration(seconds: 1);

/// Waits until the app stops scheduling frames (animations, route
/// transitions and flings have finished), for at most [timeout]. An app
/// that animates forever uses all of it: a spinner, or a focused text field
/// whose cursor fades (`CupertinoTextField` everywhere, `TextField` on iOS).
/// One frame is always waited for (for up to 100 ms), even when [timeout]
/// is zero, so the action's own rebuild is on screen before it returns.
Future<void> settleFrames({Duration timeout = defaultSettle}) async {
  const frameCap = Duration(milliseconds: 100);
  final binding = SchedulerBinding.instance;
  final stopwatch = Stopwatch()..start();
  await _nextFrame(frameCap);
  while (binding.hasScheduledFrame) {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) return;
    await _nextFrame(remaining < frameCap ? remaining : frameCap);
  }
}

class WaitResult {
  final bool found;
  final int elapsedMs;
  final List<Element> matches;

  WaitResult({
    required this.found,
    required this.elapsedMs,
    required this.matches,
  });
}

/// Checks every frame until a widget matching [query] appears, for at most
/// [timeoutMs]. Always checks at least once, even when [timeoutMs] is 0.
Future<WaitResult> waitForElement(
  FindQuery query, {
  int timeoutMs = 5000,
}) async {
  final stopwatch = Stopwatch()..start();
  while (true) {
    final matches = findElements(query);
    if (matches.isNotEmpty) {
      return WaitResult(
        found: true,
        elapsedMs: stopwatch.elapsedMilliseconds,
        matches: matches,
      );
    }
    final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
    if (remaining <= 0) {
      return WaitResult(
        found: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        matches: const [],
      );
    }
    await _nextFrame(Duration(milliseconds: remaining < 100 ? remaining : 100));
  }
}
