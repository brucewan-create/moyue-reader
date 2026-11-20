import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/book.dart';

/// 本地数据库服务 - Windows 用 ffi，Android 用原生 sqflite
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;
  bool _initialized = false;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (!_initialized) await init();
    return _db!;
  }

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'moyue_reader.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
    _initialized = true;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL UNIQUE,
        format TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        last_read_at INTEGER NOT NULL DEFAULT 0,
        progress REAL NOT NULL DEFAULT 0,
        read_position INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        cover_path TEXT,
        total_chars INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        excerpt TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        start INTEGER NOT NULL,
        end INTEGER NOT NULL,
        content TEXT NOT NULL,
        comment TEXT,
        color TEXT NOT NULL DEFAULT 'yellow',
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_books_pinned ON books(is_pinned)');
    await db.execute('CREATE INDEX idx_books_lastread ON books(last_read_at)');
    await db.execute('CREATE INDEX idx_bookmarks_book ON bookmarks(book_id)');
    await db.execute('CREATE INDEX idx_notes_book ON notes(book_id)');
  }

  // ===== Books =====

  Future<int> insertBook(Book book) async {
    final db = await database;
    return await db.insert('books', book.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Book>> getAllBooks({String? search, String? sortBy}) async {
    final db = await database;
    String? where;
    List<dynamic>? args;
    if (search != null && search.isNotEmpty) {
      where = 'title LIKE ? OR author LIKE ?';
      args = ['%$search%', '%$search%'];
    }

    String orderBy = 'is_pinned DESC, last_read_at DESC';
    switch (sortBy) {
      case 'title':
        orderBy = 'is_pinned DESC, title ASC';
        break;
      case 'added':
        orderBy = 'is_pinned DESC, added_at DESC';
        break;
      case 'progress':
        orderBy = 'is_pinned DESC, progress DESC';
        break;
    }

    final maps = await db.query('books', where: where, whereArgs: args, orderBy: orderBy);
    return maps.map((m) => Book.fromMap(m)).toList();
  }

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<Book?> getBookByPath(String path) async {
    final db = await database;
    final maps = await db.query('books', where: 'file_path = ?', whereArgs: [path]);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<void> updateBook(Book book) async {
    if (book.id == null) return;
    final db = await database;
    await db.update('books', book.toMap(), where: 'id = ?', whereArgs: [book.id]);
  }

  Future<void> updateReadingProgress(int bookId, int position, double progress) async {
    final db = await database;
    await db.update(
      'books',
      {
        'read_position': position,
        'progress': progress,
        'last_read_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> togglePin(int bookId, bool pinned) async {
    final db = await database;
    await db.update('books', {'is_pinned': pinned ? 1 : 0},
        where: 'id = ?', whereArgs: [bookId]);
  }

  Future<void> deleteBook(int bookId) async {
    final db = await database;
    await db.delete('bookmarks', where: 'book_id = ?', whereArgs: [bookId]);
    await db.delete('notes', where: 'book_id = ?', whereArgs: [bookId]);
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);
  }

  // ===== Bookmarks =====

  Future<int> addBookmark(Bookmark bookmark) async {
    final db = await database;
    return await db.insert('bookmarks', bookmark.toMap()..remove('id'));
  }

  Future<List<Bookmark>> getBookmarks(int bookId) async {
    final db = await database;
    final maps = await db.query('bookmarks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'position ASC');
    return maps.map((m) => Bookmark.fromMap(m)).toList();
  }

  Future<void> deleteBookmark(int id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // ===== Notes =====

  Future<int> addNote(Note note) async {
    final db = await database;
    return await db.insert('notes', note.toMap()..remove('id'));
  }

  Future<List<Note>> getNotes(int bookId) async {
    final db = await database;
    final maps = await db.query('notes',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'start ASC');
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  Future<void> updateNote(Note note) async {
    if (note.id == null) return;
    final db = await database;
    await db.update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}
