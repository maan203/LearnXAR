// ============================================
// FILE: lib/services/notification_service.dart
// Scheduled notifications:
//   9 AM  — Good morning motivation
//   2 PM  — Midday dive-deeper reminder
//   6 PM  — First streak save warning
//  10 PM  — Last-chance urgent alert
// Instant:
//   Streak broken (sad emoji)
// ============================================
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _kEnabled = 'notifications_enabled';

  // ── Channel IDs ────────────────────────────────────────────────────────────
  static const _channelStreak     = 'learnxar_streak';
  static const _channelMotivation = 'learnxar_motivation';
  static const _channelAlert      = 'learnxar_alert';

  // ── Notification IDs ───────────────────────────────────────────────────────
  static const int _idMorning     = 1001; // 9 AM
  static const int _idMidday      = 1002; // 2 PM
  static const int _idEveningWarn = 1003; // 6 PM streak warning
  static const int _idNightAlert  = 1004; // 10 PM last chance
  static const int _idStreakBreak = 1005; // instant — streak broken

  // ─── Init ──────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();

    // ── FIX: set device local timezone so scheduled times match clock ────────
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (_) {
      // Fallback: leave as UTC — at least we logged the attempt
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  // ─── User-facing toggle ────────────────────────────────────────────────────
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    if (enabled) {
      await scheduleAllRecurring();
    } else {
      await cancelAll();
    }
  }

  // ─── Schedule all recurring notifications ──────────────────────────────────
  static Future<void> scheduleAllRecurring() async {
    if (!await isEnabled()) return;

    // 9 AM — Good morning
    await _scheduleDailyAt(
      id: _idMorning,
      hour: 9, minute: 0,
      title: 'Good morning! ☀️',
      body: "Let's start your learning session today. A little every day goes a long way!",
      channelId: _channelMotivation,
      channelName: 'Daily motivation',
    );

    // 2 PM — Midday dive-deeper
    await _scheduleDailyAt(
      id: _idMidday,
      hour: 14, minute: 0,
      title: 'Time to dive deep 📚',
      body: "Pick up where you left off — your DSA concepts are waiting for you!",
      channelId: _channelMotivation,
      channelName: 'Daily motivation',
    );

    // 6 PM — First streak warning
    await _scheduleDailyAt(
      id: _idEveningWarn,
      hour: 18, minute: 0,
      title: "Don't break your streak! 🔥",
      body: "A quick 5-minute session is all it takes to keep your streak alive.",
      channelId: _channelStreak,
      channelName: 'Streak reminders',
    );

    // 10 PM — Urgent last chance
    await _scheduleDailyAt(
      id: _idNightAlert,
      hour: 22, minute: 0,
      title: '⚠️ Last chance today!',
      body: "Your streak breaks at midnight. Open LearnXAR and study now!",
      channelId: _channelAlert,
      channelName: 'End-of-day alerts',
    );
  }

  // ─── Instant: streak broken ────────────────────────────────────────────────
  static Future<void> notifyStreakBroken(int previousStreak) async {
    if (!await isEnabled()) return;
    if (previousStreak <= 0) return;
    await _plugin.show(
      _idStreakBreak,
      'Your streak ended 😢',
      "You had a $previousStreak-day streak. Don't give up — start a new one today!",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelAlert,
          'Streak alerts',
          channelDescription: 'Alerts when your streak breaks',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  // ─── Test notification ─────────────────────────────────────────────────────
  static Future<void> showTestNotification() async {
    await _plugin.show(
      9999,
      'Test Notification 🔔',
      'If you see and hear this, notifications are working!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelAlert,
          'Test',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  // ─── Cancel all ────────────────────────────────────────────────────────────
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ─── Internal: schedule a daily-repeating notification ─────────────────────
  static Future<void> _scheduleDailyAt({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    await _plugin.cancel(id);

    final scheduledTime = _nextInstanceOf(hour, minute);

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'LearnXAR reminders',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id, title, body, scheduledTime, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Failed to schedule notification $id: $e');
    }
  }

  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
