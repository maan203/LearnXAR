// ============================================
// FILE: lib/screens/insights_screen.dart
// Shows performance analysis after quiz
// Weak areas, strong areas, recommendations
// ============================================
import 'package:flutter/material.dart';

class InsightsScreen extends StatelessWidget {
  final String moduleName;
  final int score;
  final int total;
  final List<Map<String, dynamic>> questions;
  final List<int?> userAnswers;
  final bool isDarkMode;

  const InsightsScreen({
    super.key,
    required this.moduleName,
    required this.score,
    required this.total,
    required this.questions,
    required this.userAnswers,
    this.isDarkMode = false,
  });

  // ── Theme helpers ─────────────────────────────────────────────────────────
  bool get dark => isDarkMode;
  Color get _bg           => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card         => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary  => dark ? Colors.white            : const Color(0xFF111827);
  Color get _textSecondary=> dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _border       => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);

  double get _percentage => (score / total) * 100;

  // ── Analyze wrong answers to find weak areas ──────────────────────────────
  List<Map<String, dynamic>> get _wrongQuestions {
    List<Map<String, dynamic>> wrong = [];
    for (int i = 0; i < questions.length; i++) {
      if (userAnswers[i] != questions[i]['correct']) {
        wrong.add({
          'question': questions[i]['question'],
          'correct': (questions[i]['options'] as List<String>)[questions[i]['correct'] as int],
          'yourAnswer': userAnswers[i] != null
              ? (questions[i]['options'] as List<String>)[userAnswers[i]!]
              : 'Not answered',
        });
      }
    }
    return wrong;
  }

  List<Map<String, dynamic>> get _correctQuestions {
    List<Map<String, dynamic>> correct = [];
    for (int i = 0; i < questions.length; i++) {
      if (userAnswers[i] == questions[i]['correct']) {
        correct.add({'question': questions[i]['question']});
      }
    }
    return correct;
  }

  // ── Performance level ─────────────────────────────────────────────────────
  String get _level {
    if (_percentage >= 80) return 'Excellent';
    if (_percentage >= 50) return 'Average';
    return 'Needs Work';
  }

  Color get _levelColor {
    if (_percentage >= 80) return const Color(0xFF10B981);
    if (_percentage >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String get _overallMessage {
    if (_percentage >= 80) {
      return 'You have a strong understanding of $moduleName. Your performance shows you\'ve grasped the key concepts and are ready to move forward!';
    } else if (_percentage >= 50) {
      return 'You have a basic understanding of $moduleName but there are some areas that need attention. Review the topics below and try again.';
    } else {
      return 'You need more practice with $moduleName. Don\'t worry — go back to the module content, focus on the weak areas listed below, and retake the quiz.';
    }
  }

  String get _recommendation {
    if (_percentage >= 80) return 'Move on to the next module!';
    if (_percentage >= 50) return 'Review weak areas then retake quiz';
    return 'Revisit full module content first';
  }

  IconData get _recommendationIcon {
    if (_percentage >= 80) return Icons.arrow_forward_rounded;
    if (_percentage >= 50) return Icons.refresh_rounded;
    return Icons.menu_book_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Insights',
            style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverallCard(),
            const SizedBox(height: 16),
            _buildScoreBreakdown(),
            const SizedBox(height: 16),
            _buildRecommendationCard(),
            const SizedBox(height: 16),
            if (_wrongQuestions.isNotEmpty) ...[
              _buildWeakAreasCard(),
              const SizedBox(height: 16),
            ],
            if (_correctQuestions.isNotEmpty) ...[
              _buildStrongAreasCard(),
              const SizedBox(height: 16),
            ],
            _buildNextStepsCard(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Overall Performance Card ──────────────────────────────────────────────
  Widget _buildOverallCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _levelColor.withValues(alpha: 0.15),
            _levelColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _levelColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _levelColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: _levelColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$moduleName Quiz Insights',
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _levelColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_level,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_overallMessage,
              style: TextStyle(
                  color: _textSecondary, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  // ── Score Breakdown ───────────────────────────────────────────────────────
  Widget _buildScoreBreakdown() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Score Breakdown',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  label: 'Correct',
                  value: '${_correctQuestions.length}',
                  color: const Color(0xFF10B981),
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  label: 'Wrong',
                  value: '${_wrongQuestions.length}',
                  color: const Color(0xFFEF4444),
                  icon: Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  label: 'Score',
                  value: '${_percentage.toInt()}%',
                  color: _levelColor,
                  icon: Icons.bar_chart_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _percentage / 100,
              backgroundColor: _border,
              valueColor: AlwaysStoppedAnimation<Color>(_levelColor),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: _textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Recommendation Card ───────────────────────────────────────────────────
  Widget _buildRecommendationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4044C8).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF4044C8).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4044C8).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_recommendationIcon,
                color: const Color(0xFF4044C8), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recommendation',
                    style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(_recommendation,
                    style: const TextStyle(
                        color: Color(0xFF4044C8),
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Weak Areas Card ───────────────────────────────────────────────────────
  Widget _buildWeakAreasCard() {
    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444), size: 18),
              ),
              const SizedBox(width: 10),
              Text('Needs Improvement',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_wrongQuestions.length} questions',
                    style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('You got these wrong — review and understand them:',
              style: TextStyle(color: _textSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          ..._wrongQuestions.asMap().entries.map((e) {
            final i = e.key;
            final q = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}. ${q['question']}',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Correct: ${q['correct']}',
                            style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cancel,
                          color: Color(0xFFEF4444), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Your answer: ${q['yourAnswer']}',
                            style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Strong Areas Card ─────────────────────────────────────────────────────
  Widget _buildStrongAreasCard() {
    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_rounded,
                    color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              Text('You Got These Right',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_correctQuestions.length} questions',
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Great job on these — keep it up!',
              style: TextStyle(color: _textSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          ..._correctQuestions.asMap().entries.map((e) {
            final i = e.key;
            final q = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${i + 1}. ${q['question']}',
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Next Steps Card ───────────────────────────────────────────────────────
  Widget _buildNextStepsCard(BuildContext context) {
    final List<Map<String, dynamic>> steps = _percentage >= 80
        ? [
            {'icon': Icons.check_circle, 'color': const Color(0xFF10B981), 'text': 'You passed $moduleName with a great score'},
            {'icon': Icons.arrow_forward_rounded, 'color': const Color(0xFF4044C8), 'text': 'Proceed to the next module in Learn'},
            {'icon': Icons.emoji_events_rounded, 'color': const Color(0xFFF59E0B), 'text': 'Keep building your DSA streak!'},
          ]
        : _percentage >= 50
        ? [
            {'icon': Icons.refresh_rounded, 'color': const Color(0xFFF59E0B), 'text': 'Review the "Needs Improvement" questions above'},
            {'icon': Icons.menu_book_rounded, 'color': const Color(0xFF4044C8), 'text': 'Re-read the $moduleName module content'},
            {'icon': Icons.quiz_rounded, 'color': const Color(0xFF10B981), 'text': 'Retake the quiz to improve your score'},
          ]
        : [
            {'icon': Icons.menu_book_rounded, 'color': const Color(0xFFEF4444), 'text': 'Go back and fully re-read $moduleName content'},
            {'icon': Icons.warning_amber_rounded, 'color': const Color(0xFFF59E0B), 'text': 'Focus on the ${_wrongQuestions.length} questions you got wrong'},
            {'icon': Icons.quiz_rounded, 'color': const Color(0xFF4044C8), 'text': 'Retake the quiz after thorough revision'},
          ];

    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4044C8).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.route_rounded,
                    color: Color(0xFF4044C8), size: 18),
              ),
              const SizedBox(width: 10),
              Text('Next Steps',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(step['icon'] as IconData,
                        color: step['color'] as Color, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(step['text'] as String,
                          style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              height: 1.4)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4044C8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Back to Learn',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
