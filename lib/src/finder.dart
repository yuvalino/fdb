import 'package:flutter/widgets.dart';

class FindQuery {
  final String by;
  final String value;
  final int? index;

  FindQuery({required this.by, required this.value, this.index});
}

/// Find all elements matching a query by walking the element tree.
List<Element> findElements(FindQuery query) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return const [];

  final results = <Element>[];
  _visit(root, query, results);

  if (query.index != null) {
    if (query.index! < results.length) {
      return [results[query.index!]];
    }
    return const [];
  }

  return results;
}

/// Find a single element: first match, or Nth if index is specified.
Element? findOneElement(FindQuery query) {
  final results = findElements(query);
  return results.isNotEmpty ? results.first : null;
}

void _visit(Element element, FindQuery query, List<Element> results) {
  if (_matches(element, query)) {
    results.add(element);
  }
  element.visitChildren((child) => _visit(child, query, results));
}

bool _matches(Element element, FindQuery query) {
  switch (query.by) {
    case 'key':
      final key = element.widget.key;
      if (key is ValueKey) {
        return key.value.toString() == query.value;
      }
      return key.toString() == query.value;
    case 'text':
      return _extractDirectText(element)?.contains(query.value) ?? false;
    case 'type':
      return element.widget.runtimeType.toString() == query.value;
    default:
      return false;
  }
}

/// Extract text directly from this element's widget (not descendants).
String? _extractDirectText(Element element) {
  final widget = element.widget;
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is RichText) {
    return widget.text.toPlainText();
  }
  if (widget is EditableText) {
    return widget.controller.text;
  }
  return null;
}

/// Extract text from this element and all its descendants.
String extractSubtreeText(Element element) {
  final buffer = StringBuffer();
  _collectText(element, buffer);
  return buffer.toString();
}

void _collectText(Element element, StringBuffer buffer) {
  final text = _extractDirectText(element);
  if (text != null && text.isNotEmpty) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(text);
    // Don't recurse — Text widget's RichText child would duplicate
    return;
  }
  element.visitChildren((child) => _collectText(child, buffer));
}

/// Get the screen bounds of an element's render object.
Map<String, double>? getBounds(Element element) {
  final renderObject = element.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  final topLeft = renderObject.localToGlobal(Offset.zero);
  final size = renderObject.size;
  return {
    'x': topLeft.dx,
    'y': topLeft.dy,
    'w': size.width,
    'h': size.height,
  };
}

/// Serialize an element to a JSON-friendly map.
Map<String, dynamic> serializeElement(Element element) {
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

  // Text (from subtree)
  final text = extractSubtreeText(element);
  if (text.isNotEmpty) {
    result['text'] = text;
  }

  // Bounds
  final bounds = getBounds(element);
  if (bounds != null) {
    result['bounds'] = bounds;
  }

  return result;
}
