// ============================================
// FILE: lib/screens/home_screen.dart
// Nav bar REMOVED — handled by MainScaffold
// End-of-day banner added (Phase 5)
// ============================================
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import '../services/streak_service.dart';
import '../services/user_cache.dart';
import '../services/notification_service.dart';

class HomeScreenBody extends StatefulWidget {
  final VoidCallback? onGoToLearn;
  final VoidCallback? onGoToProfile;
  final bool isDarkMode;
  const HomeScreenBody({
    super.key,
    this.onGoToLearn,
    this.onGoToProfile,
    this.isDarkMode = false,
  });

  @override
  HomeScreenBodyState createState() => HomeScreenBodyState();
}

class HomeScreenBodyState extends State<HomeScreenBody>
    with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String userName = "User";
  String userEmail = "";
  int completedModules = 0;
  int totalModules = 8;
  double progressPercentage = 0.0;
  String currentLevel = "Beginner";
  String studyTime = "0m";
  int currentStreak = 0;
  List<Map<String, dynamic>> recentActivities = [];
  bool isLoading = true;

  // ── Refresh throttle ──────────────────────────────────────────────────────
  DateTime? _lastLoadedAt;
  int _loadedCacheVersion = -1;
  static const _kRefreshThrottle = Duration(minutes: 3);

  // ── End-of-day banner state ───────────────────────────────────────────────
  bool _showEndOfDayBanner = false;
  bool _bannerDismissedToday = false;
  bool _streakWasBroken = false;   // true when checkOnLaunch detected a reset
  int  _brokenStreakDays = 0;       // how many days were lost
  static const String _kBannerDismissedDate = 'eod_banner_dismissed_date';

  // ── Module definitions (mirrors LearnScreen — used for progress aggregation)
  static final List<Map<String, dynamic>> _modules = [
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
    WidgetsBinding.instance.addObserver(this);
    _initStreakAndLoad();
  }

  @override
  void dispose() {
    // Flush the app session time on exit
    final uid = _authService.currentUser?.uid;
    if (uid != null) {
      StreakService.trackAppSessionEnd(uid);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground — start a new session window
      StreakService.trackAppSessionStart();
      // Also re-check streak (date may have rolled over)
      StreakService.checkOnLaunch(uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App going to background — flush elapsed time
      StreakService.trackAppSessionEnd(uid);
    }
  }

  Future<void> _initStreakAndLoad() async {
    final uid = _authService.currentUser?.uid;
    if (uid != null) {
      // 1) Reset streak to 0 if user missed a day; fire broken notification if so
      final broken = await StreakService.checkOnLaunch(uid);
      if (broken > 0) {
        _streakWasBroken = true;
        _brokenStreakDays = broken;
        await NotificationService.notifyStreakBroken(broken);
      }
      // 2) Start counting in-app time for today
      await StreakService.trackAppSessionStart();
    }
    // Check banner dismissal state for today
    await _loadBannerDismissedState();
    if (mounted) _loadUserData();
  }

  // Called by MainScaffold when user taps Home tab
  void refreshData() {
    if (!mounted) return;
    final recentlyLoaded = _lastLoadedAt != null &&
        DateTime.now().difference(_lastLoadedAt!) < _kRefreshThrottle;
    final upToDate = _loadedCacheVersion == UserCache.instance.version;
    if (recentlyLoaded && upToDate) return;
    setState(() => isLoading = true);
    _loadUserData();
  }

  // ── Banner dismissal — per-day persistence ────────────────────────────────
  String _todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadBannerDismissedState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDismissed = prefs.getString(_kBannerDismissedDate);
    _bannerDismissedToday = (lastDismissed == _todayKey());
  }

  Future<void> _dismissBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBannerDismissedDate, _todayKey());
    if (mounted) {
      setState(() {
        _bannerDismissedToday = true;
        _showEndOfDayBanner = false;
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      User? currentUser = _authService.currentUser;
      if (currentUser == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final uid = currentUser.uid;

      // Show name immediately without waiting for Firestore
      if (mounted) {
        setState(() {
          userName = currentUser.displayName ??
              currentUser.email?.split('@').first ??
              'User';
          isLoading = false;
        });
      }

      final userRef = _firestore.collection('users').doc(uid);
      final progressRef = userRef.collection('moduleProgress');
      final activitiesRef = userRef
          .collection('activities')
          .orderBy('timestamp', descending: true)
          .limit(20);

      // ── Closure: apply fetched docs to state ──────────────────────────────
      void apply(DocumentSnapshot userDoc, QuerySnapshot moduleProgressSnap,
          QuerySnapshot activitiesSnap) {
        if (!mounted) return;

        // Process user profile
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              userName = data['name'] ??
                  currentUser.displayName ??
                  currentUser.email?.split('@').first ??
                  'User';
              userEmail = data['email'] ?? currentUser.email ?? '';
              currentStreak = ((data['streak'] ?? 0) as num).toInt();
            });
          }
        }

        // Process module progress — only parent module keys
        if (moduleProgressSnap.docs.isNotEmpty) {
          final Map<String, Map<String, dynamic>> progressMap = {};
          for (var doc in moduleProgressSnap.docs) {
            progressMap[doc.id] = doc.data() as Map<String, dynamic>;
          }

          int completed = 0;
          int totalReadSecs = 0;
          int totalQuizSecs = 0;
          int totalARSecs = 0;
          double totalProgressSum = 0;

          // Aggregate subtopic progress into each parent module (same as LearnScreen)
          for (final module in _modules) {
            final double moduleProgress = _aggregateProgress(module, progressMap);
            if (moduleProgress >= 65) completed++;
            totalProgressSum += moduleProgress;
          }

          // Sum time across all docs — subtopics store their own time
          for (final d in progressMap.values) {
            totalReadSecs += ((d['totalReadingSeconds'] ?? 0) as num).toInt();
            totalQuizSecs += ((d['totalQuizSeconds'] ?? 0) as num).toInt();
            totalARSecs += ((d['totalARSeconds'] ?? 0) as num).toInt();
          }

          // Always divide by 8 regardless of how many modules have progress
          final double pct = totalProgressSum / 8;
          final int totalSecs = totalReadSecs + totalQuizSecs + totalARSecs;
          final int mins = totalSecs ~/ 60;
          final String timeStr =
              mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m';
          final String level = pct >= 70
              ? 'Advanced'
              : pct >= 35
                  ? 'Intermediate'
                  : 'Beginner';

          if (mounted) {
            setState(() {
              completedModules = completed;
              progressPercentage = pct;
              currentLevel = level;
              studyTime = totalSecs == 0 ? '0m' : timeStr;
            });
          }
        }

        // Process activities
        if (activitiesSnap.docs.isNotEmpty) {
          final Set<String> seenTitles = {};
          final List<Map<String, dynamic>> activities = [];

          for (var doc in activitiesSnap.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final String title = d['title'] ?? '';
            if (seenTitles.contains(title)) continue;
            seenTitles.add(title);

            final ts = d['timestamp'] as Timestamp?;
            String subtitle = '';
            if (ts != null) {
              final diff = DateTime.now().difference(ts.toDate());
              if (diff.inMinutes < 1) subtitle = 'Just now';
              else if (diff.inMinutes < 60) subtitle = '${diff.inMinutes}m ago';
              else if (diff.inHours < 24) subtitle = '${diff.inHours}h ago';
              else if (diff.inDays == 1) subtitle = 'Yesterday';
              else subtitle = '${diff.inDays} days ago';
            }

            String status = d['status'] ?? '';
            final String type = d['type'] ?? '';
            if (type == 'quiz' && status.isEmpty) status = 'Completed';
            if (type == 'ar') status = 'AR';

            activities.add({
              'title': title,
              'subtitle': subtitle,
              'status': status,
              'isAR': d['isAR'] ?? false,
              'type': type,
            });

            if (activities.length >= 5) break;
          }
          if (mounted) setState(() => recentActivities = activities);
        }

        // ── Banner check ────────────────────────────────────────────────────
        // Show if:
        //  (a) streak was broken this launch (any time of day), OR
        //  (b) past 8 PM AND user hasn't studied today
        // In both cases, dismissed state is respected.
        final now = DateTime.now();
        bool studiedToday = false;
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          final lastStudyTs = data['lastStudyDate'] as Timestamp?;
          if (lastStudyTs != null) {
            final last = lastStudyTs.toDate();
            final today = DateTime(now.year, now.month, now.day);
            final lastDay = DateTime(last.year, last.month, last.day);
            studiedToday = today.isAtSameMomentAs(lastDay);
          }
        }
        // Only warn after 8 PM if user has an active streak worth protecting
        final bool showAfterEight =
            now.hour >= 20 && !studiedToday && currentStreak > 0;
        final bool showBroken = _streakWasBroken && !studiedToday;
        if (mounted) {
          setState(() => _showEndOfDayBanner =
              !_bannerDismissedToday && (showAfterEight || showBroken));
        }

        _lastLoadedAt = DateTime.now();
        _loadedCacheVersion = UserCache.instance.version;
      }

      // ── Cache-first fetch ─────────────────────────────────────────────────
      try {
        // Fast path: show cached data instantly
        final cached = await Future.wait([
          userRef.get(const GetOptions(source: Source.cache)),
          progressRef.get(const GetOptions(source: Source.cache)),
          activitiesRef.get(const GetOptions(source: Source.cache)),
        ]);
        apply(cached[0] as DocumentSnapshot,
            cached[1] as QuerySnapshot, cached[2] as QuerySnapshot);

        // Silently refresh from server in the background
        Future.wait([
          userRef.get(const GetOptions(source: Source.server)),
          progressRef.get(const GetOptions(source: Source.server)),
          activitiesRef.get(const GetOptions(source: Source.server)),
        ]).then((fresh) => apply(fresh[0] as DocumentSnapshot,
                fresh[1] as QuerySnapshot, fresh[2] as QuerySnapshot))
            .catchError(
                (e) => debugPrint('Home screen background refresh: $e'));
      } catch (_) {
        // No local Firestore cache yet — fetch from server normally
        final results = await Future.wait([
          userRef.get(),
          progressRef.get(),
          activitiesRef.get(),
        ]);
        apply(results[0] as DocumentSnapshot,
            results[1] as QuerySnapshot, results[2] as QuerySnapshot);
      }

    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Progress formula: Quiz 60% + Reading 25% + AR 15% ───────────────────
  double _calcProgress(String key, Map<String, Map<String, dynamic>> pm) {
    final data = pm[key];
    if (data == null) return 0.0;
    final double highestScore = ((data['highestScore'] ?? 0.0) as num).toDouble();
    final int readingSecs = ((data['totalReadingSeconds'] ?? 0) as num).toInt();
    final int arSecs = ((data['totalARSeconds'] ?? 0) as num).toInt();
    final double quizComponent = (highestScore / 100.0) * 60.0;
    final double readingComponent = (readingSecs / 360.0).clamp(0.0, 1.0) * 25.0;
    final double arComponent = (arSecs / 300.0).clamp(0.0, 1.0) * 15.0;
    return quizComponent + readingComponent + arComponent;
  }

  // ── For parent modules with subtopics: average own + subtopic progress ───
  double _aggregateProgress(Map<String, dynamic> module, Map<String, Map<String, dynamic>> pm) {
    final String moduleKey = module['moduleKey'] as String;
    final List subtopics = module['subtopics'] as List? ?? [];
    if (subtopics.isEmpty) return _calcProgress(moduleKey, pm);

    // Average subtopics only — overview page has no quiz so including it
    // would cap its contribution at 25% and deflate the module score
    final List<String> subtopicKeys =
        subtopics.map((s) => s['moduleKey'] as String).toList();
    final double total =
        subtopicKeys.fold(0.0, (sum, key) => sum + _calcProgress(key, pm));
    return total / subtopicKeys.length;
  }

  Future<void> _handleLogout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const Login()),
    );
  }

  // ── Color helpers ─────────────────────────────────────────────────────────
  bool get dark => widget.isDarkMode;
  Color get _bg => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _border => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);
  Color get _textPrimary => dark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEndOfDayBanner(),    // Phase 5 — animated nudge after 8 PM
                    _buildWelcomeSection(),    // greeting only
                    _buildStatsRow(),          // modules + streak badges
                    _buildCourseProgressCard(),// course progress
                    _buildRecentActivityCard(),// recent activity
                    const SizedBox(height: 24),
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "LearnXAR",
            style: TextStyle(
              color: Color(0xFF4044C8),
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          PopupMenuButton(
            color: _card,
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF4044C8),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : "U",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(children: [
                  const Icon(Icons.person, size: 18, color: Color(0xFF4044C8)),
                  const SizedBox(width: 8),
                  Text('Profile', style: TextStyle(color: _textPrimary)),
                ]),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  const Icon(Icons.logout, size: 18, color: Color(0xFFE53935)),
                  const SizedBox(width: 8),
                  Text('Logout', style: TextStyle(color: _textPrimary)),
                ]),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') _handleLogout();
              if (value == 'profile' && widget.onGoToProfile != null) widget.onGoToProfile!();
            },
          ),
        ],
      ),
    );
  }

  // ── Streak status banner ─────────────────────────────────────────────────
  Widget _buildEndOfDayBanner() {
    if (!_showEndOfDayBanner) return const SizedBox.shrink();
    final hour = DateTime.now().hour;
    final isLate = hour >= 22;

    // Determine banner mode
    final bool streakBroken = _streakWasBroken;
    final List<Color> gradientColors;
    final IconData bannerIcon;
    final String title;
    final String subtitle;

    if (streakBroken) {
      // Streak already reset — sad message
      gradientColors = [const Color(0xFF6B7280), const Color(0xFF4B5563)];
      bannerIcon = Icons.sentiment_very_dissatisfied_rounded;
      title = "You didn't save your streak 😢";
      subtitle = _brokenStreakDays > 0
          ? 'Your $_brokenStreakDays-day streak ended. Start fresh today!'
          : 'Your streak ended. Start a new one with a quick session!';
    } else if (isLate) {
      gradientColors = [const Color(0xFFEF4444), const Color(0xFFF59E0B)];
      bannerIcon = Icons.warning_amber_rounded;
      title = 'Your streak is at risk! ⚠️';
      subtitle =
          'Open a quick quiz before midnight to keep $currentStreak days going.';
    } else {
      gradientColors = [const Color(0xFFF59E0B), const Color(0xFFFF6B35)];
      bannerIcon = Icons.access_time_rounded;
      title = "Don't forget to study today 🔥";
      subtitle = 'A 5-minute session is all it takes to keep your streak alive.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.95, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        builder: (ctx, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(bannerIcon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _dismissBanner,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Welcome — greeting only, no subtitle lines ───────────────────────────
  Widget _buildWelcomeSection() {
    final firstName = userName.split(' ').first;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final greetingEmoji = hour < 12 ? '☀️' : hour < 17 ? '👋' : '🌙';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4044C8), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4044C8).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $firstName! $greetingEmoji',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ready to keep learning today?',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Animated trophy illustration
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) => Transform.scale(
              scale: value,
              child: child,
            ),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text('🎯', style: TextStyle(fontSize: 32)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats Row — modules + streak with illustrations ───────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.menu_book_rounded,
              value: '$completedModules/$totalModules',
              label: 'Modules Done',
              color: const Color(0xFF4044C8),
              bgColor: const Color(0xFF4044C8).withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.local_fire_department_rounded,
              value: '$currentStreak days',
              label: 'Study Streak',
              color: const Color(0xFFFF6B35),
              bgColor: const Color(0xFFFF6B35).withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: dark ? [] : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.bounceOut,
            builder: (context, val, child) => Transform.scale(scale: val, child: child),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: dark ? Colors.white : const Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(fontSize: 12, color: _textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Course Progress Card ──────────────────────────────────────────────────
  Widget _buildCourseProgressCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with illustration
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Course Progress',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
                    Text('Data Structures & Algorithms',
                        style: TextStyle(fontSize: 12, color: _textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(currentLevel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF10B981))),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Overall Progress', style: TextStyle(fontSize: 13, color: _textSecondary)),
              Text('${progressPercentage.round()}%',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: dark ? Colors.white : const Color(0xFF111827))),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progressPercentage / 100,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4044C8)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),

          // Continue button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { if (widget.onGoToLearn != null) widget.onGoToLearn!(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4044C8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('▶  Continue Learning', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recent Activity ───────────────────────────────────────────────────────
  Widget _buildRecentActivityCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 12),
              Text('Recent Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          if (recentActivities.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.inbox_rounded, color: Color(0xFF9CA3AF), size: 40),
                    const SizedBox(height: 8),
                    Text('No recent activities yet', style: TextStyle(color: _textSecondary)),
                  ],
                ),
              ),
            )
          else
            ...recentActivities.map((activity) => _buildActivityItem(activity)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    String title = activity['title'] ?? 'Unknown Activity';
    String subtitle = activity['subtitle'] ?? '';
    String status = activity['status'] ?? '';
    bool isAR = activity['isAR'] ?? false;
    bool inProgress = status == 'In Progress';

    final IconData activityIcon = isAR
        ? Icons.view_in_ar_rounded
        : status == 'Completed'
        ? Icons.check_circle_rounded
        : Icons.play_circle_rounded;
    Color statusColor = status == 'Completed'
        ? const Color(0xFF10B981)
        : isAR ? const Color(0xFF4044C8) : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(activityIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: dark ? Colors.white : const Color(0xFF111827)),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: _textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (inProgress)
            TextButton(
              onPressed: () { if (widget.onGoToLearn != null) widget.onGoToLearn!(); },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: const Color(0xFF4044C8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Resume', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status,
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}