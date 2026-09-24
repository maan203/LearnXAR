// ============================================
// FILE: lib/screens/insights_tab_screen.dart
// Fully dynamic — reads all data from Firestore
// Includes achievements with real conditions
// Quiz attempts deduped (Phase 4)
// Smart recommendations (Phase 4)
// ============================================
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/achievement_service.dart';
import '../services/user_cache.dart';

class InsightsTabScreen extends StatefulWidget {
  final bool isDarkMode;
  const InsightsTabScreen({super.key, this.isDarkMode = false});

  @override
  State<InsightsTabScreen> createState() => InsightsTabScreenState();
}

class InsightsTabScreenState extends State<InsightsTabScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isLoading = true;

  // ── Refresh throttle ─────────────────────────────────────────────────────
  DateTime? _lastLoadedAt;
  int _loadedCacheVersion = -1;
  static const _kRefreshThrottle = Duration(minutes: 3);

  // ── User data ─────────────────────────────────────────────────────────────
  String userName = 'User';
  String predictedLevel = 'Beginner';
  int currentStreak = 0;
  List<String> earnedBadgeIds = [];
  DateTime? lastStudyDate;
  int daysSinceLastStudy = 0;

  // ── Expand/collapse state ────────────────────────────────────────────────
  bool _perfExpanded = false;
  bool _weakExpanded = false;

  // ── Module progress data ──────────────────────────────────────────────────
  Map<String, Map<String, dynamic>> progressMap = {};

  // ── Quiz attempts ─────────────────────────────────────────────────────────
  int totalQuizAttempts = 0;
  double overallAvgScore = 0;
  int totalReadingSecs = 0;
  int totalARSecs = 0;
  int totalQuizSecs = 0;

  // ── Module definitions for display ───────────────────────────────────────
  static const List<Map<String, dynamic>> _moduleList = [
    {'key': 'stack',                    'title': 'Stack',                    'icon': Icons.layers_rounded,             'color': Color(0xFF4044C8)},
    {'key': 'queue',                    'title': 'Queue',                    'icon': Icons.queue_rounded,              'color': Color(0xFF10B981)},
    {'key': 'arrays',                   'title': 'Arrays',                   'icon': Icons.grid_on_rounded,            'color': Color(0xFFF59E0B)},
    {'key': '1d_arrays',                'title': '1D Arrays',                'icon': Icons.table_rows_rounded,         'color': Color(0xFFF59E0B)},
    {'key': '2d_arrays',                'title': '2D Arrays',                'icon': Icons.grid_view_rounded,          'color': Color(0xFFFFB347)},
    {'key': 'multi-dimensional_arrays', 'title': 'Multi-Dimensional Arrays', 'icon': Icons.view_module_rounded,        'color': Color(0xFFFFD700)},
    {'key': 'linked_list',              'title': 'Linked List',              'icon': Icons.link_rounded,               'color': Color(0xFFEF4444)},
    {'key': 'singly_linked_list',       'title': 'Singly Linked List',       'icon': Icons.arrow_forward_rounded,      'color': Color(0xFFEF4444)},
    {'key': 'doubly_linked_list',       'title': 'Doubly Linked List',       'icon': Icons.swap_horiz_rounded,         'color': Color(0xFFFF6B6B)},
    {'key': 'circular_linked_list',     'title': 'Circular Linked List',     'icon': Icons.loop_rounded,               'color': Color(0xFFFF8A80)},
    {'key': 'searching',                'title': 'Searching',                'icon': Icons.search_rounded,             'color': Color(0xFF8B5CF6)},
    {'key': 'linear_search',            'title': 'Linear Search',            'icon': Icons.manage_search_rounded,      'color': Color(0xFF8B5CF6)},
    {'key': 'binary_search',            'title': 'Binary Search',            'icon': Icons.center_focus_strong_rounded,'color': Color(0xFF7C3AED)},
    {'key': 'sorting',                  'title': 'Sorting',                  'icon': Icons.sort_rounded,               'color': Color(0xFFEC4899)},
    {'key': 'bubble_sort',              'title': 'Bubble Sort',              'icon': Icons.bubble_chart_rounded,       'color': Color(0xFFEC4899)},
    {'key': 'selection_sort',           'title': 'Selection Sort',           'icon': Icons.select_all_rounded,         'color': Color(0xFFDB2777)},
    {'key': 'insertion_sort',           'title': 'Insertion Sort',           'icon': Icons.playlist_add_rounded,       'color': Color(0xFFF472B6)},
    {'key': 'merge_sort',               'title': 'Merge Sort',               'icon': Icons.merge_rounded,              'color': Color(0xFFBE185D)},
    {'key': 'quick_sort',               'title': 'Quick Sort',               'icon': Icons.flash_on_rounded,           'color': Color(0xFF9D174D)},
    {'key': 'trees',                    'title': 'Trees',                    'icon': Icons.account_tree_rounded,       'color': Color(0xFF06B6D4)},
    {'key': 'binary_trees',             'title': 'Binary Trees',             'icon': Icons.device_hub_rounded,         'color': Color(0xFF06B6D4)},
    {'key': 'bst',                      'title': 'Binary Search Tree',       'icon': Icons.schema_rounded,             'color': Color(0xFF0891B2)},
    {'key': 'avl_trees',                'title': 'AVL Trees',                'icon': Icons.balance_rounded,            'color': Color(0xFF0E7490)},
    {'key': 'introduction',             'title': 'Introduction',             'icon': Icons.school_rounded,             'color': Color(0xFFFF6B35)},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Called by MainScaffold when user taps Insights tab
  void refreshData() {
    if (!mounted) return;
    final recentlyLoaded = _lastLoadedAt != null &&
        DateTime.now().difference(_lastLoadedAt!) < _kRefreshThrottle;
    final upToDate = _loadedCacheVersion == UserCache.instance.version;
    if (recentlyLoaded && upToDate) return;
    // Reset all state before reloading to avoid stale data
    setState(() {
      isLoading = true;
      _perfExpanded = false;
      _weakExpanded = false;
      progressMap = {};
      totalReadingSecs = 0;
      totalARSecs = 0;
      totalQuizSecs = 0;
      totalQuizAttempts = 0;
      overallAvgScore = 0;
      earnedBadgeIds = [];
    });
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      // Fire all calls in parallel
      final results = await Future.wait([
        _firestore.collection('users').doc(user.uid).get(),
        _firestore.collection('users').doc(user.uid).collection('moduleProgress').get(),
        _firestore.collection('users').doc(user.uid).collection('quizAttempts').get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final progressSnap = results[1] as QuerySnapshot;
      final attemptsSnap = results[2] as QuerySnapshot;

      if (!mounted) return;

      // ── User doc ─────────────────────────────────────────────────────────
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        userName = data['name'] ?? user.displayName ?? 'User';
        predictedLevel = data['predictedLevel'] ?? 'Beginner';
        currentStreak = (data['streak'] ?? 0) as int;
        earnedBadgeIds = List<String>.from(data['achievements'] ?? []);
        lastStudyDate = (data['lastStudyDate'] as Timestamp?)?.toDate();
        if (lastStudyDate != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final last = DateTime(lastStudyDate!.year, lastStudyDate!.month, lastStudyDate!.day);
          daysSinceLastStudy = today.difference(last).inDays;
        }
      }

      // ── Module progress ──────────────────────────────────────────────────
      for (final doc in progressSnap.docs) {
        progressMap[doc.id] = doc.data() as Map<String, dynamic>;
        totalReadingSecs += ((progressMap[doc.id]!['totalReadingSeconds'] ?? 0) as num).toInt();
        totalARSecs += ((progressMap[doc.id]!['totalARSeconds'] ?? 0) as num).toInt();
        totalQuizSecs += ((progressMap[doc.id]!['totalQuizSeconds'] ?? 0) as num).toInt();
      }

      // ── Quiz attempts — dedupe near-duplicates (Phase 4) ─────────────────
      // Two attempts for the same module within 5 seconds are counted as one.
      if (attemptsSnap.docs.isNotEmpty) {
        final List<Map<String, dynamic>> rawAttempts =
        attemptsSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

        // Sort by timestamp so duplicate detection works
        rawAttempts.sort((a, b) {
          final ta = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return ta.compareTo(tb);
        });

        final List<Map<String, dynamic>> deduped = [];
        for (final att in rawAttempts) {
          final String module = (att['moduleKey'] ?? att['module'] ?? '') as String;
          final int ts = (att['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

          // Check if this is a near-duplicate of the most recent kept attempt
          if (deduped.isNotEmpty) {
            final last = deduped.last;
            final String lastModule = (last['moduleKey'] ?? last['module'] ?? '') as String;
            final int lastTs = (last['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            if (lastModule == module && (ts - lastTs).abs() < 5000) {
              continue; // skip duplicate
            }
          }
          deduped.add(att);
        }

        totalQuizAttempts = deduped.length;
        double scoreSum = 0;
        for (final att in deduped) {
          scoreSum += ((att['percentage'] ?? 0.0) as num).toDouble();
        }
        overallAvgScore = totalQuizAttempts > 0 ? scoreSum / totalQuizAttempts : 0;
      } else {
        totalQuizAttempts = 0;
        overallAvgScore = 0;
      }

      if (mounted) setState(() => isLoading = false);
      _lastLoadedAt = DateTime.now();
      _loadedCacheVersion = UserCache.instance.version;
    } catch (e) {
      debugPrint('Error loading insights: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Progress formula (same as learn_screen) ───────────────────────────────
  int _moduleProgress(String key) {
    final data = progressMap[key];
    if (data == null) return 0;
    final double hs = ((data['highestScore'] ?? 0.0) as num).toDouble();
    final int rs = ((data['totalReadingSeconds'] ?? 0) as num).toInt();
    final int ar = ((data['totalARSeconds'] ?? 0) as num).toInt();
    final double q = (hs / 100.0) * 60.0;
    final double r = (rs / 720.0).clamp(0.0, 1.0) * 25.0;
    final double a = (ar / 600.0).clamp(0.0, 1.0) * 15.0;
    return (q + r + a).round().clamp(0, 100);
  }

  int get _completedModules =>
      _moduleList.where((m) => _moduleProgress(m['key'] as String) >= 70).length;

  String _formatTime(int secs) {
    if (secs == 0) return '0m';
    final int h = secs ~/ 3600;
    final int m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  // ── Theme ─────────────────────────────────────────────────────────────────
  bool get dark => widget.isDarkMode;
  Color get _bg => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _border => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);
  Color get _textPrimary => dark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  Color _levelColor(String level) {
    switch (level) {
      case 'Advanced': return const Color(0xFFEF4444);
      case 'Intermediate': return const Color(0xFFF59E0B);
      default: return const Color(0xFF10B981);
    }
  }

  IconData _levelIcon(String level) {
    switch (level) {
      case 'Advanced': return Icons.local_fire_department_rounded;
      case 'Intermediate': return Icons.trending_up_rounded;
      default: return Icons.eco_rounded;
    }
  }

  String _levelMessage(String level) {
    switch (level) {
      case 'Advanced': return 'Impressive! You\'re tackling complex problems with confidence.';
      case 'Intermediate': return 'Great progress! You\'re connecting concepts and going deeper.';
      default: return 'You\'re building a solid foundation! Keep exploring the basics.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4044C8)))
                  : RefreshIndicator(
                onRefresh: () async {
                  setState(() => isLoading = true);
                  progressMap.clear();
                  totalReadingSecs = 0; totalARSecs = 0; totalQuizSecs = 0;
                  totalQuizAttempts = 0; overallAvgScore = 0;
                  await _loadData();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLearningProfileCard(),
                      _buildQuickStatsRow(),
                      _buildStudyTimeCard(),
                      _buildModulePerformance(),
                      _buildWeakStrongAreas(),
                      _buildRecommendations(),
                      _buildAchievements(),
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

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4044C8).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.insights_rounded, color: Color(0xFF4044C8), size: 20),
          ),
          const SizedBox(width: 12),
          Text('My Progress',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _textPrimary)),
        ],
      ),
    );
  }

  // ── Learning Profile Card ─────────────────────────────────────────────────
  Widget _buildLearningProfileCard() {
    final color = _levelColor(predictedLevel);
    final icon = _levelIcon(predictedLevel);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4044C8), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: const Color(0xFF4044C8).withValues(alpha: 0.3),
          blurRadius: 16, offset: const Offset(0, 6),
        )],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Learning Overview', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(userName.split(' ').first,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(predictedLevel,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_levelMessage(predictedLevel),
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String value, String label, IconData icon) {
    return Expanded(child: Column(children: [
      Icon(icon, color: Colors.white70, size: 16),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 10, height: 1.3)),
    ]));
  }

  Widget _statDivider() => Container(
      width: 1, height: 40, color: Colors.white.withValues(alpha: 0.2));

  // ── Quick Stats Row ───────────────────────────────────────────────────────
  Widget _buildQuickStatsRow() {
    final int earnedCount = earnedBadgeIds.length;
    final int totalBadges = AchievementService.allBadges.length;
    final List strong = _moduleList.where((m) {
      final d = progressMap[m['key'] as String];
      return d != null && ((d['highestScore'] ?? 0) as num) >= 75;
    }).toList();
    final List weak = _moduleList.where((m) {
      final d = progressMap[m['key'] as String];
      return d != null && ((d['highestScore'] ?? 0) as num) > 0 && ((d['highestScore'] ?? 0) as num) < 50;
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(children: [
        Expanded(child: _quickStatCard(Icons.emoji_events_rounded,
            '$earnedCount/$totalBadges', 'Badges', const Color(0xFFF59E0B))),
        const SizedBox(width: 12),
        Expanded(child: _quickStatCard(Icons.trending_up_rounded,
            '${strong.length}', 'Strong Topics', const Color(0xFF10B981))),
        const SizedBox(width: 12),
        Expanded(child: _quickStatCard(Icons.flag_rounded,
            '${weak.length}', 'Need Work', const Color(0xFFEF4444))),
      ]),
    );
  }

  Widget _quickStatCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _textPrimary)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: _textSecondary)),
      ]),
    );
  }

  // ── Study Time Breakdown ──────────────────────────────────────────────────
  Widget _buildStudyTimeCard() {
    final int total = totalReadingSecs + totalARSecs + totalQuizSecs;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4044C8).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.timer_rounded, color: Color(0xFF4044C8), size: 18),
          ),
          const SizedBox(width: 10),
          Text('Study Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
          const Spacer(),
          Text(_formatTime(total),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4044C8))),
        ]),
        const SizedBox(height: 16),
        _timeRow('📖 Reading', totalReadingSecs, total, const Color(0xFF10B981)),
        const SizedBox(height: 10),
        _timeRow('🥽 AR', totalARSecs, total, const Color(0xFF06B6D4)),
        const SizedBox(height: 10),
        _timeRow('📝 Quiz', totalQuizSecs, total, const Color(0xFFF59E0B)),
      ]),
    );
  }

  Widget _timeRow(String label, int secs, int total, Color color) {
    final double pct = total > 0 ? secs / total : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontSize: 13, color: _textPrimary)),
        const Spacer(),
        Text(_formatTime(secs), style: TextStyle(fontSize: 12, color: _textSecondary)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: _border,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
        ),
      ),
    ]);
  }

  // ── Module Performance ────────────────────────────────────────────────────
  static const int _kPerfInitial = 5;

  Widget _buildModulePerformance() {
    final attempted = _moduleList.where((m) {
      final d = progressMap[m['key'] as String];
      return d != null && ((d['attempts'] ?? 0) as num) > 0;
    }).toList();

    if (attempted.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
        child: Column(children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF4044C8).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.bar_chart_rounded, color: Color(0xFF4044C8), size: 18)),
            const SizedBox(width: 10),
            Text('Quiz Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
          ]),
          const SizedBox(height: 20),
          Icon(Icons.quiz_outlined, color: _textSecondary, size: 40),
          const SizedBox(height: 8),
          Text('No quizzes taken yet', style: TextStyle(color: _textSecondary)),
        ]),
      );
    }

    final bool canExpand = attempted.length > _kPerfInitial;
    final List visible = _perfExpanded ? attempted : attempted.take(_kPerfInitial).toList();
    final int hidden = attempted.length - _kPerfInitial;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF4044C8).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.bar_chart_rounded, color: Color(0xFF4044C8), size: 18)),
          const SizedBox(width: 10),
          Text('Quiz Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
          const Spacer(),
          Text('${attempted.length} modules', style: TextStyle(fontSize: 12, color: _textSecondary)),
        ]),
        const SizedBox(height: 16),
        ...visible.map((m) {
          final d = progressMap[m['key'] as String]!;
          final double hs = ((d['highestScore'] ?? 0.0) as num).toDouble();
          final Color mColor = m['color'] as Color;
          final Color scoreColor = hs >= 75
              ? const Color(0xFF10B981)
              : hs >= 50
              ? const Color(0xFFF59E0B)
              : const Color(0xFFEF4444);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: mColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Icon(m['icon'] as IconData, color: mColor, size: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(m['title'] as String,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary))),
                Text('${hs.toInt()}%',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scoreColor)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: hs / 100,
                  backgroundColor: _border,
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  minHeight: 6,
                ),
              ),
            ]),
          );
        }),
        if (canExpand)
          GestureDetector(
            onTap: () => setState(() => _perfExpanded = !_perfExpanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF4044C8).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4044C8).withValues(alpha: 0.15)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  _perfExpanded ? 'Show less' : 'Show $hidden more',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4044C8)),
                ),
                const SizedBox(width: 4),
                Icon(
                  _perfExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF4044C8), size: 18,
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Weak/Strong Areas ─────────────────────────────────────────────────────
  static const int _kWeakInitial = 3;

  Widget _buildWeakStrongAreas() {
    final weak = _moduleList.where((m) {
      final d = progressMap[m['key'] as String];
      return d != null && ((d['attempts'] ?? 0) as num) > 0 && ((d['highestScore'] ?? 0) as num) < 50;
    }).toList();

    if (weak.isEmpty) return const SizedBox();

    final bool canExpand = weak.length > _kWeakInitial;
    final List visible = _weakExpanded ? weak : weak.take(_kWeakInitial).toList();
    final int hidden = weak.length - _kWeakInitial;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18)),
          const SizedBox(width: 10),
          Text('Needs Improvement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
          const Spacer(),
          Text('${weak.length} modules', style: TextStyle(fontSize: 12, color: _textSecondary)),
        ]),
        const SizedBox(height: 12),
        ...visible.map((m) {
          final d = progressMap[m['key'] as String]!;
          final double hs = ((d['highestScore'] ?? 0.0) as num).toDouble();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
            ),
            child: Row(children: [
              Icon(m['icon'] as IconData, color: const Color(0xFFEF4444), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['title'] as String,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
                Text('Best score: ${hs.toInt()}% — Review this module',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${hs.toInt()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
              ),
            ]),
          );
        }),
        if (canExpand)
          GestureDetector(
            onTap: () => setState(() => _weakExpanded = !_weakExpanded),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  _weakExpanded ? 'Show less' : 'Show $hidden more',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                ),
                const SizedBox(width: 4),
                Icon(
                  _weakExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFFEF4444), size: 18,
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Recommendations ───────────────────────────────────────────────────────
  Widget _buildRecommendations() {
    final List<Widget> items = [];

    // ── Signal 1: Lost streak / inactive ──
    if (daysSinceLastStudy >= 2) {
      items.add(_recItem(
        Icons.access_time_rounded,
        const Color(0xFFEF4444),
        'Get Back on Track',
        'It\'s been $daysSinceLastStudy days since your last study. A quick 5-minute session can restart your momentum.',
      ));
    } else if (currentStreak >= 3) {
      items.add(_recItem(
        Icons.local_fire_department_rounded,
        const Color(0xFFFF6B35),
        'You\'re On Fire!',
        '$currentStreak-day streak — keep it going with one more session today.',
      ));
    }

    // ── Signal 2: Weak module (score < 50%) ──
    final weakModules = _moduleList.where((m) {
      final d = progressMap[m['key'] as String];
      return d != null
          && ((d['highestScore'] ?? 0) as num) < 50
          && ((d['attempts'] ?? 0) as num) > 0;
    }).toList();

    if (weakModules.isNotEmpty) {
      // Pick the lowest-scoring weak module
      weakModules.sort((a, b) {
        final sa = ((progressMap[a['key']]!['highestScore'] ?? 0) as num).toDouble();
        final sb = ((progressMap[b['key']]!['highestScore'] ?? 0) as num).toDouble();
        return sa.compareTo(sb);
      });
      final m = weakModules.first;
      final score = ((progressMap[m['key']]!['highestScore'] ?? 0) as num).toInt();
      items.add(_recItem(
        Icons.fitness_center_rounded,
        const Color(0xFFEF4444),
        'Practice Weak Area',
        'Your ${m['title']} score is $score%. Revisit the content and retry the quiz for a better grasp.',
      ));
    }

    // ── Signal 3: Study Next (weak or unstarted) ──
    if (weakModules.isEmpty) {
      final unstarted = _moduleList.where((m) {
        final d = progressMap[m['key'] as String];
        return d == null || ((d['attempts'] ?? 0) as num) == 0;
      }).toList();
      if (unstarted.isNotEmpty) {
        items.add(_recItem(
          Icons.play_circle_rounded,
          const Color(0xFF4044C8),
          'Study Next',
          'Move forward with ${unstarted.first['title']} to expand your knowledge.',
        ));
      }
    }

    // ── Signal 4: AR engagement ──
    if (totalARSecs < 120) {
      items.add(_recItem(
        Icons.view_in_ar_rounded,
        const Color(0xFF8B5CF6),
        'Try AR Mode',
        'You haven\'t explored AR yet. Visual learners retain up to 30% more — give it a try on any module.',
      ));
    }

    // ── Signal 5: Reading time balance ──
    if (totalReadingSecs < 300 && totalQuizAttempts > 0) {
      items.add(_recItem(
        Icons.menu_book_rounded,
        const Color(0xFFF59E0B),
        'Read More Theory',
        'You\'ve been quiz-heavy. Spend 5 minutes reading content before your next quiz for better retention.',
      ));
    }

    // ── Signal 6: Level-based study tip (always last as fallback) ──
    final String tip = predictedLevel == 'Advanced'
        ? 'Challenge yourself with complex problems and optimize for efficiency.'
        : predictedLevel == 'Intermediate'
        ? 'Try solving practice problems after each module to reinforce learning.'
        : 'Focus on understanding each concept before moving to the next module.';
    items.add(_recItem(
      Icons.lightbulb_rounded,
      const Color(0xFFF59E0B),
      'Study Tip',
      tip,
    ));

    // Cap at 3 most relevant
    final shown = items.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF10B981).withValues(alpha: 0.15),
          const Color(0xFF4044C8).withValues(alpha: 0.08),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.lightbulb_rounded, color: Color(0xFF10B981), size: 18)),
          const SizedBox(width: 10),
          Text('Recommendations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
        ]),
        const SizedBox(height: 14),
        for (int i = 0; i < shown.length; i++) ...[
          shown[i],
          if (i < shown.length - 1) const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _recItem(IconData icon, Color color, String title, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: _textSecondary, height: 1.4)),
      ])),
    ]);
  }

  // ── Achievements ──────────────────────────────────────────────────────────
  Widget _buildAchievements() {
    final badges = AchievementService.allBadges;
    final earned = earnedBadgeIds.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 18)),
            const SizedBox(width: 10),
            Text('Achievements', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
          ]),
          Text('$earned/${badges.length}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
        ]),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 120,
          ),
          itemCount: badges.length,
          itemBuilder: (context, index) {
            final badge = badges[index];
            final bool isEarned = earnedBadgeIds.contains(badge['id']);
            final Color color = badge['color'] as Color;

            return GestureDetector(
              onTap: () => _showBadgeDetails(badge, isEarned),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isEarned ? color.withValues(alpha: 0.1) : _border.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isEarned ? color.withValues(alpha: 0.4) : _border),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isEarned ? color.withValues(alpha: 0.15) : _border.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(badge['icon'] as IconData,
                        color: isEarned ? color : _textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(badge['title'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: isEarned ? _textPrimary : _textSecondary)),
                  const SizedBox(height: 2),
                  if (!isEarned)
                    const Icon(Icons.lock_rounded, size: 12, color: Color(0xFF9CA3AF)),
                  if (isEarned)
                    const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF10B981)),
                ]),
              ),
            );
          },
        ),
      ]),
    );
  }

  void _showBadgeDetails(Map<String, dynamic> badge, bool isEarned) {
    final Color color = badge['color'] as Color;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isEarned ? color.withValues(alpha: 0.12) : _border.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(badge['icon'] as IconData,
                color: isEarned ? color : _textSecondary, size: 40),
          ),
          const SizedBox(height: 16),
          Text(badge['title'] as String,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textPrimary)),
          const SizedBox(height: 8),
          Text(badge['desc'] as String,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.4)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isEarned ? const Color(0xFF10B981).withValues(alpha: 0.1) : _border.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isEarned ? '✅ Earned' : '🔒 Not yet earned',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: isEarned ? const Color(0xFF10B981) : _textSecondary),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF4044C8), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}