import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/book_parser.dart';
import '../services/database.dart';
import '../services/pagination.dart';
import '../services/settings.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final DatabaseService _db = DatabaseService.instance;
  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();

  late Book _book;
  ParsedBook? _parsedBook;
  List<Chapter> _chapters = [];
  List<Bookmark> _bookmarks = [];
  List<Note> _notes = [];
  List<BookPage> _pages = [];

  bool _isLoading = true;
  String? _error;
  int _currentChapter = 0;
  int _currentPage = 0;
  bool _showSettings = false;
  bool _showToolbar = false;
  bool _scrollMode = false;

  // 排版缓存 key，设置变化或尺寸变化时重新分页
  Size? _lastPageSize;
  double? _lastFontSize;
  double? _lastLineHeight;
  double? _lastLetterSpacing;
  int? _lastFontFamily;
  int? _lastIndent;
  double? _lastMargin;
  bool _paginationScheduled = false;
  bool _pendingJumpToLast = false; // 切章后是否跳到最后一页

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _currentPosition = widget.book.readPosition;
    _loadBook();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  int _currentPosition = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadBook() async {
    setState(() => _isLoading = true);
    try {
      final parsed = await BookParser.parse(_book.filePath);
      final bookmarks = await _db.getBookmarks(_book.id!);
      final notes = await _db.getNotes(_book.id!);
      if (!mounted) return;
      setState(() {
        _parsedBook = parsed;
        _chapters = parsed.chapters;
        _bookmarks = bookmarks;
        _notes = notes;
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 在 build 中调用：检测到参数变化时，安排帧后重新分页（避免在 build 中 setState）。
  void _ensurePages(Size size, ReaderSettings settings) {
    if (_parsedBook == null || _paginationScheduled) return;
    final changed = _lastPageSize != size ||
        _lastFontSize != settings.fontSize ||
        _lastLineHeight != settings.lineHeight ||
        _lastLetterSpacing != settings.letterSpacing ||
        _lastFontFamily != settings.fontFamilyIndex ||
        _lastIndent != settings.indent ||
        _lastMargin != settings.pageMargin ||
        _pages.isEmpty;

    if (!changed) return;
    _paginationScheduled = true;
    final pendingSettings = settings;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paginationScheduled = false;
      if (!mounted || _parsedBook == null) return;
      _doPaginate(size, pendingSettings);
    });
  }

  void _doPaginate(Size size, ReaderSettings settings) {
    final content = _getCurrentContent();
    final baseOffset = _currentChapter < _chapters.length
        ? _chapters[_currentChapter].startOffset
        : 0;
    final newPages = PaginationService.paginate(
      content: content,
      baseOffset: baseOffset,
      pageSize: size,
      settings: settings,
    );

    // 找出当前位置所在页，保持阅读位置
    int targetPage = 0;
    for (int i = 0; i < newPages.length; i++) {
      if (_currentPosition >= newPages[i].startOffset) targetPage = i;
    }
    if (_pendingJumpToLast && newPages.isNotEmpty) {
      targetPage = newPages.length - 1;
      _pendingJumpToLast = false;
    }

    setState(() {
      _pages = newPages;
      _lastPageSize = size;
      _lastFontSize = settings.fontSize;
      _lastLineHeight = settings.lineHeight;
      _lastLetterSpacing = settings.letterSpacing;
      _lastFontFamily = settings.fontFamilyIndex;
      _lastIndent = settings.indent;
      _lastMargin = settings.pageMargin;
      _currentPage = newPages.isEmpty ? 0 : targetPage.clamp(0, newPages.length - 1);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && newPages.isNotEmpty) {
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  String _getCurrentContent() {
    if (_parsedBook == null) return '';
    final content = _parsedBook!.content;
    if (_chapters.isEmpty) return content; // 无章节时整本当一章，保证能读
    final chapter = _chapters[_currentChapter];
    final start = chapter.startOffset.clamp(0, content.length);
    final end = chapter.endOffset.clamp(start, content.length);
    return content.substring(start, end);
  }

  void _saveProgress() {
    if (_book.totalChars <= 0 || _pages.isEmpty) return;
    final page = _pages[_currentPage.clamp(0, _pages.length - 1)];
    final pos = page.endOffset;
    final progress = (pos / _book.totalChars).clamp(0.0, 1.0);
    _db.updateReadingProgress(_book.id!, pos, progress);
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() {
      _currentPage = index;
      _currentPosition = _pages[index].startOffset;
    });
    _saveProgress();
  }

  /// 下一页：本章还有下一页就翻页，否则进入下一章第一页
  void _nextPage() {
    if (_pages.isEmpty) return;
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else if (_currentChapter < _chapters.length - 1) {
      _goToChapter(_currentChapter + 1);
    } else {
      _showMessage('已是最后一页');
    }
  }

  void _prevPage() {
    if (_pages.isEmpty) return;
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else if (_currentChapter > 0) {
      _goToChapter(_currentChapter - 1, toLastPage: true);
    } else {
      _showMessage('已是第一页');
    }
  }

  void _goToChapter(int index, {bool toLastPage = false}) {
    if (index < 0 || index >= _chapters.length) return;
    _pendingJumpToLast = toLastPage;
    setState(() {
      _currentChapter = index;
      _currentPosition = _chapters[index].startOffset;
      _pages = []; // 触发重新分页
    });
  }

  void _jumpToPosition(int position) {
    if (_parsedBook == null) return;
    _pendingJumpToLast = false;
    setState(() {
      _currentPosition = position.clamp(0, _parsedBook!.content.length);
      _pages = [];
    });
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

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
    );
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _nextPage();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _prevPage();
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.home) {
      _goToChapter(0);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.end) {
      _goToChapter(_chapters.length - 1, toLastPage: true);
    } else if (key == LogicalKeyboardKey.keyM) {
      _showChapterList();
    }
  }

  Future<void> _toggleNightMode() async {
    final service = context.read<SettingsService>();
    final current = service.settings;
    final newDark = !current.isDarkMode;
    await service.update(current.copyWith(
      isDarkMode: newDark,
      theme: newDark ? ReaderTheme.dark : ReaderTheme.paper,
    ));
  }

  void _toggleToolbar() => setState(() => _showToolbar = !_showToolbar);

  String _getCurrentExcerpt(int length) {
    if (_parsedBook == null || _pages.isEmpty) return '';
    final page = _pages[_currentPage.clamp(0, _pages.length - 1)];
    final content = _parsedBook!.content;
    final start = page.startOffset.clamp(0, content.length - 1);
    final end = (start + length).clamp(0, content.length);
    return content.substring(start, end).trim();
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
    if (mounted) setState(() => _bookmarks = updated);
    _showMessage('已添加书签');
  }

  void _showChapterList() {
    if (_chapters.isEmpty) {
      _showMessage('本书没有识别出章节目录');
      return;
    }
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
          if (mounted) setState(() => _bookmarks = updated);
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
          final updated = await _db.getNotes(_book.id!);
          if (mounted) setState(() => _notes = updated);
        },
      ),
    );
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
      final updated = await _db.getNotes(_book.id!);
      if (mounted) setState(() => _notes = updated);
      _showMessage('笔记已保存');
    }
    controller.dispose();
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
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            _handleKey(event);
            return KeyEventResult.handled;
          },
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: theme.text.withOpacity(0.5)))
              : _error != null
                  ? _buildError()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, constraints.maxHeight);
                        _ensurePages(size, settings);
                        return _buildReader(theme, settings);
                      },
                    ),
        ),
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
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('打开失败', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(_error ?? '未知错误', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('返回')),
          ],
        ),
      ),
    );
  }

  Widget _buildReader(ReaderTheme theme, ReaderSettings settings) {
    return GestureDetector(
      // 点击左 1/3 上一页，右 1/3 下一页，中间唤出工具栏
      onTapUp: (details) {
        final x = details.globalPosition.dx;
        final w = MediaQuery.of(context).size.width;
        if (x < w / 3) {
          _prevPage();
        } else if (x > w * 2 / 3) {
          _nextPage();
        } else {
          _toggleToolbar();
        }
      },
      child: Stack(
        children: [
          if (_scrollMode)
            _buildScrollView(theme, settings)
          else
            _buildPageView(theme, settings),

          if (_showToolbar) _buildTopBar(theme),
          if (_showToolbar) _buildBottomBar(theme),
          if (!_showToolbar)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _pages.isEmpty
                      ? ''
                      : '${_currentPage + 1}/${_pages.length}  ·  ${_chapters.isEmpty ? "" : _chapters[_currentChapter].title}',
                  style: TextStyle(fontSize: 11, color: theme.text.withOpacity(0.35)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          if (_showSettings) _buildSettingsPanel(theme, settings),
        ],
      ),
    );
  }

  Widget _buildPageView(ReaderTheme theme, ReaderSettings settings) {
    if (_pages.isEmpty) {
      return Center(
        child: Text('暂无内容', style: TextStyle(color: theme.text.withOpacity(0.5))),
      );
    }
    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemCount: _pages.length,
      physics: settings.pageTurnAnimation
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final page = _pages[index];
        final font = settings.fontFamily.isEmpty ? null : settings.fontFamily;
        return Container(
          color: theme.background,
          padding: EdgeInsets.all(settings.pageMargin),
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: Text(
              page.text,
              style: TextStyle(
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                letterSpacing: settings.letterSpacing,
                color: theme.text,
                fontFamily: font,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScrollView(ReaderTheme theme, ReaderSettings settings) {
    final content = _getCurrentContent();
    final font = settings.fontFamily.isEmpty ? null : settings.fontFamily;
    return SingleChildScrollView(
      padding: EdgeInsets.all(settings.pageMargin),
      child: Text(
        content,
        style: TextStyle(
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          letterSpacing: settings.letterSpacing,
          color: theme.text,
          fontFamily: font,
        ),
      ),
    );
  }

  Widget _buildTopBar(ReaderTheme theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background.withOpacity(0.97),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
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
                  icon: Icon(Icons.bookmark_border, color: theme.text),
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
      ),
    );
  }

  Widget _buildBottomBar(ReaderTheme theme) {
    final progress = _book.totalChars > 0
        ? (_pages.isEmpty ? 0.0 : (_pages[_currentPage].endOffset / _book.totalChars).clamp(0.0, 1.0))
        : 0.0;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background.withOpacity(0.97),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('${_currentPage + 1}/${_pages.length}',
                        style: TextStyle(fontSize: 11, color: theme.text.withOpacity(0.6))),
                    Expanded(
                      child: Slider(
                        value: progress,
                        onChanged: (value) => _jumpToPosition((value * _book.totalChars).toInt()),
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
                    _toolButton(Icons.chevron_left, '上一页', theme.text, _prevPage),
                    _toolButton(Icons.chevron_right, '下一页', theme.text, _nextPage),
                    _toolButton(Icons.format_size, '设置', theme.text,
                        () => setState(() => _showSettings = true)),
                    _toolButton(Icons.bookmark, '书签', theme.text, _showBookmarks),
                    _toolButton(Icons.brightness_4, '夜间', theme.text, _toggleNightMode),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color.withOpacity(0.85)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
          ],
        ),
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
              scrollMode: _scrollMode,
              onScrollModeChanged: (v) => setState(() => _scrollMode = v),
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
  const _ChapterListSheet({required this.chapters, required this.currentIndex, required this.onSelect});

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
                Text('${chapters.length} 章', style: const TextStyle(color: Colors.grey)),
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
                    color: index == currentIndex ? Theme.of(context).colorScheme.primary : null,
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
  const _BookmarkSheet({required this.bookmarks, required this.onSelect, required this.onDelete});

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
                Text('${bookmarks.length} 个', style: const TextStyle(color: Colors.grey)),
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
                      title: Text(bookmarks[index].excerpt, maxLines: 2,
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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
  const _NoteSheet({required this.notes, required this.onSelect, required this.onAdd, required this.onDelete});

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
                      title: Text(notes[index].content, maxLines: 2,
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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
  final bool scrollMode;
  final ValueChanged<bool> onScrollModeChanged;
  final VoidCallback onClose;

  const _SettingsPanel({
    required this.theme,
    required this.settings,
    required this.scrollMode,
    required this.onScrollModeChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final service = context.read<SettingsService>();
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
          _sliderRow('字号', settings.fontSize, 12, 34, 22,
              (v) => service.update(settings.copyWith(fontSize: v)),
              label: settings.fontSize.toInt().toString()),
          _sliderRow('行距', settings.lineHeight, 1.1, 2.4, 13,
              (v) => service.update(settings.copyWith(lineHeight: v)),
              label: settings.lineHeight.toStringAsFixed(1)),
          _sliderRow('字距', settings.letterSpacing, 0, 3, 15,
              (v) => service.update(settings.copyWith(letterSpacing: v)),
              label: settings.letterSpacing.toStringAsFixed(1)),
          _sliderRow('边距', settings.pageMargin, 8, 60, 26,
              (v) => service.update(settings.copyWith(pageMargin: v)),
              label: settings.pageMargin.toInt().toString()),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 60, child: Text('翻页')),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('分页'),
                selected: !scrollMode,
                onSelected: (_) => onScrollModeChanged(false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('滚动'),
                selected: scrollMode,
                onSelected: (_) => onScrollModeChanged(true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('字体', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List.generate(ReaderSettings.fontFamilies.length, (i) {
              return ChoiceChip(
                label: Text(ReaderSettings.fontFamilies[i]),
                selected: settings.fontFamilyIndex == i,
                onSelected: (_) => service.update(settings.copyWith(fontFamilyIndex: i)),
              );
            }),
          ),
          const SizedBox(height: 12),
          const Text('背景主题', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ReaderTheme.values.map((t) {
              final selected = t == settings.theme;
              return GestureDetector(
                onTap: () => service.update(settings.copyWith(
                  theme: t,
                  isDarkMode: t.index >= 5,
                )),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: t.background,
                    border: Border.all(
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.withOpacity(0.3),
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text('字', style: TextStyle(color: t.text, fontSize: 16))),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('电脑快捷键: ← → / 空格 翻页 · M 目录',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max, int divisions,
      ValueChanged<double> onChanged, {required String labelText}) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: labelText,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 34, child: Text(labelText, textAlign: TextAlign.right)),
      ],
    );
  }
}
