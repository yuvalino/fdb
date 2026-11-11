import 'dart:async';

import 'package:flutter/widgets.dart';

import 'errors.dart';

/// An [xterm](https://pub.dev/packages/xterm) `Terminal`, reached through
/// dynamic dispatch so frt has no compile-time dependency on xterm. Any
/// widget with a `terminal` getter holding one counts, `TerminalView` among
/// them.
class TerminalHandle {
  TerminalHandle._(this._terminal);

  final dynamic _terminal;

  /// Where the terminal is drawn, when its widget draws it (TerminalView
  /// does): the render box, which has `lineHeight`, and the scroll position
  /// of the scrollable it sits in.
  RenderBox? _box;
  ScrollPosition? _scroll;
  EdgeInsets _padding = EdgeInsets.zero;

  static TerminalHandle? _of(Widget widget) {
    try {
      final dynamic terminal = (widget as dynamic).terminal;
      if (terminal == null) return null;
      // Make sure it is a terminal and not something else called that.
      terminal.buffer.lines;
      terminal.viewWidth as int;
      return TerminalHandle._(terminal);
    } on NoSuchMethodError {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// The terminal of [element]'s widget, or of the first widget under it
  /// that has one.
  static TerminalHandle find(Element element) {
    TerminalHandle? found;
    Element? at;
    void visit(Element e) {
      if (found != null) return;
      found = _of(e.widget);
      if (found != null) {
        at = e;
      } else {
        e.visitChildren(visit);
      }
    }

    visit(element);
    final handle = found ??
        (throw FrtException(409, 'not_terminal',
            'No xterm terminal at or under ${element.widget.runtimeType}'));
    handle._findView(at!);
    return handle;
  }

  /// The first scrollable under [element], and the box under it that draws
  /// terminal lines (one with a `lineHeight`), with the padding it insets
  /// its rows by (TerminalView's is the MediaQuery's).
  void _findView(Element element) {
    void visit(Element e) {
      if (_box != null) return;
      final widget = e.widget;
      if (_scroll == null && widget is Scrollable && e is StatefulElement) {
        final state = e.state;
        if (state is ScrollableState) _scroll = state.position;
      }
      if (_scroll != null) {
        final box = e.renderObject;
        if (box is RenderBox && _lineHeightOf(box) != null) {
          _box = box;
          _padding = MediaQuery.maybePaddingOf(e) ?? EdgeInsets.zero;
          return;
        }
      }
      e.visitChildren(visit);
    }

    visit(element);
  }

  static double? _lineHeightOf(RenderBox box) {
    try {
      return ((box as dynamic).lineHeight as num).toDouble();
    } on NoSuchMethodError {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// The buffer lines drawn whole in the terminal's box at its scroll
  /// position, first to last, or null when it isn't laid out.
  ({int first, int last})? _view(int lineCount) {
    final box = _box, scroll = _scroll;
    if (box == null ||
        scroll == null ||
        !box.attached ||
        !box.hasSize ||
        !scroll.hasPixels ||
        lineCount == 0) {
      return null;
    }
    final lineHeight = _lineHeightOf(box);
    if (lineHeight == null || lineHeight <= 0) return null;
    // Line i is drawn from i * lineHeight + padding.top - pixels down.
    const slack = 0.01;
    final top = scroll.pixels - _padding.top;
    var first = ((top - slack) / lineHeight).ceil();
    var last = ((top + box.size.height + slack) / lineHeight).floor() - 1;
    if (first < 0) first = 0;
    if (last > lineCount - 1) last = lineCount - 1;
    if (last < first) return null;
    return (first: first, last: last);
  }

  /// Sends [text] to the program as typed input (`Terminal.textInput`), or
  /// as a paste (`Terminal.paste`, bracketed when the program asked).
  void input(String text, {bool paste = false}) {
    if (paste) {
      _terminal.paste(text);
    } else {
      _terminal.textInput(text);
    }
  }

  /// What the terminal shows: every line of the buffer, or with [screen]
  /// only the lines in view. Lines before [from] (an index into the whole
  /// buffer) are left out.
  TerminalSnapshot snapshot({bool screen = false, int from = 0}) {
    final int width = _terminal.viewWidth as int;
    final int height = _terminal.viewHeight as int;
    final dynamic buffer = _terminal.buffer;
    final dynamic lines = buffer.lines;
    final int count = lines.length as int;
    final int scrollBack = buffer.scrollBack as int;
    var first = screen ? scrollBack : 0;
    if (from > first) first = from;

    final text = <String>[];
    final wrapped = <bool>[];
    for (var i = first; i < count; i++) {
      final dynamic line = lines[i];
      text.add(_lineText(line, width));
      wrapped.add(line.isWrapped as bool);
    }
    return TerminalSnapshot(
      width: width,
      height: height,
      lineCount: count,
      scrollBack: scrollBack,
      first: first,
      lines: text,
      wrapped: wrapped,
      cursorX: buffer.cursorX as int,
      cursorLine: buffer.absoluteCursorY as int,
      altBuffer: _terminal.isUsingAltBuffer as bool,
      view: _view(count),
    );
  }

  /// A row's characters up to its last non-empty cell. An empty cell is a
  /// space; the cell after a wide character, which holds nothing, is not.
  static String _lineText(dynamic line, int width) {
    final int end = line.getTrimmedLength(width) as int;
    final out = StringBuffer();
    var i = 0;
    while (i < end) {
      final int codePoint = line.getCodePoint(i) as int;
      if (codePoint == 0) {
        out.write(' ');
        i++;
        continue;
      }
      out.writeCharCode(codePoint);
      final int cellWidth = line.getWidth(i) as int;
      i += cellWidth < 1 ? 1 : cellWidth;
    }
    return out.toString();
  }
}

class TerminalSnapshot {
  TerminalSnapshot({
    required this.width,
    required this.height,
    required this.lineCount,
    required this.scrollBack,
    required this.first,
    required this.lines,
    required this.wrapped,
    required this.cursorX,
    required this.cursorLine,
    required this.altBuffer,
    this.view,
  });

  /// Columns and rows in view.
  final int width;
  final int height;

  /// Lines in the whole buffer, and how many of them are above the view.
  final int lineCount;
  final int scrollBack;

  /// The buffer index of `lines[0]`.
  final int first;

  final List<String> lines;

  /// `wrapped[i]`: `lines[i]` continues the line before it, which ran past
  /// the right edge.
  final List<bool> wrapped;

  final int cursorX;

  /// The cursor's row as a buffer index; `cursorLine - scrollBack` is its
  /// row in view.
  final int cursorLine;

  /// Whether a full-screen program (vim, less) has switched to the
  /// alternate screen.
  final bool altBuffer;

  /// The buffer lines in view, drawn whole: where the view is scrolled to.
  /// Null when the terminal's widget doesn't draw it or isn't laid out.
  final ({int first, int last})? view;

  /// The lines with soft wraps undone, one string per line the program
  /// wrote, joined with newlines. A line wrapped from before [first] starts
  /// mid-way.
  String get text {
    final out = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      if (i > 0 && !wrapped[i]) out.write('\n');
      out.write(lines[i]);
    }
    return out.toString();
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'lineCount': lineCount,
        'scrollBack': scrollBack,
        'first': first,
        'lines': lines,
        'wrapped': wrapped,
        'text': text,
        'cursor': {
          'x': cursorX,
          'line': cursorLine,
          'y': cursorLine - scrollBack,
        },
        'altBuffer': altBuffer,
        'view': view == null ? null : {'first': view!.first, 'last': view!.last},
      };
}

/// Polls [terminal] until [pattern] matches its [TerminalSnapshot.text], for
/// at most [timeoutMs]. Terminal output arrives without the app drawing a
/// frame for it, so this checks on a timer rather than per frame.
Future<({bool found, int elapsedMs, RegExpMatch? match, TerminalSnapshot snapshot})>
    waitForTerminal(
  TerminalHandle Function() terminal,
  RegExp pattern, {
  required int timeoutMs,
  bool screen = false,
  int from = 0,
}) async {
  final stopwatch = Stopwatch()..start();
  while (true) {
    final snapshot = terminal().snapshot(screen: screen, from: from);
    final match = pattern.firstMatch(snapshot.text);
    final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
    if (match != null || remaining <= 0) {
      return (
        found: match != null,
        elapsedMs: stopwatch.elapsedMilliseconds,
        match: match,
        snapshot: snapshot,
      );
    }
    await Future<void>.delayed(
        Duration(milliseconds: remaining < 50 ? remaining : 50));
  }
}
