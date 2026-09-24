// ============================================
// FILE: lib/screens/quiz_result_screen.dart
// Shows score, emoji, answer review key,
// and AI insights suggestion
// ============================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' show min;
import 'insights_screen.dart';
import '../services/sound_service.dart';
import '../config/secrets.dart';

class QuizResultScreen extends StatefulWidget {
  final String moduleName;
  final int score;
  final int total;
  final List<Map<String, dynamic>> questions;
  final List<int?> userAnswers;
  final bool isDarkMode;
  final String estimatedLevel;
  final String finalDifficulty;
  final List<String> difficultyHistory;
  final int easyCorrect;
  final int mediumCorrect;
  final int hardCorrect;
  final int timeTaken;
  final List<Map<String, dynamic>> wrongQuestions;
  final List<Map<String, dynamic>> newBadges;
  final bool streakIncreased;
  final int newStreak;
  final Future<({int oldStreak, int newStreak, List<Map<String, dynamic>> newBadges})>? saveFuture;

  const QuizResultScreen({
    super.key,
    required this.moduleName,
    required this.score,
    required this.total,
    required this.questions,
    required this.userAnswers,
    this.isDarkMode = false,
    this.estimatedLevel = 'Intermediate',
    this.finalDifficulty = 'medium',
    this.difficultyHistory = const [],
    this.easyCorrect = 0,
    this.mediumCorrect = 0,
    this.hardCorrect = 0,
    this.timeTaken = 0,
    this.wrongQuestions = const [],
    this.newBadges = const [],
    this.streakIncreased = false,
    this.newStreak = 0,
    this.saveFuture,
  });

  @override
  QuizResultScreenState createState() => QuizResultScreenState();
}

class QuizResultScreenState extends State<QuizResultScreen> {
  bool _showAnswerKey = false;
  String? _aiFeedback;
  bool _isLoadingFeedback = false;
  bool _feedbackLoaded = false;

