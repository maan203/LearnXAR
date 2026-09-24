// ============================================
// FILE: lib/services/achievement_service.dart
// Checks badge conditions and unlocks new ones
// Called after quiz, AR, and reading sessions
// ============================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AchievementService {

  // ── All badge definitions ─────────────────────────────────────────────────
  static const List<Map<String, dynamic>> allBadges = [
    {
      'id': 'first_quiz',
      'title': 'First Step',
      'desc': 'Completed your first quiz',
      'icon': Icons.flag_rounded,
      'color': Color(0xFF4044C8),
    },
    {
      'id': 'perfect_score',
      'title': 'Perfectionist',
      'desc': 'Scored 100% on any quiz',
      'icon': Icons.emoji_events_rounded,
      'color': Color(0xFFF59E0B),
    },
    {
      'id': 'speed_master',
      'title': 'Speed Master',
      'desc': 'Scored 80%+ in under 60 seconds',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFF8B5CF6),
    },
    {
      'id': 'never_give_up',
      'title': 'Never Give Up',
      'desc': 'Retried a quiz 3+ times and improved each time',
      'icon': Icons.fitness_center_rounded,
      'color': Color(0xFFEF4444),
    },
    {
      'id': 'on_fire',
      'title': 'On Fire',
      'desc': 'Maintained a 5-day study streak',
      'icon': Icons.local_fire_department_rounded,
      'color': Color(0xFFFF6B35),
    },
    {
      'id': 'deep_reader',
      'title': 'Deep Reader',
      'desc': 'Spent 60+ minutes reading module content',
      'icon': Icons.menu_book_rounded,
      'color': Color(0xFF10B981),
    },
    {
      'id': 'ar_enthusiast',
      'title': 'AR Enthusiast',
      'desc': 'Used AR on 5 or more different modules',
      'icon': Icons.view_in_ar_rounded,
      'color': Color(0xFF06B6D4),
    },
    {
      'id': 'dsa_champion',
      'title': 'DSA Champion',
      'desc': 'Completed all 8 modules at 70%+ progress',
      'icon': Icons.workspace_premium_rounded,
      'color': Color(0xFFEC4899),
    },
  ];

  static const List<String> _allModuleKeys = [
    'introduction', 'arrays', 'linked_list', 'stack',
    'queue', 'searching', 'sorting', 'trees',
  ];

  // ── Check all badges and return newly unlocked ones ───────────────────────
  static Future<List<Map<String, dynamic>>> checkAndUnlock({
    required String uid,
    required FirebaseFirestore firestore,
    double? quizScore,
    int? quizTimeSecs,
    int? attemptNumber,
    double? previousHighestScore,
    String? moduleKey,
  }) async {
    try {
      final userDoc = await firestore.collection('users').doc(uid).get();
      final List<String> earned = userDoc.exists
          ? List<String>.from(userDoc.data()?['achievements'] ?? [])
          : [];

      final progressSnap = await firestore
          .collection('users').doc(uid).collection('moduleProgress').get();
      final Map<String, Map<String, dynamic>> progressMap = {};
      for (final doc in progressSnap.docs) {
        progressMap[doc.id] = doc.data();
      }

      final attemptsSnap = await firestore
          .collection('users').doc(uid).collection('quizAttempts').get();
      final int totalAttempts = attemptsSnap.docs.length;
      final int streak = (userDoc.data()?['streak'] ?? 0) as int;

      int totalReadingSecs = 0;
      Set<String> arModules = {};
      for (final entry in progressMap.entries) {
        totalReadingSecs += ((entry.value['totalReadingSeconds'] ?? 0) as num).toInt();
        if (((entry.value['totalARSeconds'] ?? 0) as num).toInt() >= 120) {
          arModules.add(entry.key);
        }
      }

      final List<String> newlyUnlocked = [];

      for (final badge in allBadges) {
        final String id = badge['id'] as String;
        if (earned.contains(id)) continue;

        bool unlocked = false;

        switch (id) {
          case 'first_quiz':
            unlocked = totalAttempts >= 1;
            break;

          case 'perfect_score':
            if (quizScore != null) {
              unlocked = quizScore >= 100.0;
            } else {
              for (final doc in attemptsSnap.docs) {
                if (((doc.data()['percentage'] ?? 0) as num) >= 100) {
                  unlocked = true; break;
                }
              }
            }
            break;

          case 'speed_master':
            if (quizScore != null && quizTimeSecs != null) {
              unlocked = quizScore >= 80.0 && quizTimeSecs < 60;
            } else {
              for (final doc in attemptsSnap.docs) {
                final pct = ((doc.data()['percentage'] ?? 0) as num).toDouble();
                final t = ((doc.data()['timeTaken'] ?? 999) as num).toInt();
                if (pct >= 80 && t < 60) { unlocked = true; break; }
              }
            }
            break;

          case 'never_give_up':
            if (moduleKey != null) {
              final attempts = attemptsSnap.docs
                  .where((d) => d.data()['moduleKey'] == moduleKey)
                  .toList();
              if (attempts.length >= 3) {
                attempts.sort((a, b) =>
                    ((a.data()['attemptNumber'] ?? 0) as num)
                        .compareTo((b.data()['attemptNumber'] ?? 0) as num));
                bool improving = true;
                for (int i = 1; i < attempts.length; i++) {
                  final prev = ((attempts[i-1].data()['percentage'] ?? 0) as num).toDouble();
                  final curr = ((attempts[i].data()['percentage'] ?? 0) as num).toDouble();
                  if (curr <= prev) { improving = false; break; }
                }
                unlocked = improving;
              }
            }
            break;

          case 'on_fire':
            unlocked = streak >= 5;
            break;

          case 'deep_reader':
            unlocked = totalReadingSecs >= 3600;
            break;

          case 'ar_enthusiast':
            unlocked = arModules.length >= 5;
            break;

          case 'dsa_champion':
            int completedCount = 0;
            for (final key in _allModuleKeys) {
              final data = progressMap[key];
              if (data != null) {
                final double hs = ((data['highestScore'] ?? 0.0) as num).toDouble();
                final int rs = ((data['totalReadingSeconds'] ?? 0) as num).toInt();
                final int ar = ((data['totalARSeconds'] ?? 0) as num).toInt();
                final double progress = ((hs / 100.0) * 60.0) +
                    ((rs / 720.0).clamp(0.0, 1.0) * 25.0) +
                    ((ar / 600.0).clamp(0.0, 1.0) * 15.0);
                if (progress >= 70) completedCount++;
              }
            }
            unlocked = completedCount >= 8;
            break;
        }

        if (unlocked) newlyUnlocked.add(id);
      }

      if (newlyUnlocked.isNotEmpty) {
        await firestore.collection('users').doc(uid).update({
          'achievements': FieldValue.arrayUnion(newlyUnlocked),
        });
        debugPrint('🏆 New badges unlocked: $newlyUnlocked');
      }

      return allBadges.where((b) => newlyUnlocked.contains(b['id'])).toList();

    } catch (e) {
      debugPrint('Achievement check error: $e');
      return [];
    }
  }

  static Map<String, dynamic>? getBadgeById(String id) {
    try {
      return allBadges.firstWhere((b) => b['id'] == id);
    } catch (_) {
      return null;
    }
  }
}
