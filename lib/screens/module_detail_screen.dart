// ============================================
// FILE: lib/screens/module_detail_screen.dart
// Single dynamic page for ALL modules
// Content changes based on module passed in
// Gemini Flash personalization per level
// ============================================
import 'package:flutter/material.dart';
import 'ar_unity_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'quiz_screen.dart';
import '../services/gemini_service.dart';
import '../services/streak_service.dart';
import '../services/user_cache.dart';

class ModuleDetailScreen extends StatefulWidget {
  final String moduleName;
  final Map<String, dynamic> moduleData;
  final bool isDarkMode;

  const ModuleDetailScreen({
    super.key,
    required this.moduleName,
    required this.moduleData,
    this.isDarkMode = false,
  });

  @override
  ModuleDetailScreenState createState() => ModuleDetailScreenState();
}

class ModuleDetailScreenState extends State<ModuleDetailScreen> {
  bool _isLoadingContent = false;
  String _selectedLevel = 'Beginner';
  List<Map<String, String>>? _personalizedContent;
  String? _contentError;
  bool _levelSelected = false;

  // ── Predicted level from Firestore ────────────────────────────────────────
  String _predictedLevel = 'Beginner';
  // True only when user has a real predicted level from a completed quiz
  // False = new user / no quiz taken yet → show base Firestore content, no Gemini
  bool _hasRealLevel = false;

  // ── Firestore content ──────────────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, String>>? _firestoreContent; // sections from Firestore
  String? _firestoreRawContent;                 // raw content for Gemini
  bool _isLoadingFirestore = true;
  String? _loadError;

