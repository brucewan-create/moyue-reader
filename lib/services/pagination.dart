import 'package:flutter/material.dart';

import '../services/settings.dart';

/// 排版后的一页
class BookPage {
  final String text;
  final int startOffset; // 相对整本书的起始字符位置
  final int endOffset;

  BookPage({required this.text, required this.startOffset, required this.endOffset});

  int get length => endOffset - startOffset;
}

/// 精确分页引擎：用 TextPainter 按可用区域逐段排版，结果稳定，支持任意字号/行距。
class PaginationService {
  /// 把一段正文切成若干页。
  /// [content] 章节正文，[baseOffset] 该章节在整本书中的起始字符偏移。
  static List<BookPage> paginate({
    required String content,
    required int baseOffset,
    required Size pageSize,
    required ReaderSettings settings,
  }) {
    if (content.isEmpty) return [];

    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing,
      fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
    );

    final margin = settings.pageMargin;
    final availableWidth = (pageSize.width - margin * 2).clamp(80.0, 4000.0).toDouble();
    final availableHeight = (pageSize.height - margin * 2).clamp(80.0, 4000.0).toDouble();

    final indent = '　' * settings.indent;
    final paragraphGap = settings.fontSize * 0.6;

    // 按原文本切段，同时记录每段在 content 中的偏移
    final segments = <_Segment>[];
    int cursor = 0;
    for (final rawLine in content.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        cursor += rawLine.length + 1;
        continue;
      }
      segments.add(_Segment(text: trimmed, offset: baseOffset + cursor));
      cursor += rawLine.length + 1;
    }

    if (segments.isEmpty) {
      return [BookPage(text: '', startOffset: baseOffset, endOffset: baseOffset)];
    }

    final pages = <BookPage>[];
    final buffer = StringBuffer();
    double usedHeight = 0;
    int? pageStart;
    int pageEnd = baseOffset;

    for (final seg in segments) {
      final line = '$indent${seg.text}';
      final painter = TextPainter(
        text: TextSpan(text: line, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: availableWidth);
      final blockHeight = painter.height + paragraphGap;

      if (pageStart == null) pageStart = seg.offset;

      // 放不下且本页已有内容 → 另起一页
      if (usedHeight + blockHeight > availableHeight && buffer.isNotEmpty) {
        pages.add(BookPage(
          text: buffer.toString().trimRight(),
          startOffset: pageStart,
          endOffset: pageEnd,
        ));
        buffer.clear();
        usedHeight = 0;
        pageStart = seg.offset;
      }

      buffer.writeln(line);
      usedHeight += blockHeight;
      pageEnd = seg.offset + seg.text.length;
    }

    if (buffer.isNotEmpty) {
      pages.add(BookPage(
        text: buffer.toString().trimRight(),
        startOffset: pageStart ?? baseOffset,
        endOffset: pageEnd,
      ));
    }

    return pages;
  }
}

class _Segment {
  final String text;
  final int offset;
  _Segment({required this.text, required this.offset});
}