  // ── Theme helpers ─────────────────────────────────────────────────────────
  bool get dark => widget.isDarkMode;
  Color get _bg            => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card          => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary   => dark ? Colors.white            : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _border        => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);

  double get _percentage => (widget.score / widget.total) * 100;

  // ── Score level helpers ───────────────────────────────────────────────────
  String get _emoji {
    if (_percentage >= 80) return '😊';
    if (_percentage >= 50) return '😐';
    return '😞';
  }

  Color get _emojiColor {
    if (_percentage >= 80) return const Color(0xFF10B981);
    if (_percentage >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String get _scoreLabel {
    if (_percentage >= 80) return 'Excellent work!';
    if (_percentage >= 50) return 'Good Work';
    return 'Unsatisfied';
  }

  String get _insightMessage {
    if (_percentage >= 80) {
      return 'Amazing performance! You have a strong understanding of ${widget.moduleName}. You are ready to move to the next module!';
    } else if (_percentage >= 50) {
      return 'Good effort! You understand the basics of ${widget.moduleName} but there are some gaps. Review the sections you got wrong and retake the quiz to solidify your knowledge.';
    } else {
      return 'You need more practice with ${widget.moduleName}. We recommend revisiting the module content, especially the sections on operations and working mechanisms, before attempting the quiz again.';
    }
  }

  String get _insightAction {
    if (_percentage >= 80) return '✅ Move to next module';
    if (_percentage >= 50) return '🔁 Review weak areas and retake';
    return '📖 Revisit module content first';
  }

  @override
  void initState() {
    super.initState();
    if (widget.wrongQuestions.isNotEmpty) {
      _loadAIFeedback();
    }

    // When save completes in the background, trigger streak + badge celebrations
    widget.saveFuture?.then((result) {
      if (!mounted) return;
      final streakIncreased = result.newStreak > result.oldStreak;

      if (streakIncreased) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _showStreakCelebration(result.newStreak);
        });
      }

      if (result.newBadges.isNotEmpty) {
        final delay = streakIncreased
            ? const Duration(milliseconds: 5600)
            : const Duration(milliseconds: 800);
        Future.delayed(delay, () {
          if (mounted) _showBadgePopup(result.newBadges);
        });
      }
    });
  }

  // ── Streak celebration overlay ─────────────────────────────────────────────
  void _showStreakCelebration(int newStreak) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'streak',
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => _StreakCelebrationDialog(
        newStreak: newStreak,
      ),
    );
  }

  // ── Badge celebration popup ───────────────────────────────────────────────
  void _showBadgePopup(List<Map<String, dynamic>> badges) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: _BadgeCelebrationSheet(
          badges: badges,
          isDarkMode: widget.isDarkMode,
        ),
      ),
    );
  }

  Future<void> _loadAIFeedback() async {
    if (_feedbackLoaded || widget.wrongQuestions.isEmpty) return;
    setState(() => _isLoadingFeedback = true);

    try {
      final wrongList = widget.wrongQuestions.take(5).map((q) =>
      '- ${q['question']} (Correct: ${q['correctAnswer']}, Difficulty: ${q['difficulty']})'
      ).join('\n');

      final prompt =
'Student scored ${widget.score}/${widget.total} on ${widget.moduleName}. '
'Level: ${widget.estimatedLevel}.\n\n'
'Wrong questions:\n$wrongList\n\n'
'Write exactly 3 short sentences as plain text:\n'
'1. What concept the student struggled with most.\n'
'2. One specific thing they should review or practice.\n'
'3. One encouraging sentence to motivate them.\n\n'
'Rules: Plain text only. No bullet points. No asterisks. No headers. '
'No numbering. Just 3 flowing sentences separated by spaces. '
'Each sentence must be fully complete with a period. '
'Always write in second person, addressing the student directly '
'as \'you\' and \'your\'. Never say \'the student\'. Start with \'You\'.';

      const String geminiKey = Secrets.geminiApiKey;
      const String geminiUrl =
                'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

      final response = await http.post(
        Uri.parse('$geminiUrl?key=$geminiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.3,
            'maxOutputTokens': 2048,
            'thinkingConfig': {'thinkingBudget': 0},
          },
        }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('Feedback API status: ${response.statusCode}');
      debugPrint('Feedback raw: ${response.body.substring(0, min(200, response.body.length))}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['candidates'][0]['content']['parts'][0]['text'] as String;

        setState(() {
          _aiFeedback = raw.trim();
          _feedbackLoaded = true;
          _isLoadingFeedback = false;
        });
      } else {
        setState(() => _isLoadingFeedback = false);
      }
    } catch (e) {
      debugPrint('AI feedback error: $e');
      setState(() {
        _aiFeedback = 'Could not load feedback right now. Try retaking the quiz for fresh feedback.';
        _feedbackLoaded = true;
        _isLoadingFeedback = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              _buildResultCard(),
              const SizedBox(height: 20),
              _buildAdaptiveCard(),
              const SizedBox(height: 20),
              _buildFeedbackCard(),
              const SizedBox(height: 20),
              if (_showAnswerKey) _buildAnswerKey(),
              const SizedBox(height: 24),
              _buildBottomButtons(), // ← moved INSIDE scroll
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
  // ── Result Card ───────────────────────────────────────────────────────────
  Widget _buildResultCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Text('Quiz Results',
              style: TextStyle(
                  color: const Color(0xFF4044C8),
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),

          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _emojiColor, width: 3),
            ),
            child: Center(
              child: Text(_emoji, style: const TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            '${widget.score.toString().padLeft(2, '0')}/${widget.total.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: _textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(_scoreLabel,
              style: TextStyle(color: _textSecondary, fontSize: 14)),
          const SizedBox(height: 24),

          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Your Score',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _percentage / 100,
                  backgroundColor: _border,
                  valueColor: AlwaysStoppedAnimation<Color>(_emojiColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text('${_percentage.toInt()}%',
                  style: TextStyle(color: _textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: _border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Retake',
                      style: TextStyle(
                          color: _textPrimary, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4044C8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Continue',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Merged Personalized Feedback Card ────────────────────────────────────
// ── Merged Personalized Feedback Card ────────────────────────────────────
  Widget _buildFeedbackCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4044C8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.psychology_rounded,
                      color: Color(0xFF4044C8), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Feedback',
                          style: TextStyle(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text('Based on your performance',
                          style: TextStyle(fontSize: 11, color: _textSecondary)),
                    ],
                  ),
                ),
                if (!_isLoadingFeedback &&
                    _aiFeedback == null &&
                    widget.wrongQuestions.isNotEmpty)
                  GestureDetector(
                    onTap: _loadAIFeedback,
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4044C8).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Retry',
                          style: TextStyle(
                              color: Color(0xFF4044C8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Feedback body ──
            if (widget.wrongQuestions.isNotEmpty) ...[
              if (_isLoadingFeedback)
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF4044C8)),
                    ),
                    const SizedBox(width: 12),
                    Text('Analyzing your answers...',
                        style: TextStyle(color: _textSecondary, fontSize: 13)),
                  ],
                )
              else if (_aiFeedback != null)
                Text(
                  _aiFeedback!,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                      color: _textSecondary, fontSize: 13, height: 1.6),
                )
              else
                Text(
                  _insightMessage,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                      color: _textSecondary, fontSize: 14, height: 1.5),
                ),
            ] else if (_percentage >= 100)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Perfect Score!',
                            style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You have a strong command of this topic. Keep it up!',
                            style: TextStyle(
                                color: _textSecondary,
                                fontSize: 13,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                _insightMessage,
                softWrap: true,
                overflow: TextOverflow.visible,
                style:
                TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
              ),

            const SizedBox(height: 12),

            // ── Action chip ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _emojiColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_insightAction,
                  style: TextStyle(
                      color: _emojiColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 16),

            // ── Answer key toggle ──
            GestureDetector(
              onTap: () => setState(() => _showAnswerKey = !_showAnswerKey),
              child: Row(
                children: [
                  Icon(
                    _showAnswerKey
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF4044C8),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showAnswerKey ? 'Hide Answer Key' : 'View Answer Key',
                    style: const TextStyle(
                        color: Color(0xFF4044C8),
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// ── Answer Key ────────────────────────────────────────────────────────────
  // ── Answer Key ────────────────────────────────────────────────────────────
  Widget _buildAnswerKey() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Answer Review',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...widget.questions.asMap().entries.map((e) {
            final int i = e.key;
            final q = e.value;
            final options = q['options'] as List<String>;
            final int correct = q['correct'] as int;
            final int? userAnswer = widget.userAnswers[i];
            final bool isCorrect = userAnswer == correct;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isCorrect
                    ? const Color(0xFF10B981).withValues(alpha: 0.06)
                    : const Color(0xFFEF4444).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCorrect
                      ? const Color(0xFF10B981).withValues(alpha: 0.3)
                      : const Color(0xFFEF4444).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        color: isCorrect
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Q${i + 1}: ${q['question']}',
                            style: TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      Text('Correct: ',
                          style: TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Expanded(
                        child: Text(options[correct],
                            style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (!isCorrect && userAnswer != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.cancel_outlined,
                            color: Color(0xFFEF4444), size: 16),
                        const SizedBox(width: 6),
                        Text('Your answer: ',
                            style: TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(options[userAnswer],
                              style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── View AI Insights gradient button ──────────────────────────────────────
  Widget _buildBottomButtons() {
    return Padding(                              // ← was Container with color
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Center(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InsightsScreen(
                    moduleName: widget.moduleName,
                    score: widget.score,
                    total: widget.total,
                    questions: widget.questions,
                    userAnswers: widget.userAnswers,
                    isDarkMode: widget.isDarkMode,
                  ),
                ),
              );
            },
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF38D9C0),
                    Color(0xFFB8A83A),
                    Color(0xFFE8904A)
                  ],
                  stops: [0.0, 0.55, 1.0],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Padding(
                padding:
                EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insights_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('Insights',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Adaptive Performance Card ─────────────────────────────────────────────
  Widget _buildAdaptiveCard() {
    final Color levelColor = widget.estimatedLevel == 'Advanced'
        ? const Color(0xFFEF4444)
        : widget.estimatedLevel == 'Intermediate'
        ? const Color(0xFFF59E0B)
        : const Color(0xFF10B981);

    final IconData levelIcon = widget.estimatedLevel == 'Advanced'
        ? Icons.local_fire_department_rounded
        : widget.estimatedLevel == 'Intermediate'
        ? Icons.trending_up_rounded
        : Icons.emoji_nature_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4044C8).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF4044C8), size: 18),
              ),
              const SizedBox(width: 10),
              Text('Performance Analysis',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                Border.all(color: levelColor.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(levelIcon, color: levelColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estimated Level',
                            style: TextStyle(
                                fontSize: 12, color: _textSecondary)),
                        Text(widget.estimatedLevel,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: levelColor)),
                      ],
                    )),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: _buildDiffStat(
                      'Easy', widget.easyCorrect, const Color(0xFF10B981))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildDiffStat('Medium', widget.mediumCorrect,
                      const Color(0xFFF59E0B))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildDiffStat(
                      'Hard', widget.hardCorrect, const Color(0xFFEF4444))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffStat(String label, int correct, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Icon(
            label == 'Easy'
                ? Icons.emoji_nature_outlined
                : label == 'Medium'
                ? Icons.trending_up_rounded
                : Icons.local_fire_department_outlined,
            color: color,
            size: 16),
        const SizedBox(height: 4),
        Text('$correct',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(fontSize: 10, color: _textSecondary)),
      ]),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
// BADGE CELEBRATION BOTTOM SHEET — fixed overflow + confetti animation
// ══════════════════════════════════════════════════════════════════════════════
class _BadgeCelebrationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> badges;
  final bool isDarkMode;

  const _BadgeCelebrationSheet({
    required this.badges,
    required this.isDarkMode,
  });

  @override
  State<_BadgeCelebrationSheet> createState() => _BadgeCelebrationSheetState();
}

class _BadgeCelebrationSheetState extends State<_BadgeCelebrationSheet>
    with TickerProviderStateMixin {

  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;
  late AnimationController _confettiController;
  int _currentBadgeIndex = 0;

  bool get dark => widget.isDarkMode;
  Color get _card => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary => dark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut);
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scaleController.forward();
    _confettiController.forward();
    // Sound + haptic for badge unlock
    SoundService.instance.playBadge();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 250),
        () => HapticFeedback.mediumImpact());
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _nextBadge() {
    if (_currentBadgeIndex < widget.badges.length - 1) {
      _scaleController.reset();
      _confettiController.reset();
      setState(() => _currentBadgeIndex++);
      _scaleController.forward();
      _confettiController.forward();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badges[_currentBadgeIndex];
    final Color color = badge['color'] as Color;
    final IconData icon = badge['icon'] as IconData;
    final bool hasMore = _currentBadgeIndex < widget.badges.length - 1;
    final double screenH = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.72),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Confetti particles
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (_, __) => CustomPaint(
                painter: _ConfettiPainter(
                  progress: _confettiController.value,
                  color: color,
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open_rounded, color: color, size: 14),
                      const SizedBox(width: 6),
                      Text('Achievement Unlocked! 🎉',
                          style: TextStyle(color: color, fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12),
                      border: Border.all(color: color.withValues(alpha: 0.4), width: 3),
                      boxShadow: [
                        BoxShadow(color: color.withValues(alpha: 0.4),
                            blurRadius: 24, spreadRadius: 4),
                      ],
                    ),
                    child: Icon(icon, color: color, size: 46),
                  ),
                ),
                const SizedBox(height: 14),
                Text(badge['title'] as String,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: _textPrimary)),
                const SizedBox(height: 6),
                Text(badge['desc'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.4)),
                if (widget.badges.length > 1) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.badges.length, (i) =>
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: i == _currentBadgeIndex ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == _currentBadgeIndex
                                ? color : Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _nextBadge,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text(
                      hasMore ? 'Next Badge →' : '🎉 Awesome!',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confetti painter ──────────────────────────────────────────────────────────
class _ConfettiPainter extends CustomPainter {
  final double progress;
  final Color color;
  _ConfettiPainter({required this.progress, required this.color});

  static final List<Map<String, dynamic>> _particles = List.generate(28, (i) {
    final r1 = (i * 7919 + 13) % 100 / 100.0;
    final r2 = (i * 6271 + 7) % 100 / 100.0;
    final r3 = (i * 3457 + 17) % 100 / 100.0;
    return {'x': r1, 'speed': 0.4 + r2 * 0.6, 'size': 4.0 + r3 * 6,
      'angle': r2 * 6.28, 'ci': i % 5};
  });

  static const List<Color> _colors = [
    Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFFEC4899),
    Color(0xFF4044C8), Color(0xFFEF4444),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    for (final p in _particles) {
      final x = (p['x'] as double) * size.width;
      final y = size.height * (1 - progress * (p['speed'] as double) * 1.2);
      if (y < 0 || y > size.height) continue;
      final paint = Paint()
        ..color = _colors[p['ci'] as int]
            .withValues(alpha: (1 - progress * 0.8).clamp(0.0, 1.0));
      final sz = (p['size'] as double) * (1 - progress * 0.3);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((p['angle'] as double) + progress * 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: sz, height: sz * 0.5),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

// ══════════════════════════════════════════════════════════════════════════════
// STREAK CELEBRATION DIALOG — Duolingo-style bounce-in overlay
// ══════════════════════════════════════════════════════════════════════════════
class _StreakCelebrationDialog extends StatefulWidget {
  final int newStreak;
  const _StreakCelebrationDialog({required this.newStreak});

  @override
  State<_StreakCelebrationDialog> createState() =>
      _StreakCelebrationDialogState();
}

class _StreakCelebrationDialogState extends State<_StreakCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();

    // Sound + haptic for the celebration
    SoundService.instance.playStreak();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200),
        () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 450),
        () => HapticFeedback.mediumImpact());

    // Auto-dismiss after 5 seconds (user can tap anywhere to skip sooner)
    Future.delayed(const Duration(milliseconds: 5000), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 36),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.55),
                      blurRadius: 36,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.newStreak == 1 ? '🎉' : '🔥',
                      style: const TextStyle(fontSize: 72, height: 1),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.newStreak == 1
                          ? 'First Streak!'
                          : '${widget.newStreak} Day Streak!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.newStreak == 1
                          ? "Amazing start! Don't stop now — keep it going! 💪"
                          : "You're on fire! Keep it up! 💪",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Tap anywhere to continue',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}