  // ── Reading time tracker ──────────────────────────────────────────────────
  final Stopwatch _readingTimer = Stopwatch();
  bool _sessionSaved = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Theme helpers ──────────────────────────────────────────────────────────
  bool get dark => widget.isDarkMode;
  Color get _bg            => dark ? const Color(0xFF0F1117)  : const Color(0xFFF8F9FA);
  Color get _card          => dark ? const Color(0xFF1C1F2E)  : Colors.white;
  Color get _textPrimary   => dark ? Colors.white             : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF)  : const Color(0xFF374151);
  Color get _border        => dark ? const Color(0xFF2D3148)  : const Color(0xFFE5E7EB);
  Color get _headingBg     => dark
      ? const Color(0xFF4044C8).withValues(alpha: 0.18)
      : const Color(0xFF4044C8).withValues(alpha: 0.08);
  Color get _headingText   => dark ? Colors.white : const Color(0xFF4044C8);

  // ── Level config ──────────────────────────────────────────────────────────
  static const List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

  // ── AR-enabled modules ──   ← ADD HERE (inside class, before methods)
  static const Set<String> _arEnabledModules = {
  'stack',
  'introduction',
  'linear_search',
  'binary_search',
  'bubble_sort',
  'selection_sort',
  'insertion_sort',
  'merge_sort',
  'quick_sort',
  'queue',
  'singly_linked_list',
  'doubly_linked_list',
  'circular_linked_list',
  '1d_arrays',
  '2d_arrays',
  'multi-dimensional_arrays',
  'binary_trees',
  'bst',
  'avl_trees',
  };

  bool get _hasARScene => _arEnabledModules.contains(_getModuleKey());
  @override
  void initState() {
    super.initState();
    _readingTimer.start();
    // Load Firestore content FIRST, then load predicted level and auto-personalize
    // This ensures _firestoreRawContent is ready before Gemini is called
    _loadFirestoreContent().then((_) => _loadPredictedLevel());
  }

  @override
  void dispose() {
    _readingTimer.stop();
    _saveReadingSession();
    super.dispose();
  }

  // ── Load global predicted level from users/{uid} ─────────────────────────
  Future<void> _loadPredictedLevel() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data()?['predictedLevel'] != null) {
        final level = doc.data()!['predictedLevel'] as String;
        final lastModule = doc.data()!['lastLevelModule'] as String? ?? '';
        debugPrint('Global predicted level: $level (last set by: $lastModule)');

        if (mounted) {
          setState(() {
            _predictedLevel = level;
            _selectedLevel = level;
            _hasRealLevel = true; // user has taken a quiz
          });
          // Only call Gemini when user has a real predicted level
          _fetchPersonalizedContent(level);
        }
      } else {
        // ── Cold start: new user, no quiz taken yet ──
        // Show Firestore base content as-is — no Gemini call
        // Content is already loaded in _firestoreContent by _loadFirestoreContent()
        debugPrint('New user — showing base Firestore content, no Gemini');
        if (mounted) {
          setState(() {
            _predictedLevel = 'Beginner';
            _selectedLevel = 'Beginner';
            _hasRealLevel = false; // no real level yet
          });
          // Do NOT call _fetchPersonalizedContent here
          // Base content from Firestore will show automatically via _currentContent
        }
      }
    } catch (e) {
      debugPrint('Error loading predicted level: $e');
      // On error, just show base content silently
    }
  }

  Future<void> _saveReadingSession() async {
    if (_sessionSaved) return;
    _sessionSaved = true;
    final duration = _readingTimer.elapsed.inSeconds;
    if (duration < 5) return; // ignore accidental opens

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final moduleKey = _getModuleKey();

      // Save reading session
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('readingSessions')
          .add({
        'module': widget.moduleName,
        'moduleKey': moduleKey,
        'duration': duration,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update module progress with reading time
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('moduleProgress')
          .doc(moduleKey)
          .set({
        'module': widget.moduleName,
        'moduleKey': moduleKey,
        'totalReadingSeconds': FieldValue.increment(duration),
        'lastReadSession': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Streak handled by centralized service (requires 5min reading + 5min app)
      await StreakService.recordReadingTime(uid: user.uid, seconds: duration);

      // Invalidate cached tab data so home/insights/profile reload fresh
      UserCache.instance.invalidate();

      debugPrint('Reading session saved: ${duration}s for ${widget.moduleName}');
    } catch (e) {
      debugPrint('Error saving reading session: $e');
    }
  }


  // ── Module key mapping ────────────────────────────────────────────────────
  String _getModuleKey() {
    const Map<String, String> keyMap = {
      'Stack': 'stack',
      'Introduction': 'introduction',
      'Arrays': 'arrays',
      '1D Arrays': '1d_arrays',
      '2D Arrays': '2d_arrays',
      'Multi-Dimensional Arrays': 'multi-dimensional_arrays',
      'Linked List': 'linked_list',
      'Singly Linked List': 'singly_linked_list',
      'Doubly Linked List': 'doubly_linked_list',
      'Circular Linked List': 'circular_linked_list',
      'Queue': 'queue',
      'Searching': 'searching',
      'Linear Search': 'linear_search',
      'Binary Search': 'binary_search',
      'Sorting': 'sorting',
      'Bubble Sort': 'bubble_sort',
      'Selection Sort': 'selection_sort',
      'Insertion Sort': 'insertion_sort',
      'Merge Sort': 'merge_sort',
      'Quick Sort': 'quick_sort',
      'Trees': 'trees',
      'Binary Trees': 'binary_trees',
      'Binary Search Tree': 'bst',
      'AVL Trees': 'avl_trees',
    };
    return keyMap[widget.moduleName] ??
        widget.moduleName.toLowerCase().replaceAll(' ', '_');
  }

  // ── Quiz key — subtopics redirect to parent module's quiz ────────────────
  String _getQuizKey() {
    // Each module/subtopic uses its OWN quiz collection
    const Map<String, String> quizKeyMap = {
      // Arrays subtopics
      '1D Arrays':                 '1d_arrays',
      '2D Arrays':                 '2d_arrays',
      'Multi-Dimensional Arrays':  'multi-dimensional_arrays',
      // Linked List subtopics
      'Singly Linked List':        'singly_linked_list',
      'Doubly Linked List':        'doubly_linked_list',
      'Circular Linked List':      'circular_linked_list',
      // Searching subtopics
      'Linear Search':             'linear_search',
      'Binary Search':             'binary_search',
      // Sorting subtopics
      'Bubble Sort':               'bubble_sort',
      'Selection Sort':            'selection_sort',
      'Insertion Sort':            'insertion_sort',
      'Merge Sort':                'merge_sort',
      'Quick Sort':                'quick_sort',
      // Trees subtopics
      'Binary Trees':              'binary_trees',
      'Binary Search Tree':        'bst',
      'AVL Trees':                 'avl_trees',
    };
    return quizKeyMap[widget.moduleName] ?? _getModuleKey();
  }

  // ── isOverview: true means this is the parent overview page ──────────────
  // No quiz, no AR — just content reading
  bool get _isOverview => widget.moduleData['isOverview'] == true;

  Future<void> _loadFirestoreContent() async {
    final moduleKey = _getModuleKey();
    debugPrint('Loading Firestore content for: $moduleKey');

    try {
      final moduleDoc = await _firestore
          .collection('modules')
          .doc(moduleKey)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!moduleDoc.exists) {
        if (mounted) setState(() {
          _loadError = 'Content for "${widget.moduleName}" has not been uploaded yet.';
          _isLoadingFirestore = false;
        });
        return;
      }

      final data = moduleDoc.data()!;
      _firestoreRawContent = data['rawContent'] as String?;

      final sectionsSnap = await _firestore
          .collection('modules')
          .doc(moduleKey)
          .collection('sections')
          .get()
          .timeout(const Duration(seconds: 10));

      if (sectionsSnap.docs.isEmpty) {
        if (mounted) setState(() {
          _loadError = 'Sections for "${widget.moduleName}" are empty.';
          _isLoadingFirestore = false;
        });
        return;
      }

      // Sort manually by order field
      final docs = sectionsSnap.docs.toList();
      docs.sort((a, b) {
        final aOrder = (a.data()['order'] as num?)?.toInt() ?? 0;
        final bOrder = (b.data()['order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      });

      _firestoreContent = docs.map((doc) {
        final d = doc.data();
        return {
          'heading': (d['heading'] ?? '') as String,
          'body': (d['body'] ?? '') as String,
        };
      }).toList();

      debugPrint('Sections loaded: ${_firestoreContent!.length}');

    } on TimeoutException {
      if (mounted) setState(() {
        _loadError = 'Connection timed out. Check your internet and try again.';
        _isLoadingFirestore = false;
      });
      return;
    } catch (e) {
      final String err = e.toString();
      String msg;
      if (err.contains('network') || err.contains('unavailable') ||
          err.contains('UNAVAILABLE') || err.contains('SocketException') ||
          err.contains('Failed host lookup')) {
        msg = 'No internet connection. Connect to the internet to load content.';
      } else if (err.contains('permission') || err.contains('PERMISSION_DENIED')) {
        msg = 'Permission denied. Check Firestore security rules.';
      } else {
        msg = 'Failed to load content. Please try again.\nError: $err';
      }
      debugPrint('Firestore error: $err');
      if (mounted) setState(() {
        _loadError = msg;
        _isLoadingFirestore = false;
      });
      return;
    }

    if (mounted) setState(() => _isLoadingFirestore = false);
  }

  Future<void> _retryLoading() async {
    setState(() {
      _isLoadingFirestore = true;
      _loadError = null;
      _firestoreContent = null;
      _firestoreRawContent = null;
    });
    await _loadFirestoreContent();
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'Beginner':     return const Color(0xFF10B981);
      case 'Intermediate': return const Color(0xFFF59E0B);
      case 'Advanced':     return const Color(0xFFEF4444);
      default:             return const Color(0xFF4044C8);
    }
  }

  IconData _levelIcon(String level) {
    switch (level) {
      case 'Beginner':     return Icons.emoji_nature_outlined;
      case 'Intermediate': return Icons.trending_up_rounded;
      case 'Advanced':     return Icons.local_fire_department_outlined;
      default:             return Icons.school_outlined;
    }
  }


  List<Map<String, String>> get _currentContent {
    // 1. Personalized Gemini content — only when available
    if (_personalizedContent != null && _personalizedContent!.isNotEmpty) {
      return _personalizedContent!;
    }
    // 2. Firestore base content — always the fallback
    if (_firestoreContent != null && _firestoreContent!.isNotEmpty) {
      return _firestoreContent!;
    }
    return [];
  }

  bool get _hasBaseContent {
    return _firestoreRawContent != null && _firestoreRawContent!.isNotEmpty;
  }

  String get _rawContentForGemini => _firestoreRawContent ?? '';

  // ── Content source tracking ───────────────────────────────────────────────
  // 'base'     = showing Firestore base content (no level yet)
  // 'loading'  = Gemini is being called
  // 'gemini'   = showing Gemini personalized content
  // 'failed'   = Gemini failed, showing base as fallback
  String _contentSource = 'base';
  String? _geminiError; // brief error shown for a few seconds

  Future<void> _fetchPersonalizedContent(String level) async {
    debugPrint('Fetching Gemini for: $level on ${widget.moduleName}');
    if (!_hasBaseContent) return;

    setState(() {
      _isLoadingContent = true;
      _contentError = null;
      _geminiError = null;
      _contentSource = 'loading';
      _personalizedContent = null; // clear old personalized content
    });

    try {
      final result = await GeminiService.personalizeContent(
        moduleName: _getModuleKey(),
        baseContent: _rawContentForGemini,
        level: level,
      );
      if (mounted) {
        setState(() {
          _personalizedContent = result;
          _isLoadingContent = false;
          _contentSource = 'gemini';
          _geminiError = null;
        });
      }
    } catch (e) {
      debugPrint('Gemini failed: $e');
      if (mounted) {
        setState(() {
          _isLoadingContent = false;
          _personalizedContent = null;
          _contentSource = 'failed';
          _geminiError = 'Failed to personalize content — showing base content';
        });
        // Clear error message after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _geminiError = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = widget.moduleData['completed'] as bool? ?? false;
    final int moduleNumber = widget.moduleData['number'] as int? ?? 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () async {
            _readingTimer.stop();
            await _saveReadingSession();
            if (context.mounted) Navigator.pop(context);
          },
        ),
        title: Text(widget.moduleName,
            style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: _isLoadingFirestore
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(60),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF4044C8)),
                      const SizedBox(height: 16),
                      Text('Loading content...', style: TextStyle(color: _textSecondary)),
                    ],
                  ),
                ),
              )
                  : _loadError != null
                  ? _buildErrorCard()
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModuleHeaderCard(isCompleted),
                  const SizedBox(height: 24),
                  if (!_isOverview && _hasARScene) _buildARCard(),
                  if (!_isOverview && _hasARScene) const SizedBox(height: 24),
                  _buildContentSections(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildBottomQuizButton(),
        ],
      ),
    );
  }

  Widget _buildModuleHeaderCard(bool isCompleted) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4044C8), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.data_object_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.moduleName,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(widget.moduleData['description'] ?? '',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _headerChip(Icons.book_outlined, '${widget.moduleData['topics'] ?? 0} topics'),
              const SizedBox(width: 12),
              _headerChip(Icons.quiz_outlined, '${widget.moduleData['quizQuestions'] ?? 0} questions'),
              const Spacer(),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Completed', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (widget.moduleData['progress'] as int? ?? 0) / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text('${widget.moduleData['progress'] ?? 0}% Complete',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _headerChip(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
  Widget _buildARCard() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ARUnityScreen(
                  moduleName: widget.moduleName,
                  moduleKey: widget.moduleData['moduleKey'] as String? ??
                      _getModuleKey(),
                  isDarkMode: widget.isDarkMode,
                ),
              ),
            );
          },
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF38D9C0), Color(0xFFB8A83A), Color(0xFFE8904A)],
                stops: [0.0, 0.55, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.view_in_ar_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${widget.moduleName} - AR Experience',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentSections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const SizedBox(height: 10),

        // Predicted level badge removed — personalization now silent
        const SizedBox(height: 8),

        // ── Gemini failure toast (auto-dismisses after 4 sec) ─────────────
        if (_geminiError != null)
          AnimatedOpacity(
            opacity: _geminiError != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_geminiError!,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),

        // ── Content error banner ──────────────────────────────────────────
        if (_contentError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_contentError!,
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                ),
              ],
            ),
          ),

        if (_isLoadingContent)
          _buildLoadingShimmer()
        else
          ..._currentContent.map((section) => _buildSection(section)),
      ],
    );
  }

  // ── Source badge — shows where content is coming from ────────────────────
  Widget _buildSourceBadge() {
    String label;
    Color color;
    IconData icon;

    switch (_contentSource) {
      case 'gemini':
        label = '✨ $_selectedLevel';
        color = _levelColor(_selectedLevel);
        icon = Icons.auto_awesome_rounded;
        break;
      case 'loading':
        label = '⏳ Personalizing...';
        color = const Color(0xFF4044C8);
        icon = Icons.hourglass_top_rounded;
        break;
      case 'failed':
        label = '📄 Base Content';
        color = const Color(0xFFF59E0B);
        icon = Icons.warning_amber_rounded;
        break;
      default: // 'base'
        label = '📄 Base Content';
        color = const Color(0xFF9CA3AF);
        icon = Icons.article_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ── Predicted level badge (replaces manual selector) ─────────────────────
  Widget _buildPredictedLevelBadge() {
    final Color color = _hasRealLevel
        ? _levelColor(_predictedLevel)
        : const Color(0xFF9CA3AF);
    final IconData icon = _hasRealLevel
        ? _levelIcon(_predictedLevel)
        : Icons.article_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          if (_hasRealLevel) ...[
            Text(
              'Content personalized for: ',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            Text(
              _predictedLevel,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _showLevelDetails(),
              child: Icon(Icons.info_outline, color: color, size: 16),
            ),
          ] else
            Text(
              'Default Content',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
        ],
      ),
    );
  }

  // ── Show level prediction info (for testing) ──────────────────────────────
  void _showLevelDetails() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(_levelIcon(_predictedLevel),
                color: _levelColor(_predictedLevel), size: 20),
            const SizedBox(width: 8),
            Text('Your Learning Level',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _levelInfoRow('Current Level', _predictedLevel,
                _levelColor(_predictedLevel)),
            const SizedBox(height: 12),
            Text(
              'This is your global learning level — predicted from your quiz performance, time spent, attempts, reading, and AR engagement.',
              style: TextStyle(
                  fontSize: 13, color: _textSecondary, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              'All module content across the app is automatically personalized to this level. It updates every time you complete a quiz.',
              style: TextStyle(
                  fontSize: 13, color: _textSecondary, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it',
                style: TextStyle(
                    color: Color(0xFF4044C8),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _levelInfoRow(String label, String value, Color color) {
    return Row(
      children: [
        Text('$label: ',
            style: TextStyle(fontSize: 13, color: _textSecondary)),
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ),
      ],
    );
  }

  Widget _buildLevelSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2D3148) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: _levels.map((level) {
          final bool isSelected = _selectedLevel == level && _levelSelected;
          final Color color = _levelColor(level);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedLevel = level;
                  _levelSelected = true;
                  _personalizedContent = null;
                });
                _fetchPersonalizedContent(level);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_levelIcon(level), size: 12,
                        color: isSelected ? Colors.white : _textSecondary),
                    const SizedBox(width: 4),
                    Text(level,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : _textSecondary)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSection(Map<String, String> section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _headingBg, borderRadius: BorderRadius.circular(8)),
            child: Text(section['heading'] ?? '',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _headingText)),
          ),
          const SizedBox(height: 10),
          Text(section['body'] ?? '',
              style: TextStyle(fontSize: 14, color: _textSecondary, height: 1.6)),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _levelColor(_selectedLevel)),
              ),
              const SizedBox(width: 14),
              Text('Personalizing for $_selectedLevel level...',
                  style: TextStyle(color: _textSecondary, fontSize: 13)),
            ],
          ),
        ),
        ...List.generate(3, (i) => Container(
          width: double.infinity, height: 100,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2D3148) : Colors.grey[200],
            borderRadius: BorderRadius.circular(14),
          ),
        )),
      ],
    );
  }

  Widget _buildBottomQuizButton() {
    // Overview pages have no quiz button
    if (_isOverview) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuizScreen(
                  moduleName: widget.moduleName,
                  moduleKey: _getQuizKey(), // ← fixed
                  isDarkMode: widget.isDarkMode,
                ),
              ),
            );
          },
          icon: const Icon(Icons.play_circle_outline, size: 20),
          label: Text('Start ${widget.moduleName} Quiz',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4044C8),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  // ── Error Card ────────────────────────────────────────────────────────────
  Widget _buildErrorCard() {
    final bool isNoInternet = _loadError!.contains('internet') ||
        _loadError!.contains('timed out');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isNoInternet
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
                  : const Color(0xFFEF4444).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNoInternet ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 48,
              color: isNoInternet
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isNoInternet ? 'No Internet Connection' : 'Could Not Load Content',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _loadError!,
            style: TextStyle(
                fontSize: 14,
                color: _textSecondary,
                height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _retryLoading,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4044C8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}