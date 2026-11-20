import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/book_parser.dart';
import '../services/database.dart';
import '../screens/reader_screen.dart';
import '../screens/settings_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  final DatabaseService _db = DatabaseService.instance;

  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  bool _isGridView = true;
  bool _isLoading = true;
  String _searchQuery = '';
  String _sortBy = 'recent';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    setState(() => _isLoading = true);
    final books = await _db.getAllBooks(search: _searchQuery, sortBy: _sortBy);
    setState(() {
      _books = books;
      _filteredBooks = books;
      _isLoading = false;
    });
  }

  Future<void> _importFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub', 'pdf', 'mobi', 'azw3', 'azw'],
      );

      if (files.isEmpty) return;

      int imported = 0;
      int skipped = 0;

      for (final file in files) {
        final path = file.path;
        if (path == null) continue;

        // 检查是否已导入
        final existing = await _db.getBookByPath(path);
        if (existing != null) {
          skipped++;
          continue;
        }

        try {
          // 解析文件获取元数据
          final parsed = await BookParser.parse(path);
          final fileStat = File(path).statSync();

          final book = Book(
            title: parsed.title,
            author: parsed.author,
            filePath: path,
            format: formatFromExtension(path).name,
            fileSize: fileStat.size,
            addedAt: DateTime.now().millisecondsSinceEpoch,
            totalChars: parsed.content.length,
          );

          await _db.insertBook(book);
          imported++;
        } catch (e) {
          debugPrint('导入失败 $path: $e');
          skipped++;
        }
      }

      await _loadBooks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入 $imported 本${skipped > 0 ? '，跳过 $skipped 本' : ''}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _openBook(Book book) async {
    if (!book.fileExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在或已被移动，请重新导入')),
        );
      }
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(book: book),
      ),
    );

    if (result == true) await _loadBooks();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    _loadBooks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '墨阅',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? '列表视图' : '网格视图',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _sortBy = value);
              _loadBooks();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'recent', child: Text('最近阅读')),
              const PopupMenuItem(value: 'title', child: Text('书名排序')),
              const PopupMenuItem(value: 'added', child: Text('添加时间')),
              const PopupMenuItem(value: 'progress', child: Text('阅读进度')),
            ],
            icon: const Icon(Icons.sort),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              if (mounted) setState(() {});
            },
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索书名或作者',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // 统计信息
          if (_books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${_books.length} 本书',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${_books.fold<int>(0, (sum, b) => sum + b.fileSize)} 字节',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // 书库
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBooks.isEmpty
                    ? _buildEmptyState()
                    : _isGridView
                        ? _buildGridView()
                        : _buildListView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFiles,
        icon: const Icon(Icons.add),
        label: const Text('导入书籍'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? '没有找到匹配的书籍' : '书架空空如也',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? '换个关键词试试' : '点击右下角「导入书籍」开始',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _filteredBooks.length,
      itemBuilder: (context, index) => _BookCard(
        book: _filteredBooks[index],
        onTap: () => _openBook(_filteredBooks[index]),
        onPin: () async {
          final book = _filteredBooks[index];
          await _db.togglePin(book.id!, !book.isPinned);
          await _loadBooks();
        },
      ),
    );
  }

  Widget _buildListView() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredBooks.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _BookListTile(
        book: _filteredBooks[index],
        onTap: () => _openBook(_filteredBooks[index]),
        onPin: () async {
          final book = _filteredBooks[index];
          await _db.togglePin(book.id!, !book.isPinned);
          await _loadBooks();
        },
      ),
    );
  }
}

/// 网格书籍卡片
class _BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onPin;

  const _BookCard({required this.book, required this.onTap, required this.onPin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatColor = _formatColor(book.bookFormat);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面占位
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: formatColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: formatColor.withOpacity(0.3)),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.book_outlined, size: 36, color: formatColor),
                        const SizedBox(height: 6),
                        Text(
                          formatLabel(book.bookFormat),
                          style: TextStyle(
                            fontSize: 11,
                            color: formatColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (book.isPinned)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(Icons.push_pin, size: 16, color: formatColor),
                    ),
                  // 进度条
                  if (book.progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: book.progress,
                        backgroundColor: Colors.grey.withOpacity(0.2),
                        color: formatColor,
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            '${(book.progress * 100).toInt()}%',
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 列表书籍条目
class _BookListTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onPin;

  const _BookListTile({required this.book, required this.onTap, required this.onPin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatColor = _formatColor(book.bookFormat);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 60,
        decoration: BoxDecoration(
          color: formatColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: formatColor.withOpacity(0.3)),
        ),
        child: Icon(Icons.book_outlined, color: formatColor, size: 24),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (book.isPinned)
            Icon(Icons.push_pin, size: 14, color: theme.colorScheme.primary),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${book.author} · ${formatLabel(book.bookFormat)} · ${BookParser.formatFileSize(book.fileSize)}',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: book.progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            minHeight: 3,
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.push_pin_outlined, size: 18),
        onPressed: onPin,
        tooltip: book.isPinned ? '取消置顶' : '置顶',
      ),
      isThreeLine: true,
    );
  }
}

Color _formatColor(BookFormat format) {
  switch (format) {
    case BookFormat.txt:
      return const Color(0xFF5B7A6B);
    case BookFormat.epub:
      return const Color(0xFF4A6FA5);
    case BookFormat.pdf:
      return const Color(0xFFC0392B);
    case BookFormat.mobi:
    case BookFormat.azw3:
      return const Color(0xFF8E44AD);
    case BookFormat.unknown:
      return Colors.grey;
  }
}
