import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/achievement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';


class ARUnityScreen extends StatefulWidget {
  final String moduleName;
  final String moduleKey;
  final bool isDarkMode;

  const ARUnityScreen({
    super.key,
    required this.moduleName,
    required this.moduleKey,
    this.isDarkMode = false,
  });

  @override
  State<ARUnityScreen> createState() => _ARUnityScreenState();
}

class _ARUnityScreenState extends State<ARUnityScreen>
    with WidgetsBindingObserver {

  final Stopwatch _stopwatch = Stopwatch();
  bool _arLaunched = false;
  bool _sessionSaved = false;
  bool _isSaving = false;
  static const _prefKeyStart = 'ar_session_start';
  static const _prefKeyModule = 'ar_session_module';
  static const _prefKeyName = 'ar_session_name';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get dark => widget.isDarkMode;
  Color get _bg => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary => dark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        _launchUnity();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatch.stop();
    if (!_sessionSaved) _saveARSession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _arLaunched && !_sessionSaved) {
      _saveARSession().then((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }
  static const _channel = MethodChannel('com.learnxar/ar_launcher');

  Future<void> _launchUnity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyStart, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_prefKeyModule, widget.moduleKey);
      await prefs.setString(_prefKeyName, widget.moduleName);

      await _channel.invokeMethod('launchAR', {'moduleKey': widget.moduleKey});
      _arLaunched = true;

      // Pop immediately after launching — don't wait for return
      if (mounted) Navigator.pop(context);

    } on PlatformException catch (e) {
      debugPrint('Failed to launch Unity: ${e.code} — ${e.message}');

      // Show user-friendly message for modules without AR
      if (e.code == 'NO_AR_SCENE' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AR experience for ${widget.moduleName} is coming soon!'),
            backgroundColor: const Color(0xFFF59E0B),
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Failed to launch Unity: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _saveARSession() async {
    if (_sessionSaved) return;
    _sessionSaved = true;
    _stopwatch.stop();
    final user = _auth.currentUser;
    if (user == null) return;

    final int duration = _stopwatch.elapsed.inSeconds;
    if (duration < 3) return;

    if (mounted) setState(() => _isSaving = true);

    try {
      final String moduleKey = widget.moduleKey;

      await _firestore
          .collection('users').doc(user.uid)
          .collection('arSessions').add({
        'module': widget.moduleName,
        'moduleKey': moduleKey,
        'duration': duration,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _firestore
          .collection('users').doc(user.uid)
          .collection('moduleProgress').doc(moduleKey)
          .set({
        'module': widget.moduleName,
        'moduleKey': moduleKey,
        'totalARSeconds': FieldValue.increment(duration),
        'lastARSession': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore
          .collection('users').doc(user.uid)
          .collection('activities').add({
        'title': 'Explored ${widget.moduleName} in AR',
        'subtitle': 'Spent ${_formatTime(duration)} in AR',
        'type': 'ar',
        'module': widget.moduleName,
        'moduleKey': moduleKey,
        'isAR': true,
        'status': 'AR',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (duration >= 120) {
        // AR no longer counts toward streak — only achievements
        final newBadges = await AchievementService.checkAndUnlock(
          uid: user.uid,
          firestore: _firestore,
          moduleKey: moduleKey,
        );
        if (newBadges.isNotEmpty && mounted) {
          await _showBadgeDialog(newBadges);
        }
      }

      debugPrint('✅ AR session saved: ${duration}s for $moduleKey');
    } catch (e) {
      debugPrint('Error saving AR session: $e');
    }

    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _showBadgeDialog(List<Map<String, dynamic>> badges) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('🏆 ', style: TextStyle(fontSize: 24)),
          Text('Achievement Unlocked!',
              style: TextStyle(color: _textPrimary, fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: badges.map((b) => ListTile(
            leading: Icon(b['icon'] as IconData, color: b['color'] as Color),
            title: Text(b['title'] as String,
                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(b['desc'] as String,
                style: const TextStyle(color: Color(0xFF9CA3AF))),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome!',
                style: TextStyle(color: Color(0xFF4044C8))),
          )
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
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
          onPressed: () {
            _stopwatch.stop();
            if (!_sessionSaved) _saveARSession();
            Navigator.pop(context);
          },
        ),
        title: Text('${widget.moduleName} — AR',
            style: TextStyle(color: _textPrimary, fontSize: 16,
                fontWeight: FontWeight.w600)),
        actions: [
          if (_arLaunched)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: _LiveTimer(stopwatch: _stopwatch)),
            ),
        ],
      ),
    );
  }
}

class _LiveTimer extends StatefulWidget {
  final Stopwatch stopwatch;
  const _LiveTimer({required this.stopwatch});
  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final s = widget.stopwatch.elapsed.inSeconds;
    final m = s ~/ 60;
    final sec = s % 60;
    return Text(
      '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}',
      style: const TextStyle(
        color: Color(0xFF38D9C0),
        fontSize: 48,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}