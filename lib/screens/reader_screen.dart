import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/book_parser.dart';
import '../services/database.dart';
import '../services/settings.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final DatabaseService _db = DatabaseService.instance;

  late Book _book;
  ParsedBook? _parsedBook;
  List<Chapter> _chapters = [];
  List<Bookmark> _bookmarks = [];
  List<Note> _notes = [];

  bool _isLoading = true;
  String? _error;
  int _currentChapter = 0;
  int _currentPosition = 0;
  bool _showSettings = false;
  bool _showToolbar = true;

  final PageController _pageController = PageController();
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _currentPosition = widget.book.readPosition;
    _loadBook();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _noteController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadBook() async {
    setState(() => _isLoading = true);
    try {
      final parsed = await BookParser.parse(_book.filePath);
      final bookmarks = await _db.getBookmarks(_book.id!);
      final notes = await _db.getNotes(_book.id!);

      setState(() {
        _parsedBook = parsed;
        _chapters = parsed.chapters;
        _bookmarks = bookmarks;
        _notes = notes;

        // 根据保存的位置找到当前章节
        if (_currentPosition > 0 && _chapters.isNotEmpty) {
          for (int i = _chapters.length - 1; i >= 0; i--) {
            if (_currentPosition >= _chapters[i].startOffset) {
              _currentChapter = i;
              break;
            }
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _saveProgress() {
    final progress = _book.totalChars > 0
        ? (_currentPosition / _book.totalChars).clamp(0.0, 1.0)
        : 0.0;
    _db.updateReadingProgress(_book.id!, _currentPosition, progress);
  }

  void _toggleToolbar() {
    setState(() => _showToolbar = !_showToolbar);
  }

  Future<void> _addBookmark() async {
    final excerpt = _getCurrentExcerpt(40);
    await _db.addBookmark(Bookmark(
      bookId: _book.id!,
      position: _currentPosition,
      excerpt: excerpt,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    final updated = await _db.getBookmarks(_book.id!);
    setState(() {
      _bookmarks = updated;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加书签'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _addNote() async {
    final excerpt = _getCurrentExcerpt(100);
    if (excerpt.isEmpty) return;

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加笔记'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(excerpt, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '写下你的想法...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _db.addNote(Note(
        bookId: _book.id!,
        start: _currentPosition,
        end: _currentPosition + excerpt.length,
        content: excerpt,
        comment: result.isEmpty ? null : result,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      final updatedNotes = await _db.getNotes(_book.id!);
      setState(() {
        _notes = updatedNotes;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记已保存'), duration: Duration(seconds: 1)),
        );
      }
    }
    controller.dispose();
  }

  String _getCurrentExcerpt(int length) {
    if (_parsedBook == null || _parsedBook!.content.isEmpty) return '';
    final start = _currentPosition.clamp(0, _parsedBook!.content.length - 1);
    final end = (start + length).clamp(0, _parsedBook!.content.length);
    return _parsedBook!.content.substring(start, end).trim();
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _currentChapter = index;
      _currentPosition = _chapters[index].startOffset;
    });
    _saveProgress();
  }

  void _jumpToPosition(int position) {
    setState(() => _currentPosition = position);
    if (_chapters.isNotEmpty) {
      for (int i = _chapters.length - 1; i >= 0; i--) {
        if (position >= _chapters[i].startOffset) {
          setState(() => _currentChapter = i);
          break;
        }
      }
    }
    _saveProgress();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>().settings;
    final theme = settings.theme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveProgress();
      },
      child: Scaffold(
        backgroundColor: theme.background,
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: theme.text.withOpacity(0.5)))
            : _error != null
                ? _buildError()
                : _buildReader(theme, settings),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text('打开失败', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              _error ?? '未知错误',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReader(ReaderTheme theme, ReaderSettings settings) {
    return Stack(
      children: [
        // 正文（所有格式统一走文本阅读）
        _buildTextView(theme, settings),

        // 顶部工具栏
        if (_showToolbar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(theme),
          ),

        // 底部工具栏
        if (_showToolbar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(theme),
          ),

        // 设置面板
        if (_showSettings)
          _buildSettingsPanel(theme, settings),
      ],
    );
  }

  Widget _buildTopBar(ReaderTheme theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.background.withOpacity(0.95),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: theme.text),
                onPressed: () {
                  _saveProgress();
                  Navigator.pop(context, true);
                },
              ),
              Expanded(
                child: Text(
                  _book.title,
                  style: TextStyle(color: theme.text, fontSize: 15, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  _bookmarks.any((b) => (b.position - _currentPosition).abs() < 500)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: theme.text,
                ),
                onPressed: _addBookmark,
                tooltip: '书签',
              ),
              IconButton(
                icon: Icon(Icons.list, color: theme.text),
                onPressed: _showChapterList,
                tooltip: '目录',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderTheme theme) {
    final progress = _book.totalChars > 0
        ? (_currentPosition / _book.totalChars).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.background.withOpacity(0.95),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度滑块
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('${_currentChapter + 1}/${_chapters.length}',
                      style: TextStyle(fontSize: 11, color: theme.text.withOpacity(0.6))),
                  Expanded(
                    child: Slider(
                      value: progress,
                      onChanged: (value) {
                        final pos = (value * _book.totalChars).toInt();
                        _jumpToPosition(pos);
                      },
                      activeColor: theme.text.withOpacity(0.6),
                      inactiveColor: theme.text.withOpacity(0.2),
                    ),
                  ),
                  Text('${(progress * 100).toInt()}%',
                      style: TextStyle(fontSize: 11, color: theme.text.withOpacity(0.6))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildToolButton(icon: Icons.notes, label: '笔记', color: theme.text, onTap: _showNotes),
                  _buildToolButton(
                    icon: Icons.format_size,
                    label: '设置',
                    color: theme.text,
                    onTap: () => setState(() => _showSettings = true),
                  ),
                  _buildToolButton(
                    icon: Icons.bookmark_add,
                    label: '书签',
                    color: theme.text,
                    onTap: _showBookmarks,
                  ),
                  _buildToolButton(
                    icon: Icons.brightness_4,
                    label: '夜间',
                    color: theme.text,
                    onTap: _toggleNightMode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color.withOpacity(0.8)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildTextView(ReaderTheme theme, ReaderSettings settings) {
    final content = _getCurrentChapterContent();

    return GestureDetector(
      onTap: _toggleToolbar,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < 0) {
          _nextPage();
        } else if (details.primaryVelocity! > 0) {
          _prevPage();
        }
      },
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: _showToolbar ? 80 : 30,
          bottom: _showToolbar ? 120 : 40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题
            if (_currentChapter < _chapters.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  _chapters[_currentChapter].title,
                  style: TextStyle(
                    fontSize: settings.fontSize + 6,
                    fontWeight: FontWeight.bold,
                    color: theme.text,
                    fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
                    height: settings.lineHeight,
                  ),
                ),
              ),
            // 正文（按段落分割）
            ..._buildParagraphs(content, theme, settings),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParagraphs(String content, ReaderTheme theme, ReaderSettings settings) {
    final paragraphs = content
        .split('\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              '暂无内容',
              style: TextStyle(color: theme.text.withOpacity(0.5), fontSize: settings.fontSize),
            ),
          ),
        ),
      ];
    }

    return paragraphs.map((paragraph) {
      final indent = '　' * settings.indent;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SelectableText(
          '$indent$paragraph',
          style: TextStyle(
            fontSize: settings.fontSize,
            height: settings.lineHeight,
            letterSpacing: settings.letterSpacing,
            color: theme.text,
            fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
          ),
          onTap: _toggleToolbar,
        ),
      );
    }).toList();
  }

  String _getCurrentChapterContent() {
    if (_parsedBook == null) return '';
    final content = _parsedBook!.content;

    if (_chapters.isEmpty || _currentChapter >= _chapters.length) {
      // 按位置截取一页
      final start = _currentPosition;
      final end = (start + 1500).clamp(0, content.length);
      return content.substring(start, end);
    }

    final chapter = _chapters[_currentChapter];
    final start = chapter.startOffset;
    final end = chapter.endOffset.clamp(0, content.length);
    if (start >= end) return '';
    return content.substring(start, end);
  }

  void _nextPage() {
    if (_currentChapter < _chapters.length - 1) {
      _goToChapter(_currentChapter + 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最后一章'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _prevPage() {
    if (_currentChapter > 0) {
      _goToChapter(_currentChapter - 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是第一章'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _toggleNightMode() async {
    final settingsService = context.read<SettingsService>();
    final current = settingsService.settings;
    final newDark = !current.isDarkMode;
    await settingsService.update(current.copyWith(
      isDarkMode: newDark,
      theme: newDark ? ReaderTheme.dark : ReaderTheme.paper,
    ));
  }

  void _showChapterList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChapterListSheet(
        chapters: _chapters,
        currentIndex: _currentChapter,
        onSelect: (index) {
          _goToChapter(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showBookmarks() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BookmarkSheet(
        bookmarks: _bookmarks,
        onSelect: (position) {
          _jumpToPosition(position);
          Navigator.pop(context);
        },
        onDelete: (id) async {
          await _db.deleteBookmark(id);
          final updated = await _db.getBookmarks(_book.id!);
          setState(() {
            _bookmarks = updated;
          });
        },
      ),
    );
  }

  void _showNotes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NoteSheet(
        notes: _notes,
        onSelect: (position) {
          _jumpToPosition(position);
          Navigator.pop(context);
        },
        onAdd: () {
          Navigator.pop(context);
          _addNote();
        },
        onDelete: (id) async {
          await _db.deleteNote(id);
          final updatedNotes = await _db.getNotes(_book.id!);
          setState(() {
            _notes = updatedNotes;
          });
        },
      ),
    );
  }

  Widget _buildSettingsPanel(ReaderTheme theme, ReaderSettings settings) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showSettings = false),
        child: Container(
          color: Colors.black.withOpacity(0.3),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: _SettingsPanel(
              theme: theme,
              settings: settings,
              onClose: () => setState(() => _showSettings = false),
            ),
          ),
        ),
      ),
    );
  }
}

// ============ 子组件 ============

class _ChapterListSheet extends StatelessWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final Function(int) onSelect;

  const _ChapterListSheet({
    required this.chapters,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('目录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${chapters.length} 章', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(
                  chapters[index].title,
                  style: TextStyle(
                    color: index == currentIndex
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight: index == currentIndex ? FontWeight.bold : null,
                  ),
                ),
                trailing: index == currentIndex
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary, size: 18)
                    : null,
                onTap: () => onSelect(index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkSheet extends StatelessWidget {
  final List<Bookmark> bookmarks;
  final Function(int) onSelect;
  final Function(int) onDelete;

  const _BookmarkSheet({
    required this.bookmarks,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('书签', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${bookmarks.length} 个', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: bookmarks.isEmpty
                ? const Center(child: Text('暂无书签'))
                : ListView.builder(
                    itemCount: bookmarks.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(
                        bookmarks[index].excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '位置 ${bookmarks[index].position}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => onSelect(bookmarks[index].position),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => onDelete(bookmarks[index].id!),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoteSheet extends StatelessWidget {
  final List<Note> notes;
  final Function(int) onSelect;
  final VoidCallback onAdd;
  final Function(int) onDelete;

  const _NoteSheet({
    required this.notes,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('笔记', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.add), onPressed: onAdd, tooltip: '添加笔记'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: notes.isEmpty
                ? const Center(child: Text('暂无笔记'))
                : ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(
                        notes[index].content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: notes[index].comment != null
                          ? Text(notes[index].comment!, maxLines: 2)
                          : null,
                      onTap: () => onSelect(notes[index].start),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => onDelete(notes[index].id!),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  final ReaderTheme theme;
  final ReaderSettings settings;
  final VoidCallback onClose;

  const _SettingsPanel({
    required this.theme,
    required this.settings,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final settingsService = context.read<SettingsService>();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('阅读设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 12),

          // 字号
          Row(
            children: [
              const SizedBox(width: 40, child: Text('字号')),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12,
                  max: 32,
                  divisions: 20,
                  label: settings.fontSize.toInt().toString(),
                  onChanged: (v) => settingsService.update(settings.copyWith(fontSize: v)),
                ),
              ),
              SizedBox(width: 30, child: Text('${settings.fontSize.toInt()}')),
            ],
          ),

          // 行距
          Row(
            children: [
              const SizedBox(width: 40, child: Text('行距')),
              Expanded(
                child: Slider(
                  value: settings.lineHeight,
                  min: 1.2,
                  max: 2.5,
                  divisions: 13,
                  onChanged: (v) => settingsService.update(settings.copyWith(lineHeight: v)),
                ),
              ),
              SizedBox(width: 30, child: Text(settings.lineHeight.toStringAsFixed(1))),
            ],
          ),

          // 主题
          const SizedBox(height: 8),
          const Text('背景主题'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ReaderTheme.values.map((t) {
              final selected = t == settings.theme;
              return GestureDetector(
                onTap: () => settingsService.update(settings.copyWith(
                  theme: t,
                  isDarkMode: t.index >= 5,
                )),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: t.background,
                    border: Border.all(
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.withOpacity(0.3),
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '字',
                      style: TextStyle(color: t.text, fontSize: 18),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
