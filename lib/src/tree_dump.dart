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

  final key = keyString(widget.key);
  if (key != null) result['key'] = key;

  // Direct text
  final text = extractDirectText(element);
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
