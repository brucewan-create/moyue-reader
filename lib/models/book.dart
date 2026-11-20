import 'dart:io';

/// 支持的书籍格式
enum BookFormat { txt, epub, pdf, mobi, azw3, unknown }

BookFormat formatFromExtension(String path) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'txt':
      return BookFormat.txt;
    case 'epub':
      return BookFormat.epub;
    case 'pdf':
      return BookFormat.pdf;
    case 'mobi':
      return BookFormat.mobi;
    case 'azw3':
    case 'azw':
      return BookFormat.azw3;
    default:
      return BookFormat.unknown;
  }
}

String formatLabel(BookFormat f) {
  switch (f) {
    case BookFormat.txt:
      return 'TXT';
    case BookFormat.epub:
      return 'EPUB';
    case BookFormat.pdf:
      return 'PDF';
    case BookFormat.mobi:
      return 'MOBI';
    case BookFormat.azw3:
      return 'AZW3';
    case BookFormat.unknown:
      return '未知';
  }
}

/// 书籍模型
class Book {
  final int? id;
  final String title;
  final String author;
  final String filePath;
  final String format;
  final int fileSize;
  final int addedAt;
  final int lastReadAt;
  final double progress; // 0.0 ~ 1.0
  final int readPosition; // 字符偏移或页码
  final bool isPinned;
  final String? coverPath;
  final int totalChars;

  Book({
    this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.format,
    required this.fileSize,
    required this.addedAt,
    this.lastReadAt = 0,
    this.progress = 0.0,
    this.readPosition = 0,
    this.isPinned = false,
    this.coverPath,
    this.totalChars = 0,
  });

  BookFormat get bookFormat => formatFromExtension(filePath);

  bool get fileExists => File(filePath).existsSync();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'file_path': filePath,
        'format': format,
        'file_size': fileSize,
        'added_at': addedAt,
        'last_read_at': lastReadAt,
        'progress': progress,
        'read_position': readPosition,
        'is_pinned': isPinned ? 1 : 0,
        'cover_path': coverPath,
        'total_chars': totalChars,
      };

  factory Book.fromMap(Map<String, dynamic> map) => Book(
        id: map['id'] as int?,
        title: map['title'] as String? ?? '未命名',
        author: map['author'] as String? ?? '未知作者',
        filePath: map['file_path'] as String? ?? '',
        format: map['format'] as String? ?? 'txt',
        fileSize: map['file_size'] as int? ?? 0,
        addedAt: map['added_at'] as int? ?? 0,
        lastReadAt: map['last_read_at'] as int? ?? 0,
        progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
        readPosition: map['read_position'] as int? ?? 0,
        isPinned: (map['is_pinned'] as int?) == 1,
        coverPath: map['cover_path'] as String?,
        totalChars: map['total_chars'] as int? ?? 0,
      );

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? filePath,
    String? format,
    int? fileSize,
    int? addedAt,
    int? lastReadAt,
    double? progress,
    int? readPosition,
    bool? isPinned,
    String? coverPath,
    int? totalChars,
  }) =>
      Book(
        id: id ?? this.id,
        title: title ?? this.title,
        author: author ?? this.author,
        filePath: filePath ?? this.filePath,
        format: format ?? this.format,
        fileSize: fileSize ?? this.fileSize,
        addedAt: addedAt ?? this.addedAt,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        progress: progress ?? this.progress,
        readPosition: readPosition ?? this.readPosition,
        isPinned: isPinned ?? this.isPinned,
        coverPath: coverPath ?? this.coverPath,
        totalChars: totalChars ?? this.totalChars,
      );
}

/// 章节
class Chapter {
  final int index;
  final String title;
  final int startOffset;
  final int endOffset;

  Chapter({
    required this.index,
    required this.title,
    required this.startOffset,
    required this.endOffset,
  });
}

/// 书签
class Bookmark {
  final int? id;
  final int bookId;
  final int position;
  final String excerpt;
  final int createdAt;

  Bookmark({
    this.id,
    required this.bookId,
    required this.position,
    required this.excerpt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'book_id': bookId,
        'position': position,
        'excerpt': excerpt,
        'created_at': createdAt,
      };

  factory Bookmark.fromMap(Map<String, dynamic> map) => Bookmark(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        position: map['position'] as int,
        excerpt: map['excerpt'] as String? ?? '',
        createdAt: map['created_at'] as int? ?? 0,
      );
}

/// 划线笔记
class Note {
  final int? id;
  final int bookId;
  final int start;
  final int end;
  final String content;
  final String? comment;
  final String color;
  final int createdAt;

  Note({
    this.id,
    required this.bookId,
    required this.start,
    required this.end,
    required this.content,
    this.comment,
    this.color = 'yellow',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'book_id': bookId,
        'start': start,
        'end': end,
        'content': content,
        'comment': comment,
        'color': color,
        'created_at': createdAt,
      };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        start: map['start'] as int,
        end: map['end'] as int,
        content: map['content'] as String? ?? '',
        comment: map['comment'] as String?,
        color: map['color'] as String? ?? 'yellow',
        createdAt: map['created_at'] as int? ?? 0,
      );
}
