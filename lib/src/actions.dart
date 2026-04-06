import 'dart:async';

import 'package:flutter/widgets.dart';

import 'waiter.dart';

int _nextPointer = 100;

Offset _getCenter(Element element) {
  final renderBox = element.findRenderObject() as RenderBox;
  final topLeft = renderBox.localToGlobal(Offset.zero);
  return topLeft + Offset(renderBox.size.width / 2, renderBox.size.height / 2);
}

/// Simulate a tap on an element.
Future<void> performTap(Element element) async {
  final center = _getCenter(element);
  final pointer = _nextPointer++;
  final binding = WidgetsBinding.instance;

  binding.handlePointerEvent(PointerDownEvent(
    position: center,
    pointer: pointer,
  ));

  await Future<void>.delayed(const Duration(milliseconds: 1));

  binding.handlePointerEvent(PointerUpEvent(
    position: center,
    pointer: pointer,
  ));
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

  editableState!.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ));
}

/// Simulate a scroll (drag) gesture on an element.
Future<void> performScroll(Element element, double dx, double dy) async {
  final center = _getCenter(element);
  final binding = WidgetsBinding.instance;
  final pointer = _nextPointer++;

  binding.handlePointerEvent(PointerDownEvent(
    position: center,
    pointer: pointer,
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
    ));
  }

  binding.handlePointerEvent(PointerUpEvent(
    position: center + Offset(dx, dy),
    pointer: pointer,
  ));
}

/// Simulate a long press on an element.
Future<void> performLongPress(Element element, {int durationMs = 500}) async {
  final center = _getCenter(element);
  final pointer = _nextPointer++;
  final binding = WidgetsBinding.instance;

  binding.handlePointerEvent(PointerDownEvent(
    position: center,
    pointer: pointer,
  ));

  await Future<void>.delayed(Duration(milliseconds: durationMs));

  binding.handlePointerEvent(PointerUpEvent(
    position: center,
    pointer: pointer,
  ));
}
