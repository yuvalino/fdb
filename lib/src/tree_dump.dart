import 'package:flutter/widgets.dart';

import 'finder.dart';

/// Dump the widget tree as a JSON-friendly nested map.
Map<String, dynamic> dumpTree({int maxDepth = 50}) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return {'error': 'no root element'};
  return _dumpElement(root, 0, maxDepth);
}

Map<String, dynamic> _dumpElement(Element element, int depth, int maxDepth) {
  final widget = element.widget;
  final result = <String, dynamic>{
    'type': widget.runtimeType.toString(),
  };

  // Key
  final key = widget.key;
  if (key is ValueKey) {
    result['key'] = key.value.toString();
  } else if (key != null) {
    result['key'] = key.toString();
  }

  // Direct text
  final text = _extractDirectText(element);
  if (text != null && text.isNotEmpty) {
    result['text'] = text;
  }

  // Bounds
  final bounds = getBounds(element);
  if (bounds != null) {
    result['bounds'] = bounds;
  }

  // Children
  if (depth < maxDepth) {
    final children = <Map<String, dynamic>>[];
    element.visitChildren((child) {
      children.add(_dumpElement(child, depth + 1, maxDepth));
    });
    if (children.isNotEmpty) {
      result['children'] = children;
    }
  }

  return result;
}

String? _extractDirectText(Element element) {
  final widget = element.widget;
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is RichText) {
    return widget.text.toPlainText();
  }
  return null;
}
