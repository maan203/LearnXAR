// ============================================
// FILE: lib/screens/learn_screen.dart
// Dynamic — reads progress from Firestore
// Progress = Quiz(60%) + Reading(25%) + AR(15%)
// Parent module aggregates subtopic progress
// ============================================
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'module_detail_screen.dart';
import '../services/user_cache.dart';

class LearnScreen extends StatefulWidget {
  final bool isDarkMode;
  const LearnScreen({super.key, this.isDarkMode = false});

  @override
  LearnScreenState createState() => LearnScreenState();
}

class LearnScreenState extends State<LearnScreen> {
  int? _expandedIndex;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // moduleKey → progress data from Firestore
  Map<String, Map<String, dynamic>> _progressData = {};
  bool _isLoadingProgress = true;

  // ── Local memory cache ────────────────────────────────────────────────────
  DateTime? _lastLoadedAt;
  int _loadedCacheVersion = -1;

  // ── Module definitions ────────────────────────────────────────────────────
  final List<Map<String, dynamic>> modules = [
    {
      'number': 1,
      'title': 'Introduction',
      'description': 'Intro to DSA concepts',
      'topics': 2,
      'quizQuestions': 10,
      'moduleKey': 'introduction',
      'subtopics': [],
    },
    {
      'number': 2,
      'title': 'Arrays',
      'description': 'Learn about arrays and indexing',
      'topics': 3,
      'quizQuestions': 30,
      'moduleKey': 'arrays',
      'subtopics': [
        {'title': '1D Arrays', 'quizQuestions': 10, 'moduleKey': '1d_arrays'},
        {'title': '2D Arrays', 'quizQuestions': 10, 'moduleKey': '2d_arrays'},
        {'title': 'Multi-Dimensional Arrays', 'quizQuestions': 10, 'moduleKey': 'multi-dimensional_arrays'},
      ],
    },
    {
      'number': 3,
      'title': 'Linked List',
      'description': 'Single and double linked lists',
      'topics': 3,
      'quizQuestions': 30,
      'moduleKey': 'linked_list',
      'subtopics': [
        {'title': 'Singly Linked List', 'quizQuestions': 10, 'moduleKey': 'singly_linked_list'},
        {'title': 'Doubly Linked List', 'quizQuestions': 10, 'moduleKey': 'doubly_linked_list'},
        {'title': 'Circular Linked List', 'quizQuestions': 10, 'moduleKey': 'circular_linked_list'},
      ],
    },
    {
      'number': 4,
      'title': 'Stack',
      'description': 'LIFO data structure operations',
      'topics': 1,
      'quizQuestions': 10,
      'moduleKey': 'stack',
      'subtopics': [],
    },
    {
      'number': 5,
      'title': 'Queue',
      'description': 'FIFO data structure operations',
      'topics': 1,
      'quizQuestions': 10,
      'moduleKey': 'queue',
      'subtopics': [],
    },
    {
      'number': 6,
      'title': 'Searching',
      'description': 'Linear and binary search techniques',
      'topics': 2,
      'quizQuestions': 30,
      'moduleKey': 'searching',
      'subtopics': [
        {'title': 'Linear Search', 'quizQuestions': 15, 'moduleKey': 'linear_search'},
        {'title': 'Binary Search', 'quizQuestions': 15, 'moduleKey': 'binary_search'},
      ],
    },
    {
      'number': 7,
      'title': 'Sorting',
      'description': 'Sorting algorithms and complexity',
      'topics': 5,
      'quizQuestions': 50,
      'moduleKey': 'sorting',
      'subtopics': [
        {'title': 'Bubble Sort', 'quizQuestions': 10, 'moduleKey': 'bubble_sort'},
        {'title': 'Selection Sort', 'quizQuestions': 10, 'moduleKey': 'selection_sort'},
        {'title': 'Insertion Sort', 'quizQuestions': 10, 'moduleKey': 'insertion_sort'},
        {'title': 'Merge Sort', 'quizQuestions': 10, 'moduleKey': 'merge_sort'},
        {'title': 'Quick Sort', 'quizQuestions': 10, 'moduleKey': 'quick_sort'},
      ],
    },
    {
      'number': 8,
      'title': 'Trees',
      'description': 'Tree traversals and operations',
      'topics': 3,
      'quizQuestions': 30,
      'moduleKey': 'trees',
      'subtopics': [
        {'title': 'Binary Trees', 'quizQuestions': 10, 'moduleKey': 'binary_trees'},
        {'title': 'Binary Search Tree', 'quizQuestions': 10, 'moduleKey': 'bst'},
        {'title': 'AVL Trees', 'quizQuestions': 10, 'moduleKey': 'avl_trees'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadProgressData();
  }

  // Called by MainScaffold when user switches to Learn tab
  void refreshData() {
    if (!mounted) return;
    if (_loadedCacheVersion != UserCache.instance.version) {
      _loadProgressData();
    }
  }

  Future<void> _loadProgressData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingProgress = false);
        return;
      }

      // Skip entirely if data is fresh and cache version unchanged
      if (_lastLoadedAt != null &&
          DateTime.now().difference(_lastLoadedAt!) <
              const Duration(minutes: 2) &&
          _loadedCacheVersion == UserCache.instance.version) {
        if (mounted) setState(() => _isLoadingProgress = false);
        return;
      }

      final collection = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('moduleProgress');

      void apply(QuerySnapshot snap) {
        final Map<String, Map<String, dynamic>> data = {};
        for (final doc in snap.docs) {
          data[doc.id] = doc.data() as Map<String, dynamic>;
        }
        if (mounted) {
          setState(() {
            _progressData = data;
            _isLoadingProgress = false;
          });
        }
        _lastLoadedAt = DateTime.now();
        _loadedCacheVersion = UserCache.instance.version;
      }

      try {
        // Fast path: show cached data instantly
        final cached =
            await collection.get(const GetOptions(source: Source.cache));
        apply(cached);
        // Silently refresh from server in the background
        collection
            .get(const GetOptions(source: Source.server))
            .then((fresh) => apply(fresh))
            .catchError(
                (e) => debugPrint('Progress background refresh: $e'));
      } catch (_) {
        // No local Firestore cache yet — fetch from server normally
        final fresh = await collection.get();
        apply(fresh);
      }
    } catch (e) {
      debugPrint('Error loading progress: $e');
      if (mounted) setState(() => _isLoadingProgress = false);
    }
  }

  // ── Progress formula: Quiz 60% + Reading 25% + AR 15% ────────────────────
  int _calculateProgress(String moduleKey) {
    final data = _progressData[moduleKey];
    if (data == null) return 0;

    final double highestScore = ((data['highestScore'] ?? 0.0) as num).toDouble();
    final int readingSecs = ((data['totalReadingSeconds'] ?? 0) as num).toInt();
    final int arSecs = ((data['totalARSeconds'] ?? 0) as num).toInt();

    final double quizComponent = (highestScore / 100.0) * 60.0;
    final double readingComponent = (readingSecs / 360.0).clamp(0.0, 1.0) * 25.0;
    final double arComponent = (arSecs / 300.0).clamp(0.0, 1.0) * 15.0;

    return (quizComponent + readingComponent + arComponent).round().clamp(0, 100);
  }

  // ── For parent modules with subtopics: average own + all subtopic progress ─
  int _calculateAggregatedProgress(Map<String, dynamic> module) {
    final String moduleKey = module['moduleKey'] as String;
    final List subtopics = module['subtopics'] as List? ?? [];

    if (subtopics.isEmpty) {
      // No subtopics — just own progress
      return _calculateProgress(moduleKey);
    }

    // Average subtopics only — overview page has no quiz so including it
    // would cap its contribution at 25% and deflate the module score
    final List<String> subtopicKeys =
        subtopics.map((s) => s['moduleKey'] as String).toList();
    final int total =
        subtopicKeys.fold(0, (sum, key) => sum + _calculateProgress(key));
    return (total / subtopicKeys.length).round().clamp(0, 100);
  }

  bool _isCompleted(int progress) => progress >= 65;

  // ── Lock: module is locked if the previous module has progress < 70 ────────
  bool _isModuleLocked(int moduleIndex) {
    // First module is never locked
    if (moduleIndex == 0) return false;

    // If this module itself has any progress, never show it as locked
    // (student already accessed it somehow — don't punish them)
    final int ownProgress = _calculateAggregatedProgress(modules[moduleIndex]);
    if (ownProgress > 0) return false;

    // Otherwise lock if previous module is not completed
    final int prevProgress = _calculateAggregatedProgress(modules[moduleIndex - 1]);
    return prevProgress < 65;
  }

  void _showLockedSheet({
    required String previousModuleName,
    required VoidCallback onContinue,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        decoration: BoxDecoration(
          color: _card,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4044C8).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  size: 40, color: Color(0xFF4044C8)),
            ),
            const SizedBox(height: 16),
            Text(
              'Complete Previous Module First',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'We recommend completing $previousModuleName before starting '
              'this one. This ensures you have the foundation needed.',
              style: TextStyle(
                  fontSize: 14, color: _textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Go Back',
                        style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4044C8), Color(0xFF6A53E7)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onContinue();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Continue Anyway',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Overall progress — aggregate all 8 parent modules via _calculateAggregatedProgress
  double get overallProgress {
    double total = 0;
    for (final module in modules) {
      total += _calculateAggregatedProgress(module);
    }
    return total / modules.length; // always divide by 8
  }

  String get levelLabel {
    if (overallProgress >= 70) return 'Advanced';
    if (overallProgress >= 35) return 'Intermediate';
    return 'Beginner';
  }

  Color get levelColor {
    if (overallProgress >= 70) return const Color(0xFFEF4444);
    if (overallProgress >= 35) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  // ── Theme helpers ──────────────────────────────────────────────────────────
  bool get dark => widget.isDarkMode;
  Color get _bg => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _topBar => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary => dark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _border => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);
  Color get _subtopicBg => dark ? const Color(0xFF252840) : const Color(0xFFF0F4FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Container(
              color: _topBar,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Text('Learn',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (!_isLoadingProgress)
                    GestureDetector(
                      onTap: () {
                        setState(() => _isLoadingProgress = true);
                        _loadProgressData();
                      },
                      child: Icon(Icons.refresh_rounded,
                          color: _textSecondary, size: 20),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: _border),

            Expanded(
              child: _isLoadingProgress
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF4044C8)))
                  : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProgressCard(),
                      const SizedBox(height: 24),
                      Text('Course Modules',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary)),
                      const SizedBox(height: 16),
                      ...modules.asMap().entries.map(
                            (e) => _buildModuleCard(e.value, e.key),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_rounded,
                        color: Color(0xFF4044C8), size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('Course Progress',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: levelColor,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(levelLabel,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Overall Progress',
                  style: TextStyle(fontSize: 13, color: _textSecondary)),
              Text('${overallProgress.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: overallProgress / 100,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF10B981)),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleCard(Map<String, dynamic> module, int index) {
    final int progress = _calculateAggregatedProgress(module);
    final bool completed = _isCompleted(progress);
    final bool isExpanded = _expandedIndex == index;
    final List subtopics = module['subtopics'] as List? ?? [];
    final bool hasSubtopics = subtopics.length > 1;
    final bool locked = _isModuleLocked(index);
    final String prevModuleName =
        index > 0 ? modules[index - 1]['title'] as String : '';

    void handleLockedTap(VoidCallback navigate) {
      if (locked) {
        _showLockedSheet(
            previousModuleName: prevModuleName, onContinue: navigate);
      } else {
        navigate();
      }
    }

    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded
                ? const Color(0xFF4044C8).withValues(alpha: 0.4)
                : _border,
          ),
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isExpanded ? 0 : 14),
                  bottomRight: Radius.circular(isExpanded ? 0 : 14),
                ),
                onTap: () => handleLockedTap(() {
                  if (hasSubtopics) {
                    setState(
                        () => _expandedIndex = isExpanded ? null : index);
                  } else {
                    _navigateToModule(module, progress, completed);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      // ── Progress indicator ──
                      _buildProgressIndicator(progress, completed),
                      const SizedBox(width: 14),

                      // ── Title + lock icon + inline progress bar ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${module['title']}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: _textPrimary),
                                  ),
                                ),
                                if (locked) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.lock_outline,
                                      size: 16,
                                      color: Color(0xFF9CA3AF)),
                                ],
                              ],
                            ),
                            if (progress > 0 && !completed) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress / 100,
                                  backgroundColor: _border,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Color(0xFF4044C8)),
                                  minHeight: 3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ── Right badge ──
                      if (completed)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Text('Completed',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ),
                            if (hasSubtopics) ...[
                              const SizedBox(width: 6),
                              Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: _textSecondary,
                                size: 22,
                              ),
                            ],
                          ],
                        )
                      else
                        Icon(
                          hasSubtopics
                              ? (isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded)
                              : Icons.chevron_right,
                          color: _textSecondary,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Subtopics ──
            if (isExpanded && subtopics.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: _subtopicBg,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Column(
                  children: [
                    Divider(height: 1, color: _border),

                    // ── Overview entry ──
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => handleLockedTap(() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ModuleDetailScreen(
                                moduleName: module['title'] as String,
                                moduleData: {
                                  ...module,
                                  'isOverview': true,
                                  'progress': _calculateProgress(
                                      module['moduleKey'] as String),
                                  'completed': _isCompleted(
                                      _calculateProgress(
                                          module['moduleKey'] as String)),
                                },
                                isDarkMode: widget.isDarkMode,
                              ),
                            ),
                          ).then((_) { if (mounted) _loadProgressData(); });
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4044C8)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.menu_book_outlined,
                                    color: Color(0xFF4044C8), size: 16),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${module['title']} Overview',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Introduction & general concepts',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: _textSecondary, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Divider(
                        height: 1,
                        color: _border,
                        indent: 20,
                        endIndent: 20),

                    // ── Subtopic rows ──
                    ...subtopics.asMap().entries.map((e) {
                      final int i = e.key;
                      final Map sub = e.value as Map;
                      final bool isLast = i == subtopics.length - 1;
                      final String subKey = sub['moduleKey'] as String;
                      final int subProgress = _calculateProgress(subKey);
                      final bool subCompleted = _isCompleted(subProgress);

                      return Column(
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.only(
                                bottomLeft:
                                    Radius.circular(isLast ? 14 : 0),
                                bottomRight:
                                    Radius.circular(isLast ? 14 : 0),
                              ),
                              onTap: () => handleLockedTap(() {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ModuleDetailScreen(
                                      moduleName: sub['title'] as String,
                                      moduleData: {
                                        ...module,
                                        'title': sub['title'],
                                        'quizQuestions':
                                            sub['quizQuestions'],
                                        'moduleKey': sub['moduleKey'],
                                        'topics': 1,
                                        'progress': subProgress,
                                        'completed': subCompleted,
                                      },
                                      isDarkMode: widget.isDarkMode,
                                    ),
                                  ),
                                ).then((_) { if (mounted) _loadProgressData(); });
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                child: Row(
                                  children: [
                                    if (subCompleted)
                                      const Icon(Icons.check_circle,
                                          color: Color(0xFF10B981), size: 18)
                                    else if (subProgress > 0)
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          value: subProgress / 100,
                                          strokeWidth: 2.5,
                                          backgroundColor: _border,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                  Color>(Color(0xFF4044C8)),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 3,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: _border,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(sub['title'] as String,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: _textPrimary)),
                                          const SizedBox(height: 2),
                                          Text(
                                              '${sub['quizQuestions']} quiz questions',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: _textSecondary)),
                                          if (subProgress > 0 &&
                                              !subCompleted) ...[
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: subProgress / 100,
                                                backgroundColor: _border,
                                                valueColor:
                                                    const AlwaysStoppedAnimation<
                                                        Color>(
                                                        Color(0xFF4044C8)),
                                                minHeight: 2,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right,
                                        color: _textSecondary, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!isLast)
                            Divider(
                                height: 1,
                                color: _border,
                                indent: 20,
                                endIndent: 20),
                        ],
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Progress indicator widget ─────────────────────────────────────────────
  Widget _buildProgressIndicator(int progress, bool completed) {
    if (completed) {
      return const Icon(Icons.check_circle,
          color: Color(0xFF10B981), size: 26);
    } else if (progress > 0) {
      return SizedBox(
        width: 26,
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress / 100,
              strokeWidth: 3,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF4044C8)),
            ),
            Text('$progress',
                style: TextStyle(
                    fontSize: 6,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary)),
          ],
        ),
      );
    } else {
      return const Icon(Icons.radio_button_unchecked,
          color: Color(0xFFD1D5DB), size: 26);
    }
  }

  void _navigateToModule(
      Map<String, dynamic> module, int progress, bool completed) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModuleDetailScreen(
          moduleName: module['title'] as String,
          moduleData: {
            ...module,
            'progress': progress,
            'completed': completed,
          },
          isDarkMode: widget.isDarkMode,
        ),
      ),
    ).then((_) { if (mounted) _loadProgressData(); });
  }
}