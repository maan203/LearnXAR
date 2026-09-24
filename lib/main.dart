// ============================================
// FILE: lib/main.dart
// ============================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/main_scaffold.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/achievement_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();
  await NotificationService.scheduleAllRecurring();
  debugPrint('Notifications initialized and scheduled');

  // Recover any AR session that was in progress when Unity was closed
  await _recoverARSession();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const LearnXARApp());
}

// ============================================================================
// AR Session Recovery
// ----------------------------------------------------------------------------
// When the user launches Unity, ar_unity_screen.dart writes the start time
// and module info to SharedPreferences, then pops itself. Unity runs in its
// own process (:unity). When the user comes back, Flutter restarts/resumes
// and this function reads the saved start time, computes duration, and
// writes the session to Firestore (matching the pattern in
// ar_unity_screen.dart's _saveARSession).
// ============================================================================
Future<void> _recoverARSession() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt('ar_session_start');
    final moduleKey = prefs.getString('ar_session_module');
    final moduleName = prefs.getString('ar_session_name');

    // No pending session — nothing to recover
    if (startMs == null || moduleKey == null || moduleName == null) return;

    final duration =
        (DateTime.now().millisecondsSinceEpoch - startMs) ~/ 1000;

    // Clear keys immediately so we never double-save the same session
    await prefs.remove('ar_session_start');
    await prefs.remove('ar_session_module');
    await prefs.remove('ar_session_name');

    if (duration < 3) {
      debugPrint('AR session ignored ($duration s) — too short');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('AR session not saved — no logged in user');
      return;
    }

    final firestore = FirebaseFirestore.instance;

    // Save AR session record
    await firestore
        .collection('users').doc(user.uid)
        .collection('arSessions').add({
      'module': moduleName,
      'moduleKey': moduleKey,
      'duration': duration,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update module progress (cumulative AR seconds)
    await firestore
        .collection('users').doc(user.uid)
        .collection('moduleProgress').doc(moduleKey)
        .set({
      'module': moduleName,
      'moduleKey': moduleKey,
      'totalARSeconds': FieldValue.increment(duration),
      'lastARSession': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Recent activities feed
    await firestore
        .collection('users').doc(user.uid)
        .collection('activities').add({
      'title': 'Explored $moduleName in AR',
      'subtitle': 'Spent ${_formatARTime(duration)} in AR',
      'type': 'ar',
      'module': moduleName,
      'moduleKey': moduleKey,
      'isAR': true,
      'status': 'AR',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Achievement check — AR Enthusiast unlocks at 5+ modules with 120+ sec each
    if (duration >= 120) {
      try {
        await AchievementService.checkAndUnlock(
          uid: user.uid,
          firestore: firestore,
          moduleKey: moduleKey,
        );
      } catch (e) {
        debugPrint('Achievement check error during AR recovery: $e');
      }
    }

    debugPrint('✅ AR session recovered: ${duration}s for $moduleKey');
  } catch (e) {
    debugPrint('Error recovering AR session: $e');
  }
}

String _formatARTime(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

class LearnXARApp extends StatelessWidget {
  const LearnXARApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LearnXAR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      ),
      home: const _AppEntry(),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> with WidgetsBindingObserver {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When Unity closes and Flutter comes back to the foreground,
    // try to recover any pending AR session.
    if (state == AppLifecycleState.resumed) {
      _recoverARSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashScreen(
        onComplete: () {
          if (mounted) setState(() => _splashDone = true);
        },
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D0F1E),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4044C8),
                strokeWidth: 2,
              ),
            ),
          );
        }
        if (snapshot.hasData) {
          return const MainScaffold();
        }
        return const Login();
      },
    );
  }
}