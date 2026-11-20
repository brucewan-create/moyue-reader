import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;

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

  /// 解析 EPUB
  static Future<ParsedBook> _parseEpub(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final epubBook = await EpubReader.readBook(bytes);

    final title = epubBook.Title ??
        file.uri.pathSegments.last.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    final author = epubBook.Author ?? '未知作者';

    final buffer = StringBuffer();
    final chapters = <Chapter>[];
    final bookChapters = epubBook.Chapters ?? [];

    // 按 Spine 顺序读取章节
    for (int i = 0; i < bookChapters.length; i++) {
      final chapter = bookChapters[i];
      final startOffset = buffer.length;

      // 章节标题
      final chapterTitle = (chapter.Title?.isNotEmpty == true)
          ? chapter.Title!
          : '第 ${i + 1} 章';

      // 提取 HTML 正文
      final htmlContent = chapter.HtmlContent;
      if (htmlContent != null && htmlContent.isNotEmpty) {
        final document = html_parser.parse(htmlContent);
        final text = document.body?.text ?? '';
        buffer.writeln(text.trim());
      }

      if (buffer.length > startOffset) {
        chapters.add(Chapter(
          index: chapters.length,
          title: chapterTitle,
          startOffset: startOffset,
          endOffset: buffer.length,
        ));
      }
    }

    // 如果没有章节，尝试从 Content.Html 读取
    if (chapters.isEmpty && epubBook.Content != null) {
      final htmlFiles = epubBook.Content!.Html;
      if (htmlFiles != null) {
        for (final htmlFile in htmlFiles.values) {
          final startOffset = buffer.length;
          final document = html_parser.parse(htmlFile.Content ?? '');
          final text = document.body?.text ?? '';
          buffer.writeln(text.trim());
          if (buffer.length > startOffset) {
            chapters.add(Chapter(
              index: chapters.length,
              title: htmlFile.FileName ?? '正文',
              startOffset: startOffset,
              endOffset: buffer.length,
            ));
          }
        }
      }
      if (chapters.isEmpty) {
        chapters.add(Chapter(
          index: 0,
          title: '正文',
          startOffset: 0,
          endOffset: buffer.length,
        ));
      }
    }

    return ParsedBook(
      title: title,
      author: author,
      content: buffer.toString(),
      chapters: chapters,
    );
  }

  /// 解析 PDF（仅提取元数据，正文由 pdfrx 直接渲染）
  static Future<ParsedBook> _parsePdf(String filePath) async {
    final file = File(filePath);
    final title = file.uri.pathSegments.last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

    // PDF 正文由专门的 PDF 阅读器组件渲染，这里只返回基础信息
    return ParsedBook(
      title: title,
      author: '未知作者',
      content: '',
      chapters: [],
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
