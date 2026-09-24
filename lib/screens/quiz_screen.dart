// ============================================
// FILE: lib/screens/quiz_screen.dart
// ADAPTIVE QUIZ — starts at medium
// Correct → harder question next
// Wrong   → easier question next
// ============================================
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'quiz_result_screen.dart';
import '../services/achievement_service.dart';
import '../services/user_cache.dart';

class QuizScreen extends StatefulWidget {
  final String moduleName;
  final String moduleKey;
  final bool isDarkMode;

  const QuizScreen({
    super.key,
    required this.moduleName,
    required this.moduleKey,
    this.isDarkMode = false,
  });

  @override
  QuizScreenState createState() => QuizScreenState();
}

class QuizScreenState extends State<QuizScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── All questions split by difficulty ─────────────────────────────────────
  List<Map<String, dynamic>> _easyQuestions   = [];
  List<Map<String, dynamic>> _mediumQuestions = [];
  List<Map<String, dynamic>> _hardQuestions   = [];

  // ── Quiz state ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _selectedQuestions = []; // 10 questions in order shown
  int _currentIndex     = 0;
  int? _selectedAnswer;
  List<int?> _userAnswers = [];
  bool _isLoading = true;
  String? _error;

  // ── Adaptive tracking ──────────────────────────────────────────────────────
  String _currentDifficulty = 'medium'; // starts at medium
  List<String> _difficultyHistory = []; // track difficulty of each question shown
  bool _showDifficulty = false; // user-controlled toggle, hidden by default
  bool _isSubmitting = false; // prevent double-submission
  Set<String> _usedQuestionIds = {};   // avoid repeating questions

  // ── Total quiz length ──────────────────────────────────────────────────────
  static const int _totalQuestions = 10;

  // ── Timer and Auth ────────────────────────────────────────────────────────
  final Stopwatch _quizTimer = Stopwatch();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Theme helpers ──────────────────────────────────────────────────────────
  bool get dark => widget.isDarkMode;
  Color get _bg            => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card          => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary   => dark ? Colors.white            : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _border        => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);

  Color _difficultyColor(String d) {
    switch (d) {
      case 'easy':   return const Color(0xFF10B981);
      case 'medium': return const Color(0xFFF59E0B);
      case 'hard':   return const Color(0xFFEF4444);
      default:       return const Color(0xFF4044C8);
    }
  }

  IconData _difficultyIcon(String d) {
    switch (d) {
      case 'easy':   return Icons.emoji_nature_outlined;
      case 'medium': return Icons.trending_up_rounded;
      case 'hard':   return Icons.local_fire_department_outlined;
      default:       return Icons.school_outlined;
    }
  }

  String _difficultyLabel(String d) {
    switch (d) {
      case 'easy':   return 'Easy';
      case 'medium': return 'Medium';
      case 'hard':   return 'Hard';
      default:       return d;
    }
  }

  @override
  void initState() {
    super.initState();
    _quizTimer.start();
    _loadQuestions();
  }

  // ── Load and split questions by difficulty ─────────────────────────────────
  Future<void> _loadQuestions() async {
    try {
      debugPrint('Loading adaptive questions for: ${widget.moduleKey}');
      final snapshot = await _firestore
          .collection('quizzes')
          .doc(widget.moduleKey)
          .collection('questions')
          .get();

      debugPrint('Total questions found: ${snapshot.docs.length}');

      if (snapshot.docs.isEmpty) {
        setState(() {
          _error = 'No questions found for this module.';
          _isLoading = false;
        });
        return;
      }

      // Split into difficulty buckets
      List<Map<String, dynamic>> easy   = [];
      List<Map<String, dynamic>> medium = [];
      List<Map<String, dynamic>> hard   = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final q = {
          'id': doc.id,
          'question': data['question'] ?? '',
          'options': List<String>.from(data['options'] ?? []),
          'correct': data['correct'] ?? 0,
          'difficulty': data['difficulty'] ?? 'medium',
        };

        switch (q['difficulty']) {
          case 'easy':   easy.add(q);   break;
          case 'hard':   hard.add(q);   break;
          default:       medium.add(q); break;
        }
      }

      // Shuffle each bucket
      easy.shuffle(Random());
      medium.shuffle(Random());
      hard.shuffle(Random());

      debugPrint('Easy: ${easy.length}, Medium: ${medium.length}, Hard: ${hard.length}');

      // If any bucket is empty, fill from others
      if (medium.isEmpty) medium = [...easy, ...hard];
      if (easy.isEmpty)   easy   = medium;
      if (hard.isEmpty)   hard   = medium;

      setState(() {
        _easyQuestions   = easy;
        _mediumQuestions = medium;
        _hardQuestions   = hard;
      });

      // Pick the first question (always medium)
      _startAdaptiveQuiz();

    } catch (e) {
      setState(() {
        _error = 'Failed to load questions: $e';
        _isLoading = false;
      });
    }
  }

  // ── Start quiz with first medium question ──────────────────────────────────
  void _startAdaptiveQuiz() {
    _currentDifficulty = 'medium';
    final firstQuestion = _getNextQuestion('medium');

    if (firstQuestion == null) {
      setState(() {
        _error = 'Not enough questions available.';
        _isLoading = false;
      });
      return;
    }

    _shuffleOptions(firstQuestion);

    setState(() {
      _selectedQuestions = [firstQuestion];
      _difficultyHistory = ['medium'];
      _userAnswers = List.filled(_totalQuestions, null);
      _isLoading = false;
    });
  }

  // ── Get next question from the right difficulty bucket ─────────────────────
  Map<String, dynamic>? _getNextQuestion(String difficulty) {
    List<Map<String, dynamic>> bucket;
    switch (difficulty) {
      case 'easy':  bucket = _easyQuestions;   break;
      case 'hard':  bucket = _hardQuestions;   break;
      default:      bucket = _mediumQuestions; break;
    }

    // Find unused question from bucket
    for (var q in bucket) {
      if (!_usedQuestionIds.contains(q['id'])) {
        _usedQuestionIds.add(q['id'] as String);
        return Map<String, dynamic>.from(q);
      }
    }

    // If all used, try other difficulties
    for (var fallbackBucket in [_mediumQuestions, _easyQuestions, _hardQuestions]) {
      for (var q in fallbackBucket) {
        if (!_usedQuestionIds.contains(q['id'])) {
          _usedQuestionIds.add(q['id'] as String);
          return Map<String, dynamic>.from(q);
        }
      }
    }

    return null;
  }

  // ── Shuffle options and update correct index ───────────────────────────────
  void _shuffleOptions(Map<String, dynamic> question) {
    final options = question['options'] as List<String>;
    final correctAnswer = options[question['correct'] as int];
    options.shuffle(Random());
    question['correct'] = options.indexOf(correctAnswer);
  }

  // ── Adaptive: move difficulty up or down ───────────────────────────────────
  String _moveUp(String current) {
    if (current == 'easy')   return 'medium';
    if (current == 'medium') return 'hard';
    return 'hard';
  }

  String _moveDown(String current) {
    if (current == 'hard')   return 'medium';
    if (current == 'medium') return 'easy';
    return 'easy';
  }

  // ── Select answer ──────────────────────────────────────────────────────────
  void _selectAnswer(int index) {
    setState(() {
      _selectedAnswer = index;
      _userAnswers[_currentIndex] = index;
    });
  }

  // ── Go to next question (adaptive) ────────────────────────────────────────
  void _goNext() {
    if (_currentIndex < _selectedQuestions.length - 1) {
      // Going back to already-seen question
      setState(() {
        _currentIndex++;
        _selectedAnswer = _userAnswers[_currentIndex];
      });
      return;
    }

    // Need to fetch new question adaptively
    if (_selectedQuestions.length < _totalQuestions) {
      final bool wasCorrect = _userAnswers[_currentIndex] ==
          _selectedQuestions[_currentIndex]['correct'];

      // Adjust difficulty based on answer
      final newDifficulty = wasCorrect
          ? _moveUp(_currentDifficulty)
          : _moveDown(_currentDifficulty);

      _currentDifficulty = newDifficulty;

      final nextQuestion = _getNextQuestion(newDifficulty);
      if (nextQuestion != null) {
        _shuffleOptions(nextQuestion);
        setState(() {
          _selectedQuestions.add(nextQuestion);
          _difficultyHistory.add(newDifficulty);
          _currentIndex++;
          _selectedAnswer = null;
        });
      }
    }
  }

  // ── Go to previous question ────────────────────────────────────────────────
  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _selectedAnswer = _userAnswers[_currentIndex];
        _currentDifficulty = _difficultyHistory[_currentIndex];
      });
    }
  }

  // ── Finish quiz ────────────────────────────────────────────────────────────
  void _finishQuiz() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    _quizTimer.stop();
    final int timeTaken = _quizTimer.elapsed.inSeconds;

    int score = 0;
    int easyCorrect   = 0;
    int mediumCorrect = 0;
    int hardCorrect   = 0;
    List<Map<String, dynamic>> wrongQuestions = [];

    for (int i = 0; i < _selectedQuestions.length; i++) {
      final bool correct = _userAnswers[i] == _selectedQuestions[i]['correct'];
      if (correct) {
        score++;
        switch (_difficultyHistory[i]) {
          case 'easy':   easyCorrect++;   break;
          case 'medium': mediumCorrect++; break;
          case 'hard':   hardCorrect++;   break;
        }
      } else {
        // Collect wrong questions for AI feedback
        final q = _selectedQuestions[i];
        final options = q['options'] as List<String>;
        wrongQuestions.add({
          'question': q['question'],
          'correctAnswer': options[q['correct'] as int],
          'userAnswer': _userAnswers[i] != null
              ? options[_userAnswers[i]!]
              : 'Not answered',
          'difficulty': _difficultyHistory[i],
        });
      }
    }

    // ── Fetch previous progress for accurate level prediction ─────────────────
    try {
      final user = _auth.currentUser;
      int previousAttempts = 0;
      double previousHighestScore = 0.0;
      int totalQuizSecsSoFar = 0;
      int totalReadingSecs = 0;
      int totalARSecs = 0;

      if (user != null) {
        try {
          final progressDoc = await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('moduleProgress')
              .doc(widget.moduleKey)
              .get();
          if (progressDoc.exists) {
            final d = progressDoc.data()!;
            previousAttempts = ((d['attempts'] ?? 0) as num).toInt();
            previousHighestScore =
                ((d['highestScore'] ?? 0.0) as num).toDouble();
            totalQuizSecsSoFar =
                ((d['totalQuizSeconds'] ?? 0) as num).toInt();
            totalReadingSecs =
                ((d['totalReadingSeconds'] ?? 0) as num).toInt();
            totalARSecs = ((d['totalARSeconds'] ?? 0) as num).toInt();
          }
        } catch (e) {
          debugPrint('Error fetching previous progress: $e');
        }
      }

      final int thisAttemptNumber = previousAttempts + 1;
      final double percentage = (score / _totalQuestions) * 100;

      // ── Contextual Level Prediction ───────────────────────────────────────
      final String estimatedLevel = _predictLevel(
        scorePercent: percentage,
        timeTakenSecs: timeTaken,
        finalDifficulty: _currentDifficulty,
        attemptNumber: thisAttemptNumber,
        previousHighestScore: previousHighestScore,
        totalReadingSecs: totalReadingSecs,
        totalARSecs: totalARSecs,
        totalQuizSecsSoFar: totalQuizSecsSoFar,
      );

      UserCache.instance.invalidate();

      if (!mounted) return;

      // ── Start save in background, navigate immediately ────────────────────
      final saveFuture = _saveQuizResults(
        score: score,
        timeTaken: timeTaken,
        estimatedLevel: estimatedLevel,
        easyCorrect: easyCorrect,
        mediumCorrect: mediumCorrect,
        hardCorrect: hardCorrect,
        wrongQuestions: wrongQuestions,
        thisAttemptNumber: thisAttemptNumber,
        previousHighestScore: previousHighestScore,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuizResultScreen(
            moduleName: widget.moduleName,
            score: score,
            total: _selectedQuestions.length,
            questions: _selectedQuestions,
            userAnswers: _userAnswers.sublist(0, _selectedQuestions.length),
            isDarkMode: widget.isDarkMode,
            estimatedLevel: estimatedLevel,
            finalDifficulty: _currentDifficulty,
            difficultyHistory: _difficultyHistory,
            easyCorrect: easyCorrect,
            mediumCorrect: mediumCorrect,
            hardCorrect: hardCorrect,
            timeTaken: timeTaken,
            wrongQuestions: wrongQuestions,
            saveFuture: saveFuture,
          ),
        ),
      );
    } catch (e) {
      debugPrint('_finishQuiz error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONTEXTUAL LEVEL PREDICTION
  // Step 1: Base level from score
  // Step 2: Contextual upgrades from behavior patterns
  // Step 3: Contextual downgrades from struggle signals
  // Step 4: Cap at ±1 level from base
  // ══════════════════════════════════════════════════════════════════════════
  String _predictLevel({
    required double scorePercent,       // 0–100
    required int timeTakenSecs,         // seconds for this quiz attempt
    required String finalDifficulty,    // easy / medium / hard
    required int attemptNumber,         // which attempt is this (1,2,3...)
    required double previousHighestScore, // best score before this attempt
    required int totalReadingSecs,      // cumulative reading time
    required int totalARSecs,           // cumulative AR time
    required int totalQuizSecsSoFar,    // cumulative quiz seconds before this
  }) {
    // ── Thresholds ──────────────────────────────────────────────────────────
    const double highScore    = 75.0;   // ≥75% = good
    const double mediumScore  = 50.0;   // 50–74% = medium
    // below 50% = poor

    const int fastQuiz        = 60;     // secs — answered very fast
    const int slowQuiz        = 200;    // secs — took a long time
    const int goodReading     = 600;    // 10 mins reading = engaged
    const int goodAR          = 600;    // 10 mins AR = engaged
    const double improveDelta = 15.0;   // score improved by 15%+ = improving

    // ── STEP 1: Base level from score ──────────────────────────────────────
    String base;
    if (scorePercent >= highScore && attemptNumber >= 2) {
      base = 'Advanced';
    } else if (scorePercent >= mediumScore) {
      base = 'Intermediate';
    } else {
      base = 'Beginner';
    }

    // ── STEP 2: Collect upgrade signals ───────────────────────────────────
    int upgradeSignals = 0;
    List<String> upgradeReasons = [];

    // Signal: High score + fast quiz time → mastery (knows it cold)
    if (scorePercent >= highScore && timeTakenSecs < fastQuiz) {
      upgradeSignals++;
      upgradeReasons.add('Fast+accurate: natural mastery');
    }

    // Signal: High score + low reading time → prior knowledge
    if (scorePercent >= highScore && totalReadingSecs < 120) {
      upgradeSignals++;
      upgradeReasons.add('High score without much reading: prior knowledge');
    }

    // Signal: High score + low AR time → didn't need AR to learn
    if (scorePercent >= highScore && totalARSecs < 120) {
      upgradeSignals++;
      upgradeReasons.add('High score without AR: self-sufficient');
    }

    // Signal: First attempt + high score → confident knowledge
    if (attemptNumber == 1 && scorePercent >= highScore) {
      upgradeSignals++;
      upgradeReasons.add('First attempt success');
    }

    // Signal: Reached hard difficulty + good score
    if (finalDifficulty == 'hard' && scorePercent >= highScore) {
      upgradeSignals++;
      upgradeReasons.add('Excelled at hard difficulty');
    }

    // Signal: Score improved significantly from previous best
    if (attemptNumber > 1 &&
        previousHighestScore > 0 &&
        scorePercent - previousHighestScore >= improveDelta) {
      upgradeSignals++;
      upgradeReasons.add('Significant score improvement across attempts');
    }

    // ── STEP 3: Collect downgrade signals ─────────────────────────────────
    int downgradeSignals = 0;
    List<String> downgradeReasons = [];

    // Signal: High AR time + low score → used AR a lot but still struggling
    if (totalARSecs >= goodAR && scorePercent < mediumScore) {
      downgradeSignals++;
      downgradeReasons.add('Extensive AR time but poor score: struggling');
    }

    // Signal: High reading time + low score → studied but didn't understand
    if (totalReadingSecs >= goodReading && scorePercent < mediumScore) {
      downgradeSignals++;
      downgradeReasons.add('Extensive reading but poor score: comprehension issue');
    }

    // Signal: Slow quiz + low score → guessing slowly / not understanding
    if (timeTakenSecs > slowQuiz && scorePercent < mediumScore) {
      downgradeSignals++;
      downgradeReasons.add('Slow quiz + poor score: struggling');
    }

    // Signal: Multiple attempts + score not improving
    if (attemptNumber >= 3 &&
        previousHighestScore > 0 &&
        scorePercent <= previousHighestScore + 5) {
      downgradeSignals++;
      downgradeReasons.add('Multiple attempts without meaningful improvement: plateauing');
    }

    // Signal: Many attempts + still poor score
    if (attemptNumber >= 3 && scorePercent < mediumScore) {
      downgradeSignals++;
      downgradeReasons.add('Many attempts still below passing: persistent struggle');
    }

    // Signal: Fast quiz + poor score → guessing / not engaging
    if (timeTakenSecs < fastQuiz && scorePercent < mediumScore) {
      downgradeSignals++;
      downgradeReasons.add('Fast quiz but poor score: likely guessing');
    }

    // Signal: Reached hard but score is poor → overreached
    if (finalDifficulty == 'hard' && scorePercent < mediumScore) {
      downgradeSignals++;
      downgradeReasons.add('Reached hard difficulty but poor score: overreached');
    }

    // ── STEP 4: Apply contextual adjustment (cap at ±1 level) ─────────────
    // Net signal: positive = upgrade, negative = downgrade
    final int netSignal = upgradeSignals - downgradeSignals;

    String finalLevel = base;

    if (netSignal >= 2) {
      // Strong upgrade signal — go up one level from base
      if (base == 'Beginner') finalLevel = 'Intermediate';
      else if (base == 'Intermediate') finalLevel = 'Advanced';
      else finalLevel = 'Advanced'; // already max
    } else if (netSignal <= -2) {
      // Strong downgrade signal — go down one level from base
      if (base == 'Advanced') finalLevel = 'Intermediate';
      else if (base == 'Intermediate') finalLevel = 'Beginner';
      else finalLevel = 'Beginner'; // already min
    } else {
      // Weak or neutral signals — stay at base
      finalLevel = base;
    }

    // Debug log for testing
    debugPrint('═══ LEVEL PREDICTION for ${widget.moduleName} ═══');
    debugPrint('Score: $scorePercent% | Time: ${timeTakenSecs}s | Attempt: $attemptNumber');
    debugPrint('Reading: ${totalReadingSecs}s | AR: ${totalARSecs}s | Difficulty: $finalDifficulty');
    debugPrint('Base level: $base');
    debugPrint('Upgrade signals ($upgradeSignals): $upgradeReasons');
    debugPrint('Downgrade signals ($downgradeSignals): $downgradeReasons');
    debugPrint('Net signal: $netSignal → Final level: $finalLevel');
    debugPrint('═══════════════════════════════════════════════');

    return finalLevel;
  }

  // ── Save quiz results to Firestore ─────────────────────────────────────────
  // Each step has its own try-catch so a failure in one never blocks the streak.
  Future<({int oldStreak, int newStreak, List<Map<String, dynamic>> newBadges})> _saveQuizResults({
    required int score,
    required int timeTaken,
    required String estimatedLevel,
    required int easyCorrect,
    required int mediumCorrect,
    required int hardCorrect,
    required List<Map<String, dynamic>> wrongQuestions,
    required int thisAttemptNumber,
    required double previousHighestScore,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return (oldStreak: 0, newStreak: 0, newBadges: <Map<String, dynamic>>[]);

    final double percentage = (score / _totalQuestions) * 100;
    final double newHighest =
        percentage > previousHighestScore ? percentage : previousHighestScore;

    // 1. Save quiz attempt
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('quizAttempts')
          .add({
        'module': widget.moduleName,
        'moduleKey': widget.moduleKey,
        'score': score,
        'total': _totalQuestions,
        'percentage': percentage,
        'timeTaken': timeTaken,
        'estimatedLevel': estimatedLevel,
        'finalDifficulty': _currentDifficulty,
        'easyCorrect': easyCorrect,
        'mediumCorrect': mediumCorrect,
        'hardCorrect': hardCorrect,
        'wrongQuestions': wrongQuestions,
        'difficultyHistory': _difficultyHistory,
        'attemptNumber': thisAttemptNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Step 1 quizAttempts write failed: $e');
    }

    // 2. Update module progress
    try {
      final progressRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('moduleProgress')
          .doc(widget.moduleKey);
      await progressRef.set({
        'module': widget.moduleName,
        'moduleKey': widget.moduleKey,
        'highestScore': newHighest,
        'lastScore': percentage,
        'attempts': thisAttemptNumber,
        'estimatedLevel': estimatedLevel,
        'predictedLevel': estimatedLevel,
        'lastAttempt': FieldValue.serverTimestamp(),
        'totalQuizSeconds': FieldValue.increment(timeTaken),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Step 2 moduleProgress write failed: $e');
    }

    // 3. Update predicted level on user doc
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'predictedLevel': estimatedLevel,
        'lastLevelUpdate': FieldValue.serverTimestamp(),
        'lastLevelModule': widget.moduleName,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Step 3 predictedLevel write failed: $e');
    }

    // 4. Save recent activity
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('activities')
          .add({
        'title': 'Completed ${widget.moduleName} Quiz',
        'subtitle': 'Score: $score/$_totalQuestions · ${timeTaken}s',
        'type': 'quiz',
        'module': widget.moduleName,
        'moduleKey': widget.moduleKey,
        'isAR': false,
        'status': percentage >= 50 ? 'Completed' : 'In Progress',
        'score': score,
        'total': _totalQuestions,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Step 4 activities write failed: $e');
    }

    // 5. Update streak — direct Firestore write, no service indirection
    ({int oldStreak, int newStreak}) streakResult = (oldStreak: 0, newStreak: 0);
    try {
      final userRef = _firestore.collection('users').doc(user.uid);
      final snap = await userRef.get();
      final data = (snap.data() as Map<String, dynamic>?) ?? {};
      final int currentStreak = ((data['streak'] ?? 0) as num).toInt();
      final lastStudyRaw = data['lastStudyDate'];

      debugPrint('📊 Streak read — doc exists: ${snap.exists}, streak: $currentStreak, lastStudy: $lastStudyRaw');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int newStreak;
      if (lastStudyRaw == null) {
        newStreak = 1;
      } else {
        final lastStudy = (lastStudyRaw as Timestamp).toDate();
        final lastDay =
            DateTime(lastStudy.year, lastStudy.month, lastStudy.day);
        final diff = today.difference(lastDay).inDays;
        if (diff == 0) {
          newStreak = currentStreak <= 0 ? 1 : currentStreak;
        } else if (diff == 1) {
          newStreak = currentStreak + 1;
        } else {
          newStreak = 1;
        }
      }

      debugPrint('📝 Writing streak: $currentStreak → $newStreak');
      // set(merge:true) works even if the document was never created at signup
      await userRef.set({
        'streak': newStreak,
        'lastStudyDate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ Streak written: $currentStreak → $newStreak');
      streakResult = (oldStreak: currentStreak, newStreak: newStreak);
    } catch (e) {
      debugPrint('❌ Streak write FAILED: $e');
    }

    // 6. Check and unlock achievements
    List<Map<String, dynamic>> newBadges = [];
    try {
      newBadges = await AchievementService.checkAndUnlock(
        uid: user.uid,
        firestore: _firestore,
        quizScore: percentage,
        quizTimeSecs: timeTaken,
        attemptNumber: thisAttemptNumber,
        previousHighestScore: previousHighestScore,
        moduleKey: widget.moduleKey,
      );
    } catch (e) {
      debugPrint('❌ Achievement check failed: $e');
    }

    // 7. Recalculate global predicted level across all modules
    await _classifyGlobalLevel(user.uid, widget.moduleKey);

    return (oldStreak: streakResult.oldStreak, newStreak: streakResult.newStreak, newBadges: newBadges);
  }

  // ── Check if can go next ───────────────────────────────────────────────────
  bool get _canGoNext {
    // Must answer current question to proceed
    return _userAnswers[_currentIndex] != null;
  }

  bool get _isLastQuestion {
    return _selectedQuestions.length == _totalQuestions &&
        _currentIndex == _totalQuestions - 1;
  }

  bool get _allAnswered {
    return _selectedQuestions.length == _totalQuestions &&
        !_userAnswers.sublist(0, _totalQuestions).contains(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4044C8)))
            : _error != null
            ? Center(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_error!, style: TextStyle(color: _textPrimary)),
        ))
            : Column(
          children: [
            _buildHeader(),
            _buildProgressSection(),
            Expanded(child: _buildQuestionArea()),
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showExitDialog,
            child: Icon(Icons.close, color: _textSecondary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quiz',
                    style: const TextStyle(
                        color: Color(0xFF4044C8),
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                Text('Module: ${widget.moduleName}',
                    style: TextStyle(color: _textSecondary, fontSize: 13)),
              ],
            ),
          ),
          // Eye toggle to show/hide difficulty UI
          GestureDetector(
            onTap: () => setState(() => _showDifficulty = !_showDifficulty),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Icon(
                _showDifficulty
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Difficulty badge (only when toggle is ON)
          if (_showDifficulty && _selectedQuestions.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _difficultyColor(_currentDifficulty).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _difficultyColor(_currentDifficulty).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_difficultyIcon(_currentDifficulty),
                      color: _difficultyColor(_currentDifficulty), size: 13),
                  const SizedBox(width: 4),
                  Text(_difficultyLabel(_currentDifficulty),
                      style: TextStyle(
                          color: _difficultyColor(_currentDifficulty),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Progress Section ───────────────────────────────────────────────────────
  Widget _buildProgressSection() {
    final int answered = _userAnswers
        .sublist(0, _selectedQuestions.length)
        .where((a) => a != null)
        .length;
    final double progress = _selectedQuestions.isEmpty
        ? 0
        : answered / _totalQuestions;

    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          Container(height: 1, color: _border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${_currentIndex + 1} of $_totalQuestions',
                  style: TextStyle(color: _textSecondary, fontSize: 13)),
              Text('$answered/$_totalQuestions answered',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar — plain when hidden, colour-coded when eye is on
          Row(
            children: List.generate(_totalQuestions, (i) {
              final bool isAnswered = i < _userAnswers.length && _userAnswers[i] != null;
              final Color dotColor = _showDifficulty && i < _difficultyHistory.length
                  ? _difficultyColor(_difficultyHistory[i])
                  : const Color(0xFF4044C8);
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 6,
                  decoration: BoxDecoration(
                    color: isAnswered ? dotColor : _border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          if (_showDifficulty) ...[
            const SizedBox(height: 6),
            // Legend (only when toggle is ON)
            Row(
              children: [
                _legendDot(const Color(0xFF10B981), 'Easy'),
                const SizedBox(width: 12),
                _legendDot(const Color(0xFFF59E0B), 'Medium'),
                const SizedBox(width: 12),
                _legendDot(const Color(0xFFEF4444), 'Hard'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: _textSecondary)),
      ],
    );
  }

  // ── Question Area ──────────────────────────────────────────────────────────
  Widget _buildQuestionArea() {
    if (_selectedQuestions.isEmpty) return const SizedBox();
    final question = _selectedQuestions[_currentIndex];
    final options = question['options'] as List<String>;
    final String qDifficulty = _difficultyHistory.length > _currentIndex
        ? _difficultyHistory[_currentIndex]
        : _currentDifficulty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showDifficulty) ...[   // Difficulty tag for this question
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _difficultyColor(qDifficulty).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_difficultyIcon(qDifficulty),
                      color: _difficultyColor(qDifficulty), size: 12),
                  const SizedBox(width: 4),
                  Text(_difficultyLabel(qDifficulty),
                      style: TextStyle(
                          color: _difficultyColor(qDifficulty),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            question['question'] as String,
            style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.4),
          ),
          const SizedBox(height: 24),
          ...options.asMap().entries.map((e) => _buildOption(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildOption(int index, String text) {
    final bool isSelected = _selectedAnswer == index;
    return GestureDetector(
      onTap: () => _selectAnswer(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4044C8).withValues(alpha: 0.08)
              : _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF4044C8) : _border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF4044C8) : _textSecondary,
                  width: 2,
                ),
                color: isSelected ? const Color(0xFF4044C8) : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: isSelected ? const Color(0xFF4044C8) : _textPrimary,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Buttons ─────────────────────────────────────────────────────────
  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _currentIndex > 0 ? _goPrevious : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                    color: _currentIndex > 0
                        ? _border
                        : _border.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Previous',
                  style: TextStyle(
                      color: _currentIndex > 0 ? _textPrimary : _textSecondary,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : (_isLastQuestion
                      ? (_allAnswered ? _finishQuiz : null)
                      : (_canGoNext ? _goNext : null)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSubmitting
                    ? const Color(0xFF10B981)
                    : (_isLastQuestion
                        ? (_allAnswered ? const Color(0xFF10B981) : Colors.grey)
                        : (_canGoNext ? const Color(0xFF4044C8) : Colors.grey)),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      _isLastQuestion ? 'Finish Quiz' : 'Next',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Global level classification — weighted formula across all modules ────────
  static Future<void> _classifyGlobalLevel(String uid, String moduleKey) async {
    try {
      final firestore = FirebaseFirestore.instance;

      final progressSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('moduleProgress')
          .get();

      if (progressSnap.docs.isEmpty) return;

      const List<String> parentKeys = [
        'introduction', 'arrays', 'linked_list', 'stack',
        'queue', 'searching', 'sorting', 'trees',
      ];

      // Build a lookup map from the fetched docs
      final Map<String, Map<String, dynamic>> docMap = {};
      for (final doc in progressSnap.docs) {
        if (parentKeys.contains(doc.id)) docMap[doc.id] = doc.data();
      }

      double scoreSum = 0;

      // Always iterate all 8 parent keys — missing docs contribute 0
      for (final key in parentKeys) {
        final d = docMap[key];
        if (d == null) continue; // contributes 0 to scoreSum
        final double highestScore = ((d['highestScore'] ?? 0.0) as num).toDouble();
        final int totalReadingSecs = ((d['totalReadingSeconds'] ?? 0) as num).toInt();
        final int totalARSecs = ((d['totalARSeconds'] ?? 0) as num).toInt();

        final double quizComponent    = (highestScore / 100.0) * 60;
        final double readingComponent = (totalReadingSecs / 720.0).clamp(0.0, 1.0) * 25;
        final double arComponent      = (totalARSecs / 600.0).clamp(0.0, 1.0) * 15;
        final double moduleScore      = quizComponent + readingComponent + arComponent;

        scoreSum += moduleScore;
      }

      // Denominator is always 8 regardless of how many docs exist
      final double averageScore = scoreSum / parentKeys.length;

      final String globalLevel;
      if (averageScore >= 70) {
        globalLevel = 'Advanced';
      } else if (averageScore >= 40) {
        globalLevel = 'Intermediate';
      } else {
        globalLevel = 'Beginner';
      }

      debugPrint('═══ GLOBAL LEVEL CLASSIFICATION ═══');
      debugPrint('Modules: ${parentKeys.length} | Avg score: ${averageScore.toStringAsFixed(1)} → $globalLevel');
      debugPrint('═══════════════════════════════════');

      await firestore.collection('users').doc(uid).set({
        'predictedLevel': globalLevel,
        'lastLevelModule': moduleKey,
        'lastLevelUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ _classifyGlobalLevel failed: $e');
    }
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Exit Quiz?',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Your progress will be lost.',
            style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
            child: const Text('Exit',
                style: TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}