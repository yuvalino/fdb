import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderView;

import 'errors.dart';
import 'waiter.dart';

/// Synthetic pointer ids start far above the small ids the engine gives
/// real touches, so the two never collide.
int _nextPointer = 1 << 20;

/// The device id of frt's synthetic pointer, kept apart from real devices
/// so a real mouse's hover state is never added or removed under it.
const int _device = 0x467274; // "Frt"

PointerDeviceKind get _pointerKind =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows
        ? PointerDeviceKind.mouse
        : PointerDeviceKind.touch;

/// Where a gesture on an element lands: the centre of its render box, in
/// the logical coordinates of the view that shows it.
class _Target {
  final Offset position;
  final int viewId;
  _Target(this.position, this.viewId);
}

String _describe(Element element) => '${element.widget.runtimeType}'
    '${element.widget.key == null ? '' : ' ${element.widget.key}'}';

/// Finds where to put the pointer for [element], and checks that a pointer
/// there would actually reach it. A widget covered by a dialog barrier,
/// inside `IgnorePointer`, or scrolled off-screen fails with 409, as it
/// would for a user.
_Target _target(Element element) {
  if (!element.mounted) {
    throw FrtException(
        409, 'not_mounted', '${_describe(element)} is no longer on screen');
  }
  final box = element.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) {
    throw FrtException(409, 'no_box',
        '${_describe(element)} has no laid-out box to touch (${box.runtimeType})');
  }
  // The view is found through the render tree rather than View.maybeOf,
  // which would make the element depend on the view scope: frt shouldn't
  // change the app it drives.
  RenderObject? node = box;
  while (node != null && node is! RenderView) {
    node = node.parent;
  }
  if (node is! RenderView) {
    throw FrtException(
        409, 'no_view', '${_describe(element)} is not shown in a view');
  }
  final view = node.flutterView;
  final position = box.localToGlobal(box.size.center(Offset.zero));
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, view.viewId);
  if (!result.path.any((entry) => entry.target == box)) {
    final top = result.path.isEmpty ? null : result.path.first.target;
    throw FrtException(
      409,
      'not_hittable',
      'A pointer at the centre of ${_describe(element)} '
          '(${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}) '
          'would not reach it${top == null ? '' : '; it would hit ${top.runtimeType}'}. '
          'It may be covered, ignoring pointers, or off-screen.',
    );
  }
  return _Target(position, view.viewId);
}

/// Runs a pointer gesture: a mouse is added and hovered first and removed
/// after, so `MouseRegion`s see it as they would a real one.
Future<void> _gesture(
  _Target target,
  Future<void> Function(int pointer, PointerDeviceKind kind) body, {
  PointerDeviceKind? kind,
}) async {
  final binding = WidgetsBinding.instance;
  kind ??= _pointerKind;
  final pointer = _nextPointer++;
  final mouse = kind == PointerDeviceKind.mouse;
  if (mouse) {
    binding.handlePointerEvent(PointerAddedEvent(
        viewId: target.viewId,
        position: target.position,
        kind: kind,
        device: _device));
    binding.handlePointerEvent(PointerHoverEvent(
        viewId: target.viewId,
        position: target.position,
        kind: kind,
        device: _device));
  }
  try {
    await body(pointer, kind);
  } finally {
    if (mouse) {
      binding.handlePointerEvent(PointerRemovedEvent(
          viewId: target.viewId,
          position: target.position,
          kind: kind,
          device: _device));
    }
  }
}

/// Taps the centre of [element] with a real pointer, so the tap goes through
/// hit testing and the gesture arena exactly as a user's would.
Future<void> performTap(Element element) async {
  final target = _target(element);
  final binding = WidgetsBinding.instance;
  await _gesture(target, (pointer, kind) async {
    // `buttons` defaults to kPrimaryButton, which tap recognisers require
    // for touch as well as for a mouse.
    binding.handlePointerEvent(PointerDownEvent(
        viewId: target.viewId,
        position: target.position,
        pointer: pointer,
        kind: kind,
        device: _device));
    await Future<void>.delayed(const Duration(milliseconds: 16));
    binding.handlePointerEvent(PointerUpEvent(
        viewId: target.viewId,
        position: target.position,
        pointer: pointer,
        kind: kind,
        device: _device));
  });
}

