import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'waiter.dart';

int _nextPointer = 100;

PointerDeviceKind get _pointerKind =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows
        ? PointerDeviceKind.mouse
        : PointerDeviceKind.touch;

Offset _getCenter(Element element) {
  final renderObject = element.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    throw StateError(
      'Cannot get center of ${element.widget.runtimeType}: '
      'render object is ${renderObject.runtimeType}',
    );
  }
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft + Offset(renderObject.size.width / 2, renderObject.size.height / 2);
}

/// Simulate a tap on an element by invoking its GestureDetector/InkWell callback directly.
/// Falls back to pointer event dispatch if no tappable ancestor is found.
Future<void> performTap(Element element) async {
  // Try direct callback invocation first — avoids pointer coordinate issues.
  if (_tryDirectTap(element)) return;

  final center = _getCenter(element);
  final pointer = _nextPointer++;
  final binding = WidgetsBinding.instance;
  final kind = _pointerKind;

  if (kind == PointerDeviceKind.mouse) {
    binding.handlePointerEvent(PointerAddedEvent(position: center, pointer: pointer, kind: kind));
    binding.handlePointerEvent(PointerHoverEvent(position: center, pointer: pointer, kind: kind));
  }

  binding.handlePointerEvent(PointerDownEvent(
    position: center,
    pointer: pointer,
    kind: kind,
    buttons: kind == PointerDeviceKind.mouse ? kPrimaryMouseButton : 0,
  ));

  await Future<void>.delayed(const Duration(milliseconds: 16));

  binding.handlePointerEvent(PointerUpEvent(
    position: center,
    pointer: pointer,
    kind: kind,
  ));

  if (kind == PointerDeviceKind.mouse) {
    binding.handlePointerEvent(PointerRemovedEvent(position: center, pointer: pointer, kind: kind));
  }
}

bool _tryDirectTap(Element target) {
  VoidCallback? onTap;

  void search(Element el) {
    if (onTap != null) return;
    final widget = el.widget;
    if (widget is GestureDetector && widget.onTap != null) {
      onTap = widget.onTap;
      return;
    }
    if (widget is InkWell && widget.onTap != null) {
      onTap = widget.onTap;
      return;
    }
    if (widget is InkResponse && widget.onTap != null) {
      onTap = widget.onTap;
      return;
    }
    if (widget is IconButton && widget.onPressed != null) {
      onTap = widget.onPressed;
      return;
    }
    if (widget is TextButton && widget.onPressed != null) {
      onTap = widget.onPressed;
      return;
    }
    if (widget is ElevatedButton && widget.onPressed != null) {
      onTap = widget.onPressed;
      return;
    }
    el.visitChildren(search);
  }

  // Search the target element itself, then its subtree
  final widget = target.widget;
  if (widget is IconButton && widget.onPressed != null) {
    widget.onPressed!();
    return true;
  }
  if (widget is ElevatedButton && widget.onPressed != null) {
    widget.onPressed!();
    return true;
  }
  if (widget is TextButton && widget.onPressed != null) {
    widget.onPressed!();
    return true;
  }

  search(target);
  if (onTap != null) {
    onTap!();
    return true;
  }

  // Walk UP the tree to find tappable ancestors
  Element? current = target;
  while (current != null) {
    final w = current.widget;
    if (w is GestureDetector && w.onTap != null) { w.onTap!(); return true; }
    if (w is InkWell && w.onTap != null) { w.onTap!(); return true; }
    if (w is InkResponse && w.onTap != null) { w.onTap!(); return true; }
    if (w is IconButton && w.onPressed != null) { w.onPressed!(); return true; }
    if (w is ElevatedButton && w.onPressed != null) { w.onPressed!(); return true; }
    if (w is TextButton && w.onPressed != null) { w.onPressed!(); return true; }
    if (w is ListTile && w.onTap != null) { w.onTap!(); return true; }

    Element? parent;
    current.visitAncestorElements((ancestor) { parent = ancestor; return false; });
    current = parent;
  }

  return false;
}

/// Simulate entering text into a text field.
///
/// Taps the element to focus it, then finds the EditableTextState in the
/// subtree and updates the editing value.
Future<void> performEnterText(Element element, String text) async {
  // Tap to focus
  await performTap(element);
  await settleFrames();

  // Find EditableTextState in the subtree
  EditableTextState? editableState;
  void findEditable(Element el) {
    if (editableState != null) return;
    if (el is StatefulElement && el.state is EditableTextState) {
      editableState = el.state as EditableTextState;
      return;
    }
    el.visitChildren(findEditable);
  }
  element.visitChildren(findEditable);

  if (editableState == null) {
    throw StateError('No EditableTextState found in subtree of ${element.widget.runtimeType}');
  }

  // Use the controller directly to avoid Overlay.of() crash when the
  // EditableText is not inside a full MaterialApp Overlay (e.g. login screen
  // or contexts without a Navigator). updateEditingValue triggers selection
  // handle display which requires Overlay.of(context).
  final controller = editableState!.widget.controller;
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

/// Simulate a scroll (drag) gesture on an element.
Future<void> performScroll(Element element, double dx, double dy) async {
  final center = _getCenter(element);
  final binding = WidgetsBinding.instance;
  final pointer = _nextPointer++;
  final kind = _pointerKind;

  binding.handlePointerEvent(PointerDownEvent(
    position: center,
    pointer: pointer,
    kind: kind,
  ));

  const steps = 10;
  final stepDx = dx / steps;
  final stepDy = dy / steps;

  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    binding.handlePointerEvent(PointerMoveEvent(
      position: center + Offset(stepDx * i, stepDy * i),
      pointer: pointer,
      delta: Offset(stepDx, stepDy),
      kind: kind,
    ));
  }

  binding.handlePointerEvent(PointerUpEvent(
    position: center + Offset(dx, dy),
    pointer: pointer,
    kind: kind,
  ));
}

/// Simulate a long press on an element.
Future<void> performLongPress(Element element, {int durationMs = 500}) async {
  final center = _getCenter(element);
  final pointer = _nextPointer++;
  final binding = WidgetsBinding.instance;
  final kind = _pointerKind;

  binding.handlePointerEvent(PointerDownEvent(
    position: center,
    pointer: pointer,
    kind: kind,
  ));

  await Future<void>.delayed(Duration(milliseconds: durationMs));

  binding.handlePointerEvent(PointerUpEvent(
    position: center,
    pointer: pointer,
    kind: kind,
  ));
}
