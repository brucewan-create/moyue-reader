import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:epubx/epubx.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/book.dart';

/// 解析结果
class ParsedBook {
  final String title;
  final String author;
  final String content;
  final List<Chapter> chapters;
  final String? coverPath;

  ParsedBook({
    required this.title,
    required this.author,
    required this.content,
    required this.chapters,
    this.coverPath,
  });
}

/// 书籍解析服务 - 支持 TXT / EPUB / PDF / MOBI/AZW3(基础信息)
class BookParser {
  /// 解析书籍文件
  static Future<ParsedBook> parse(String filePath) async {
    final format = formatFromExtension(filePath);
    switch (format) {
      case BookFormat.txt:
        return _parseTxt(filePath);
      case BookFormat.epub:
        return _parseEpub(filePath);
      case BookFormat.pdf:
        return _parsePdf(filePath);
      case BookFormat.mobi:
      case BookFormat.azw3:
        return _parseMobi(filePath);
      default:
        throw UnsupportedError('不支持的格式: $filePath');
    }
  }

  /// 智能解码中文文本 (UTF-8 / GBK / GB2312 / Big5)
  static String _decodeBytes(List<int> bytes) {
    // 优先尝试 UTF-8
    try {
      final decoder = const Utf8Decoder(allowMalformed: false);
      final text = decoder.convert(bytes);
      // 检查是否有替换字符或明显的乱码标志
      if (!text.contains('\uFFFD') && _looksReasonable(text)) {
        // 去掉 BOM
        return text.startsWith('\uFEFF') ? text.substring(1) : text;
      }
    } catch (_) {}

    // UTF-8 失败，尝试 GBK（charset 包用 gbk.decode）
    try {
      final text = gbk.decode(bytes);
      if (_looksReasonable(text)) return text;
    } catch (_) {}

    // 最后用 UTF-8 宽松模式
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  /// 简单判断文本是否合理（中文占比检测）
  static bool _looksReasonable(String text) {
    if (text.isEmpty) return false;
    final sample = text.length > 500 ? text.substring(0, 500) : text;
    int chineseChars = 0;
    int replacementChars = 0;
    for (int i = 0; i < sample.length; i++) {
      final code = sample.codeUnitAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) chineseChars++;
      if (code == 0xFFFD) replacementChars++;
    }
    if (replacementChars > 5) return false;
    if (sample.length > 50 && chineseChars == 0) {
      // 纯英文文本也合理
      int letters = 0;
      for (int i = 0; i < sample.length; i++) {
        final c = sample.codeUnitAt(i);
        if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) letters++;
      }
      return letters > sample.length * 0.5;
    }
    return true;
  }

  /// 解析 TXT
  static Future<ParsedBook> _parseTxt(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    String content = _decodeBytes(bytes);

    // 规范化换行
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 提取书名（从文件名或第一行）
    String title = file.uri.pathSegments.last.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
    String author = '未知作者';

    final firstLines = content.split('\n').take(10).toList();
    for (final line in firstLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final titleMatch = RegExp(r'^书名[:：]\s*(.+)$').firstMatch(trimmed);
      if (titleMatch != null) {
        title = titleMatch.group(1)!.trim();
        continue;
      }
      final authorMatch = RegExp(r'^作者[:：]\s*(.+)$').firstMatch(trimmed);
      if (authorMatch != null) {
        author = authorMatch.group(1)!.trim();
      }
    }

    final chapters = _detectChapters(content);

    return ParsedBook(
      title: title,
      author: author,
      content: content,
      chapters: chapters,
    );
  }

  /// 智能章节识别
  static List<Chapter> _detectChapters(String content) {
    final chapters = <Chapter>[];
    final lines = content.split('\n');
    int offset = 0;

    // 常见章节标题正则
    final patterns = [
      RegExp(r'^第[零一二三四五六七八九十百千万\d]+[章节卷部篇回].*'),
      RegExp(r'^ chapter\s*\d+.*', caseSensitive: false),
      RegExp(r'^Chapter\s*\d+.*'),
      RegExp(r'^\d+[\.、]\s*\S{1,30}$'),
      RegExp(r'^【.+】$'),
      RegExp(r'^卷[零一二三四五六七八九十百千万\d]+.*'),
      RegExp(r'^楔子.*$'),
      RegExp(r'^序章.*$'),
      RegExp(r'^尾声.*$'),
      RegExp(r'^番外.*$'),
      RegExp(r'^番外篇.*$'),
    ];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        offset += lines[i].length + 1;
        continue;
      }

      // 章节标题通常较短
      if (line.length <= 60) {
        for (final pattern in patterns) {
          if (pattern.hasMatch(line)) {
            chapters.add(Chapter(
              index: chapters.length,
              title: line,
              startOffset: offset,
              endOffset: content.length,
            ));
            break;
          }
        }
      }
      offset += lines[i].length + 1;
    }

    // 如果没识别到章节，按长度分段（每约 3000 字一段）
    if (chapters.isEmpty && content.length > 3000) {
      const segmentSize = 3000;
      int start = 0;
      int idx = 0;
      while (start < content.length) {
        final end = (start + segmentSize).clamp(0, content.length);
        chapters.add(Chapter(
          index: idx++,
          title: '第 $idx 部分',
          startOffset: start,
          endOffset: end,
        ));
        start = end;
      }
    }

    // 更新上一章的结束位置
    for (int i = 0; i < chapters.length - 1; i++) {
      chapters[i] = Chapter(
        index: chapters[i].index,
        title: chapters[i].title,
        startOffset: chapters[i].startOffset,
        endOffset: chapters[i + 1].startOffset,
      );
    }

    // 如果没有识别到任何章节，至少创建一个
    if (chapters.isEmpty) {
      chapters.add(Chapter(
        index: 0,
        title: '正文',
        startOffset: 0,
        endOffset: content.length,
      ));
    }

    return chapters;
  }

  /// 需要跳过的 HTML 标签（脚本/样式/元数据，不属于正文）
  static const Set<String> _skipTags = {
    'script', 'style', 'head', 'noscript', 'meta', 'link', 'title',
  };

  /// 块级标签——在这些标签前后插入换行，保留段落结构
  static const Set<String> _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'br', 'li', 'ul', 'ol', 'tr', 'table', 'blockquote',
    'section', 'article', 'header', 'footer', 'hr', 'pre',
  };

  /// 把 EPUB 章节 HTML 转成保留段落结构的纯文本。
  /// html 包自带的 body.text 只拼接文本节点、丢弃所有换行，会把整章挤成一坨——这里不用它。
  static String _htmlToText(String html) {
    if (html.trim().isEmpty) return '';
    final document = html_parser.parseFragment(html);
    final buffer = StringBuffer();
    // 用一个布尔标志跟踪是否位于行首，避免反复 StringBuffer.toString()
    bool lineStart = true;
    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.data);
        if (node.data.isNotEmpty) lineStart = node.data.endsWith('\n');
        return;
      }
      if (node is dom.Element) {
        final tag = node.localName?.toLowerCase() ?? '';
        if (_skipTags.contains(tag)) return;
        if (_blockTags.contains(tag) && !lineStart) {
          buffer.writeln();
          lineStart = true;
        }
      }
      for (final child in node.nodes) {
        walk(child);
      }
      if (node is dom.Element && _blockTags.contains(node.localName?.toLowerCase() ?? '')) {
        if (!lineStart) {
          buffer.writeln();
          lineStart = true;
        }
      }
    }
    walk(document);

    return buffer
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ') // &nbsp;
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// 章节标题：优先 EPUB 目录名，其次 HTML 的 h1~h3，最后兜底序号
  static String _chapterTitle(String html, String? navTitle, int index) {
    if (navTitle != null) {
      final t = navTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isNotEmpty && t.length <= 60) return t;
    }
    if (html.trim().isNotEmpty) {
      try {
        final doc = html_parser.parseFragment(html);
        for (final tag in ['h1', 'h2', 'h3']) {
          final el = doc.querySelector(tag);
          if (el != null) {
            final t = el.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            if (t.isNotEmpty && t.length <= 60) return t;
          }
        }
      } catch (_) {}
    }
    return '第 ${index + 1} 章';
  }

  /// 解析 EPUB
  static Future<ParsedBook> _parseEpub(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final epubBook = await EpubReader.readBook(bytes);

    final title = (epubBook.Title?.trim().isNotEmpty == true)
        ? epubBook.Title!.trim()
        : file.uri.pathSegments.last.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    // Author 为空时尝试 AuthorList
    String author = epubBook.Author?.trim() ?? '';
    if (author.isEmpty) {
      final names = epubBook.AuthorList
              ?.where((a) => a != null && a.trim().isNotEmpty)
              .map((a) => a!.trim())
              .toList() ??
          [];
      author = names.isEmpty ? '未知作者' : names.join('、');
    }

    final buffer = StringBuffer();
    final chapters = <Chapter>[];
    final bookChapters = epubBook.Chapters ?? [];

    // 按 Spine 顺序读取章节
    for (int i = 0; i < bookChapters.length; i++) {
      final chapter = bookChapters[i];
      final htmlContent = chapter.HtmlContent ?? '';
      final startOffset = buffer.length;

      // 提取 HTML 正文（保留段落结构）
      final text = _htmlToText(htmlContent);
      if (text.isEmpty) continue;

      buffer.writeln(text);
      chapters.add(Chapter(
        index: chapters.length,
        title: _chapterTitle(htmlContent, chapter.Title, chapters.length),
        startOffset: startOffset,
        endOffset: buffer.length,
      ));
    }

    // 如果没有章节，尝试从 Content.Html 读取（按文件名排序保证顺序稳定）
    if (chapters.isEmpty && epubBook.Content != null) {
      final htmlFiles = epubBook.Content!.Html;
      if (htmlFiles != null) {
        final entries = htmlFiles.entries.toList()
          ..sort((a, b) => (a.value.FileName ?? '').compareTo(b.value.FileName ?? ''));
        for (final entry in entries) {
          final htmlFile = entry.value;
          final htmlContent = htmlFile.Content ?? '';
          final text = _htmlToText(htmlContent);
          if (text.isEmpty) continue;
          final startOffset = buffer.length;
          buffer.writeln(text);
          chapters.add(Chapter(
            index: chapters.length,
            title: _chapterTitle(htmlContent, htmlFile.FileName, chapters.length),
            startOffset: startOffset,
            endOffset: buffer.length,
          ));
        }
      }
    }

    // 兜底：至少生成一个章节，避免目录空白
    if (chapters.isEmpty) {
      chapters.add(Chapter(
        index: 0,
        title: '正文',
        startOffset: 0,
        endOffset: buffer.length,
      ));
    }

    return ParsedBook(
      title: title,
      author: author,
      content: buffer.toString(),
      chapters: chapters,
    );
  }

  /// 解析 PDF（用 syncfusion 提取纯文本，走统一阅读流程）
  static Future<ParsedBook> _parsePdf(String filePath) async {
    final file = File(filePath);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final title = dot > 0 ? name.substring(0, dot) : name;

    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);
    final text = extractor.extractText();
    document.dispose();

    final content = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 按页分段作为章节（PDF 文本里用换页符分隔）
    final chapters = <Chapter>[];
    final segments = content.split(RegExp(r'\n\s*\n'));
    int offset = 0;
    for (int i = 0; i < segments.length; i++) {
      final start = offset;
      offset += segments[i].length + 2;
      chapters.add(Chapter(
        index: chapters.length,
        title: segments[i].trim().length > 20
            ? segments[i].trim().substring(0, 20)
            : '第 ${i + 1} 段',
        startOffset: start,
        endOffset: offset,
      ));
    }
    if (chapters.isEmpty) {
      chapters.add(Chapter(index: 0, title: '正文', startOffset: 0, endOffset: content.length));
    }
    // 修正最后一章结束位置
    final last = chapters.last;
    chapters[chapters.length - 1] = Chapter(
      index: last.index,
      title: last.title,
      startOffset: last.startOffset,
      endOffset: content.length,
    );

    return ParsedBook(
      title: title,
      author: '未知作者',
      content: content,
      chapters: chapters,
    );
  }

  /// 解析 MOBI/AZW3（基础信息，正文需转换）
  static Future<ParsedBook> _parseMobi(String filePath) async {
    final file = File(filePath);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final title = dot > 0 ? name.substring(0, dot) : name;

    // MOBI/AZW3 是专有格式，Dart 无法直接解析
    // 建议在导入时提示用户用 Calibre 转为 EPUB
    return ParsedBook(
      title: title,
      author: '未知作者',
      content: '此格式为 Amazon 专有格式，建议先用 Calibre 转换为 EPUB 后导入，以获得最佳阅读体验。',
      chapters: [
        Chapter(index: 0, title: '提示', startOffset: 0, endOffset: 80),
      ],
    );
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