EditableTextState? _findEditable(Element root) {
  EditableTextState? found;
  void visit(Element el) {
    if (found != null) return;
    if (el is StatefulElement && el.state is EditableTextState) {
      found = el.state as EditableTextState;
      return;
    }
    el.visitChildren(visit);
  }

  visit(root);
  return found;
}

/// How long enter-text lets focusing settle. Short, because a focused field
/// may animate its cursor for as long as it stays focused.
const Duration _focusSettle = Duration(milliseconds: 300);

/// Enters [text] into the text field at or under [element], replacing what
/// it holds. It goes through the field like typing does: input formatters
/// apply and `onChanged` fires.
Future<void> performEnterText(Element element, String text) async {
  final field = _findEditable(element);
  if (field == null) {
    throw FrtException(409, 'not_editable',
        'No text field at or under ${_describe(element)}');
  }
  if (field.widget.readOnly) {
    throw FrtException(409, 'not_editable',
        'The text field under ${_describe(element)} is read-only');
  }

  // Tap to focus, as a user would; if the tap doesn't focus the field (for
  // example an outer "tap to unfocus" handler wins), focus it directly.
  await performTap(element);
  await settleFrames(timeout: _focusSettle);

  if (!element.mounted) {
    throw FrtException(409, 'not_mounted',
        '${_describe(element)} went away when it was tapped');
  }
  final editable = _findEditable(element);
  if (editable == null || !editable.mounted) {
    throw FrtException(409, 'not_editable',
        'The text field under ${_describe(element)} went away when it was tapped');
  }
  if (!editable.widget.focusNode.hasFocus) {
    editable.widget.focusNode.requestFocus();
    await settleFrames(timeout: _focusSettle);
    if (!editable.mounted) {
      throw FrtException(409, 'not_editable',
          'The text field under ${_describe(element)} went away when focused');
    }
  }

  final value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  if (Overlay.maybeOf(editable.context, rootOverlay: true) != null) {
    editable.userUpdateTextEditingValue(value, SelectionChangedCause.keyboard);
  } else {
    // A field with no Overlay above it (no Navigator or MaterialApp): the
    // user-input path would build selection handles, which need one. Set
    // the value and report the change the way the field would.
    final before = editable.widget.controller.text;
    editable.widget.controller.value = value;
    if (before != text) editable.widget.onChanged?.call(text);
  }
}

/// Drags from the centre of [element] by ([dx], [dy]) in ten steps. The
/// drag is a touch even on desktop: `ScrollBehavior.dragDevices` leaves the
/// mouse out by default, so a mouse drag would not scroll.
Future<void> performScroll(Element element, double dx, double dy) async {
  final target = _target(element);
  final binding = WidgetsBinding.instance;
  await _gesture(target, (pointer, kind) async {
    binding.handlePointerEvent(PointerDownEvent(
        viewId: target.viewId,
        position: target.position,
        pointer: pointer,
        kind: kind,
        device: _device));

    const steps = 10;
    final step = Offset(dx / steps, dy / steps);
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      binding.handlePointerEvent(PointerMoveEvent(
        viewId: target.viewId,
        position: target.position + step * i.toDouble(),
        pointer: pointer,
        delta: step,
        kind: kind,
        device: _device,
      ));
    }

    binding.handlePointerEvent(PointerUpEvent(
        viewId: target.viewId,
        position: target.position + Offset(dx, dy),
        pointer: pointer,
        kind: kind,
        device: _device));
  }, kind: PointerDeviceKind.touch);
}

/// The default long-press hold: past `kLongPressTimeout` (500 ms) with a
/// margin, so the recogniser's deadline never races the pointer going up.
const int defaultLongPressMs = 600;

/// Holds the pointer down on the centre of [element] for [durationMs].
Future<void> performLongPress(
  Element element, {
  int durationMs = defaultLongPressMs,
}) async {
  final target = _target(element);
  final binding = WidgetsBinding.instance;
  await _gesture(target, (pointer, kind) async {
    binding.handlePointerEvent(PointerDownEvent(
        viewId: target.viewId,
        position: target.position,
        pointer: pointer,
        kind: kind,
        device: _device));
    await Future<void>.delayed(Duration(milliseconds: durationMs));
    binding.handlePointerEvent(PointerUpEvent(
        viewId: target.viewId,
        position: target.position,
        pointer: pointer,
        kind: kind,
        device: _device));
  });
}
