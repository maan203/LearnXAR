// ============================================
// FILE: lib/screens/profile_screen.dart
// Fully dynamic — reads all data from Firestore
// Profile photo stored as base64 in Firestore
// Notifications toggle properly wired (Phase 5)
// ============================================
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import '../services/notification_service.dart';
import '../services/user_cache.dart';

class ProfileScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  const ProfileScreen({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  // ── User data ──────────────────────────────────────────────────────────────
  String userName = 'User';
  String userEmail = '';
  String predictedLevel = 'Beginner';
  String? photoBase64;

  // ── Stats ──────────────────────────────────────────────────────────────────
  int completedModules = 0;
  final int totalModules = 8;
  int totalQuizAttempts = 0;
  double averageScore = 0;
  int currentStreak = 0;
  int totalStudySecs = 0;

  // ── Settings ──────────────────────────────────────────────────────────────
  bool _notificationsEnabled = true;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  // ── Refresh throttle ─────────────────────────────────────────────────────
  DateTime? _lastLoadedAt;
  int _loadedCacheVersion = -1;
  static const _kRefreshThrottle = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Called by MainScaffold when user taps Profile tab
  void refreshData() {
    if (!mounted) return;
    final recentlyLoaded = _lastLoadedAt != null &&
        DateTime.now().difference(_lastLoadedAt!) < _kRefreshThrottle;
    final upToDate = _loadedCacheVersion == UserCache.instance.version;
    if (recentlyLoaded && upToDate) return;
    setState(() => _isLoading = true);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Load local notification preference from SharedPreferences
      // (this is the source of truth for the toggle, not Firestore)
      final bool notifEnabledLocal = await NotificationService.isEnabled();

      // FIX: use user.uid (was previously undefined `uid`)
      final results = await Future.wait([
        _firestore.collection('users').doc(user.uid).get(),
        _firestore.collection('users').doc(user.uid).collection('moduleProgress').get(),
        _firestore.collection('users').doc(user.uid).collection('quizAttempts').get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final progressSnap = results[1] as QuerySnapshot;
      final attemptsSnap = results[2] as QuerySnapshot;

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        userName = data['name'] ??
            user.displayName ??
            user.email?.split('@').first ??
            'User';
        userEmail = data['email'] ?? user.email ?? '';
        predictedLevel = data['predictedLevel'] ?? 'Beginner';
        currentStreak = (data['streak'] ?? 0) as int;
        photoBase64 = data['photoBase64'] as String?;
      }

      int completed = 0;
      int quizAttempts = 0;
      double scoreSum = 0;
      int scoreCount = 0;
      int readSecs = 0;
      int quizSecs = 0;
      int arSecs = 0;

      const List<String> parentKeys = [
        'introduction', 'arrays', 'linked_list', 'stack',
        'queue', 'searching', 'sorting', 'trees',
      ];

      for (final doc in progressSnap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        final double hs = ((d['highestScore'] ?? 0.0) as num).toDouble();
        final int rs = ((d['totalReadingSeconds'] ?? 0) as num).toInt();
        final int as_ = ((d['totalARSeconds'] ?? 0) as num).toInt();
        final int qs = ((d['totalQuizSeconds'] ?? 0) as num).toInt();

        // Completion only counts for the 8 parent modules, not subtopics
        if (parentKeys.contains(doc.id)) {
          final double qComp = (hs / 100.0) * 60.0;
          final double rComp = (rs / 720.0).clamp(0.0, 1.0) * 25.0;
          final double aComp = (as_ / 600.0).clamp(0.0, 1.0) * 15.0;
          if (qComp + rComp + aComp >= 70) completed++;
        }

        if (hs > 0) { scoreSum += hs; scoreCount++; }
        readSecs += rs;
        quizSecs += qs;
        arSecs += as_;
      }

      // Dedupe quiz attempts — same logic as Insights screen (Phase 4)
      if (attemptsSnap.docs.isNotEmpty) {
        final List<Map<String, dynamic>> raw = attemptsSnap.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .toList();
        raw.sort((a, b) {
          final ta = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return ta.compareTo(tb);
        });
        final List<Map<String, dynamic>> deduped = [];
        for (final att in raw) {
          final String module = (att['moduleKey'] ?? att['module'] ?? '') as String;
          final int ts = (att['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          if (deduped.isNotEmpty) {
            final last = deduped.last;
            final String lastModule = (last['moduleKey'] ?? last['module'] ?? '') as String;
            final int lastTs = (last['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            if (lastModule == module && (ts - lastTs).abs() < 5000) continue;
          }
          deduped.add(att);
        }
        quizAttempts = deduped.length;
      }

      if (!mounted) return;

      setState(() {
        completedModules = completed;
        totalQuizAttempts = quizAttempts;
        averageScore = scoreCount > 0 ? scoreSum / scoreCount : 0;
        totalStudySecs = readSecs + quizSecs + arSecs;
        _notificationsEnabled = notifEnabledLocal;
        _isLoading = false;
      });
      _lastLoadedAt = DateTime.now();
      _loadedCacheVersion = UserCache.instance.version;
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _viewProfilePhoto() {
    if (photoBase64 == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenPhotoView(
          photoBase64: photoBase64!,
          onChangeTap: () {
            Navigator.pop(context);
            _pickProfilePhoto();
          },
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Change Profile Photo',
            style: TextStyle(
                color: _textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF4044C8)),
              title: Text('Choose from Gallery',
                  style: TextStyle(color: _textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFF10B981)),
              title: Text('Take a Photo',
                  style: TextStyle(color: _textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );
      if (image == null) return;

      // Show preview and let user confirm + capture cropped bytes
      if (!mounted) return;
      final Uint8List? croppedBytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => _PhotoPreviewScreen(
            imagePath: image.path,
            isDarkMode: widget.isDarkMode,
          ),
        ),
      );

      if (croppedBytes == null) return;
      if (mounted) setState(() => _isUploadingPhoto = true);

      final base64Str = base64Encode(croppedBytes);

      final user = _authService.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set({'photoBase64': base64Str}, SetOptions(merge: true));
      }

      if (mounted) {
        setState(() {
          photoBase64 = base64Str;
          _isUploadingPhoto = false;
        });
      }
    } catch (e) {
      debugPrint('Error picking photo: $e');
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not pick photo. Please try again.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Display Name',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: _textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: _textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF4044C8)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                await _savePref('name', newName);
                if (mounted) setState(() => userName = newName);
              }
            },
            child: const Text('Save',
                style: TextStyle(
                    color: Color(0xFF4044C8), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _savePref(String key, dynamic value) async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid)
            .set({key: value}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Failed to save $key: $e');
    }
  }

  Future<void> _handleLogout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Login()),
          (route) => false,
    );
  }

  bool get dark => widget.isDarkMode;
  Color get _bg => dark ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _card => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _textPrimary => dark ? Colors.white : const Color(0xFF111827);
  Color get _textSecondary => dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _border => dark ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);

  Color get _levelColor {
    switch (predictedLevel) {
      case 'Advanced':     return const Color(0xFFEF4444);
      case 'Intermediate': return const Color(0xFFF59E0B);
      default:             return const Color(0xFF10B981);
    }
  }

  String get _levelDesc {
    switch (predictedLevel) {
      case 'Advanced':     return 'Tackling complex problems';
      case 'Intermediate': return 'Connecting concepts well';
      default:             return 'Building a solid foundation';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: _isLoading
            ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF4044C8)))
            : SingleChildScrollView(
          child: Column(
            children: [
              _buildTopBar(),
              const SizedBox(height: 8),
              _buildProfileHeader(),
              const SizedBox(height: 16),
              _buildSettings(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Profile',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          GestureDetector(
            onTap: () {
              final newVal = !widget.isDarkMode;
              widget.onDarkModeChanged(newVal);
              _savePref('darkMode', newVal);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4044C8).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: const Color(0xFF4044C8),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // ── Profile photo with camera badge ──
              Stack(
                children: [
                  GestureDetector(
                    onTap: photoBase64 != null ? _viewProfilePhoto : _pickProfilePhoto,
                    onLongPress: _pickProfilePhoto,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF4044C8), width: 2),
                      ),
                      child: ClipOval(
                        child: _isUploadingPhoto
                            ? Container(
                          color: const Color(0xFF4044C8)
                              .withValues(alpha: 0.1),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF4044C8),
                                strokeWidth: 2),
                          ),
                        )
                            : photoBase64 != null
                            ? Image.memory(
                          base64Decode(photoBase64!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _avatarFallback(),
                        )
                            : _avatarFallback(),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickProfilePhoto,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4044C8),
                          shape: BoxShape.circle,
                          border: Border.all(color: _card, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 11),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // ── Name + email + level ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row with pencil icon
                    Row(
                      children: [
                        Expanded(
                          child: Text(userName,
                              style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _showEditNameDialog,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4044C8)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Icon(Icons.edit_rounded,
                                color: Color(0xFF4044C8), size: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(userEmail,
                        style: TextStyle(
                            color: _textSecondary, fontSize: 13),
                        overflow: TextOverflow.ellipsis),

                    // Level pill removed for cleaner header
                  ],
                ),
              ),
            ],
          ),
          ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4044C8), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final int mins = totalStudySecs ~/ 60;
    final String timeStr =
    mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statCard(
                  icon: Icons.check_circle_outline_rounded,
                  value: '$completedModules/$totalModules',
                  label: 'Modules Done',
                  color: const Color(0xFF4044C8))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                  icon: Icons.local_fire_department_rounded,
                  value: '${currentStreak}d',
                  label: 'Streak',
                  color: const Color(0xFFFF6B35))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                  icon: Icons.timer_rounded,
                  value: timeStr,
                  label: 'Study Time',
                  color: const Color(0xFF10B981))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCard(
                  icon: Icons.quiz_rounded,
                  value: '$totalQuizAttempts',
                  label: 'Quiz Attempts',
                  color: const Color(0xFF8B5CF6))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                  icon: Icons.bar_chart_rounded,
                  value: '${averageScore.toInt()}%',
                  label: 'Avg Score',
                  color: const Color(0xFFF59E0B))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                  icon: Icons.school_rounded,
                  value: predictedLevel,
                  label: 'Level',
                  color: _levelColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: _textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _settingToggle(
            icon: Icons.dark_mode_rounded,
            label: 'Dark Mode',
            iconColor: const Color(0xFF4044C8),
            value: widget.isDarkMode,
            onChanged: (val) {
              widget.onDarkModeChanged(val);
              _savePref('darkMode', val);
            },
          ),
          _divider(),
          _settingToggle(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            iconColor: const Color(0xFFF59E0B),
            value: _notificationsEnabled,
            onChanged: (val) async {
              setState(() => _notificationsEnabled = val);
              // Actually enable / disable local notification scheduling
              await NotificationService.setEnabled(val);
              // Also mirror to Firestore for reference / future cross-device sync
              await _savePref('notifications', val);
            },
          ),
          _divider(),
          _settingTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            iconColor: const Color(0xFFEF4444),
            textColor: const Color(0xFFEF4444),
            onTap: _showLogoutDialog,
          ),
        ],
      ),
    );
  }

  Widget _settingToggle({
    required IconData icon,
    required String label,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500))),
        Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF4044C8)),
      ],
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right, color: _textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Divider(color: _border, height: 1),
  );

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Logout',
            style: TextStyle(
                color: _textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to logout?',
            style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: _textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout();
            },
            child: const Text('Logout',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Full screen photo viewer ───────────────────────────────────────────────────
class _FullScreenPhotoView extends StatelessWidget {
  final String photoBase64;
  final VoidCallback onChangeTap;

  const _FullScreenPhotoView({
    required this.photoBase64,
    required this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            tooltip: 'Change photo',
            onPressed: onChangeTap,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.memory(
            base64Decode(photoBase64),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_rounded,
              color: Colors.white54,
              size: 80,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Photo crop screen — pan & zoom to position, circle shows final result ─────
class _PhotoPreviewScreen extends StatefulWidget {
  final String imagePath;
  final bool isDarkMode;

  const _PhotoPreviewScreen({
    required this.imagePath,
    required this.isDarkMode,
  });

  @override
  State<_PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

class _PhotoPreviewScreenState extends State<_PhotoPreviewScreen> {
  final TransformationController _transformController =
  TransformationController();
  final GlobalKey _repaintKey = GlobalKey();
  bool _isSaving = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // Capture exactly what's visible in the circle as bytes
  Future<void> _captureAndReturn() async {
    setState(() => _isSaving = true);
    try {
      final RenderRepaintBoundary boundary = _repaintKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final ui.Image image =
      await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }
      final Uint8List bytes = byteData.buffer.asUint8List();
      if (mounted) Navigator.pop(context, bytes);
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double size = MediaQuery.of(context).size.width * 0.78;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: const Text('Adjust Photo',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _captureAndReturn,
            child: _isSaving
                ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4044C8)))
                : const Text('Use Photo',
                style: TextStyle(
                    color: Color(0xFF4044C8),
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            'Pinch to zoom · Drag to reposition',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 24),

          // RepaintBoundary captures exactly what's in the circle
          Center(
            child: RepaintBoundary(
              key: _repaintKey,
              child: SizedBox(
                width: size,
                height: size,
                child: ClipOval(
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 0.5,
                    maxScale: 5.0,
                    boundaryMargin:
                    const EdgeInsets.all(double.infinity),
                    // Show full image — user zooms/pans to frame what they want
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.contain, // show whole photo, no cropping
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text(
            'The circle shows how your photo will look',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
          ),

          const Spacer(),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Retake',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _captureAndReturn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4044C8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                        : const Text('Use This Photo',
                        style:
                        TextStyle(fontWeight: FontWeight.w600)),
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