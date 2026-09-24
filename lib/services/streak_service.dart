// ============================================
// FILE: lib/services/streak_service.dart
//
// Single source of truth for streak logic.
//
// Streak counts toward today if either:
//   (a) user completes a quiz, OR
//   (b) user spends ≥ 5 min reading content AND ≥ 5 min in the app
//
// AR does NOT count toward the study requirement (only achievements).
//
// On app launch, checkOnLaunch() resets the streak to 0 if the user
// skipped yesterday (gap of 2+ days since lastStudyDate).
//
// All daily counters live in shared_preferences (cheap) and reset
// automatically at midnight via the date-key check.
// ============================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class StreakService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Tunables
  static const int _appTimeRequiredSeconds = 300;     // 5 min in app
  static const int _readingRequiredSeconds = 300;     // 5 min reading

  // SharedPreferences keys
  static const String _kDailyDate = 'streak_daily_date';        // yyyy-MM-dd
  static const String _kDailyAppSecs = 'streak_daily_app_secs';
  static const String _kDailyReadSecs = 'streak_daily_read_secs';
  static const String _kStreakTriggeredToday = 'streak_triggered_today';
  static const String _kAppSessionStart = 'streak_app_session_start';

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Ensure the daily counters belong to today. If a new day has rolled over,
  /// reset all daily counters to zero.
  static Future<SharedPreferences> _ensureToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final stored = prefs.getString(_kDailyDate);
    if (stored != today) {
      await prefs.setString(_kDailyDate, today);
      await prefs.setInt(_kDailyAppSecs, 0);
      await prefs.setInt(_kDailyReadSecs, 0);
      await prefs.setBool(_kStreakTriggeredToday, false);
      // session start is reset by trackAppSessionStart below
    }
    return prefs;
  }

  // ─── Called on app launch / home screen load ───────────────────────────────

  /// Verifies the stored streak against today's date.
  /// If the user missed yesterday (last study was 2+ days ago), the streak
  /// is reset to 0 in Firestore. Idempotent — safe to call repeatedly.
  /// Returns the previous streak count if it was broken, 0 otherwise.
  static Future<int> checkOnLaunch(String uid) async {
    try {
      await _ensureToday();
      final userRef = _firestore.collection('users').doc(uid);
      final snap = await userRef.get();
      if (!snap.exists) return 0;

      final data = snap.data() ?? {};
      final int currentStreak = (data['streak'] ?? 0) as int;
      final lastStudyTs = data['lastStudyDate'] as Timestamp?;

      if (currentStreak <= 0) return 0; // nothing to break
      if (lastStudyTs == null) return 0;

      final lastStudy = lastStudyTs.toDate();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastDay = DateTime(lastStudy.year, lastStudy.month, lastStudy.day);
      final diffDays = today.difference(lastDay).inDays;

      if (diffDays >= 2) {
        await userRef.update({'streak': 0});
        debugPrint('🔥 Streak broken on launch: $diffDays day gap, reset to 0');
        return currentStreak; // return how many days were lost
      }
      return 0;
    } catch (e) {
      debugPrint('StreakService.checkOnLaunch error: $e');
      return 0;
    }
  }

  // ─── App session tracking (in-app time) ────────────────────────────────────

  /// Call once when home screen mounts (or app foregrounds).
  static Future<void> trackAppSessionStart() async {
    final prefs = await _ensureToday();
    await prefs.setInt(
      _kAppSessionStart,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Call when app backgrounds or user leaves a foreground-relevant screen.
  /// Adds elapsed seconds since trackAppSessionStart() to today's app total.
  static Future<void> trackAppSessionEnd(String uid) async {
    final prefs = await _ensureToday();
    final startMs = prefs.getInt(_kAppSessionStart) ?? 0;
    if (startMs == 0) return;

    final elapsed = (DateTime.now().millisecondsSinceEpoch - startMs) ~/ 1000;
    if (elapsed <= 0) return;

    final currentApp = prefs.getInt(_kDailyAppSecs) ?? 0;
    final newApp = currentApp + elapsed;
    await prefs.setInt(_kDailyAppSecs, newApp);
    await prefs.setInt(_kAppSessionStart, 0);

    // Re-evaluate whether today now qualifies
    await _maybeTriggerStreak(uid);
  }

  // ─── Reading time tracking ─────────────────────────────────────────────────

  /// Called from module_detail_screen when a reading session ends.
  /// Adds the session's seconds to today's reading total and may trigger
  /// the streak event if the combined threshold is now met.
  static Future<void> recordReadingTime({
    required String uid,
    required int seconds,
  }) async {
    if (seconds <= 0) return;
    final prefs = await _ensureToday();
    final current = prefs.getInt(_kDailyReadSecs) ?? 0;
    final next = current + seconds;
    await prefs.setInt(_kDailyReadSecs, next);
    await _maybeTriggerStreak(uid);
  }

  // ─── Quiz completion (instant trigger) ─────────────────────────────────────

  /// Called from quiz_screen when a full quiz is submitted.
  /// Always triggers the streak event (quiz alone is enough).
  /// Returns (oldStreak, newStreak) so the caller can animate a streak increase.
  static Future<({int oldStreak, int newStreak})> recordQuizCompleted(
      String uid) async {
    await _ensureToday();
    return await _triggerStreakEvent(uid, reason: 'quiz');
  }

  // ─── Internal: evaluate reading+app combined threshold ─────────────────────

  static Future<void> _maybeTriggerStreak(String uid) async {
    final prefs = await _ensureToday();
    final triggered = prefs.getBool(_kStreakTriggeredToday) ?? false;
    if (triggered) return;

    final readSecs = prefs.getInt(_kDailyReadSecs) ?? 0;
    final appSecs = prefs.getInt(_kDailyAppSecs) ?? 0;

    if (readSecs >= _readingRequiredSeconds &&
        appSecs >= _appTimeRequiredSeconds) {
      await _triggerStreakEvent(uid, reason: 'reading+app');
    }
  }

  // ─── Internal: actually increment/reset the streak in Firestore ────────────
  // Returns (oldStreak, newStreak). Both are 0 when already triggered today.

  static Future<({int oldStreak, int newStreak})> _triggerStreakEvent(
      String uid, {
        required String reason,
      }) async {
    try {
      final prefs = await _ensureToday();
      final userRef = _firestore.collection('users').doc(uid);

      // Already triggered today — return real streak so callers see correct value
      if (prefs.getBool(_kStreakTriggeredToday) ?? false) {
        final snap = await userRef.get();
        final streak = ((snap.data() ?? {})['streak'] ?? 0) as int;
        debugPrint('🔥 Streak already triggered today, current: $streak');
        return (oldStreak: streak, newStreak: streak);
      }
      final snap = await userRef.get();
      final data = snap.data() ?? {};
      final int currentStreak = (data['streak'] ?? 0) as int;
      final lastStudyTs = data['lastStudyDate'] as Timestamp?;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int newStreak;

      if (lastStudyTs == null) {
        newStreak = 1;
      } else {
        final lastStudy = lastStudyTs.toDate();
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

      await userRef.set({
        'streak': newStreak,
        'lastStudyDate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await prefs.setBool(_kStreakTriggeredToday, true);

      debugPrint('🔥 Streak event ($reason): $currentStreak → $newStreak');
      return (oldStreak: currentStreak, newStreak: newStreak);
    } catch (e) {
      debugPrint('StreakService._triggerStreakEvent error: $e');
      return (oldStreak: 0, newStreak: 0);
    }
  }

  // ─── Debug / Diagnostics ───────────────────────────────────────────────────

  /// For debug screens or testing — returns today's progress toward streak.
  static Future<Map<String, dynamic>> getTodayStatus() async {
    final prefs = await _ensureToday();
    return {
      'date': prefs.getString(_kDailyDate),
      'readingSeconds': prefs.getInt(_kDailyReadSecs) ?? 0,
      'appSeconds': prefs.getInt(_kDailyAppSecs) ?? 0,
      'triggeredToday': prefs.getBool(_kStreakTriggeredToday) ?? false,
      'readingRequired': _readingRequiredSeconds,
      'appRequired': _appTimeRequiredSeconds,
    };
  }
}