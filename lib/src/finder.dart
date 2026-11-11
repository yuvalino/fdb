import 'package:flutter/widgets.dart';

class FindQuery {
  final String by;
  final String value;
  final int? index;

  FindQuery({required this.by, required this.value, this.index});

  @override
  String toString() =>
      '{by: $by, value: $value${index == null ? '' : ', index: $index'}}';
}

/// Find all elements matching a query by walking the element tree.
List<Element> findElements(FindQuery query) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return const [];

  final results = <Element>[];
  _visit(root, query, results);

  final index = query.index;
  if (index != null) {
    if (index >= 0 && index < results.length) return [results[index]];
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

/// The string a key is matched and reported by: a `ValueKey`'s value, or
/// the key's own description for other keys. Null when there is no key.
String? keyString(Key? key) {
  if (key == null) return null;
  if (key is ValueKey) return key.value.toString();
  return key.toString();
}

bool _matches(Element element, FindQuery query) {
  switch (query.by) {
    case 'key':
      return keyString(element.widget.key) == query.value;
    case 'text':
      if (_isBuiltByText(element)) return false;
      return extractDirectText(element)?.contains(query.value) ?? false;
    case 'type':
      final typeName = element.widget.runtimeType.toString();
      if (typeName == query.value) return true;
      // Match private Flutter types (e.g., "BackButton" matches "_BackButton")
      if (typeName.startsWith('_') && typeName.substring(1) == query.value) {
        return true;
      }
      return false;
    default:
      return false;
  }
}

/// Whether [element] is the `RichText` a `Text` widget builds for itself,
/// so a `Text` is matched once rather than twice. `Text` builds its
/// `RichText` directly or through a few wrappers (`MouseRegion`,
/// `SelectionContainer` and private ones); a `RichText` inside a
/// `WidgetSpan` reaches an outer `RichText` first and still counts.
bool _isBuiltByText(Element element) {
  if (element.widget is! RichText) return false;
  var builtByText = false;
  var hops = 0;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Text) {
      builtByText = true;
      return false;
    }
    if (widget is RichText || widget is EditableText) return false;
    return ++hops < 8;
  });
  return builtByText;
}

/// Extract text directly from this element's widget (not descendants).
String? extractDirectText(Element element) {
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
  final text = extractDirectText(element);
  if (text != null) {
    if (text.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }
    // Don't recurse: a Text's own RichText child would repeat it.
    return;
  }
  element.visitChildren((child) => _collectText(child, buffer));
}

/// Get the screen bounds of an element's render object.
Map<String, double>? getBounds(Element element) {
  final renderObject = element.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.attached ||
      !renderObject.hasSize) {
    return null;
  }
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

  final key = keyString(widget.key);
  if (key != null) result['key'] = key;

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
