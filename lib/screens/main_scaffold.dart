import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';
import 'insights_tab_screen.dart';
import 'learn_screen.dart';
import 'profile_screen.dart';


class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  MainScaffoldState createState() => MainScaffoldState();
}

class MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  bool _isDarkMode = false;

  // Lazy loading — only build screens when first visited
  final Set<int> _visitedScreens = {0};

  final GlobalKey<HomeScreenBodyState> _homeKey =
  GlobalKey<HomeScreenBodyState>();
  final GlobalKey<LearnScreenState> _learnKey =
  GlobalKey<LearnScreenState>();
  final GlobalKey<InsightsTabScreenState> _insightsKey =
  GlobalKey<InsightsTabScreenState>();
  final GlobalKey<ProfileScreenState> _profileKey =
  GlobalKey<ProfileScreenState>();

  @override
  void initState() {
    super.initState();
    _loadDarkModePref();
  }

  Future<void> _loadDarkModePref() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (!mounted) return;
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() => _isDarkMode = data['darkMode'] ?? false);
        }
      }
    } catch (e) {
      debugPrint('Failed to load darkMode: $e');
    }
  }

  void _onDarkModeChanged(bool val) {
    if (!mounted) return;
    setState(() => _isDarkMode = val);
  }

  Color get _bg =>
      _isDarkMode ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA);
  Color get _navBg =>
      _isDarkMode ? const Color(0xFF1C1F2E) : Colors.white;
  Color get _navBorder =>
      _isDarkMode ? const Color(0xFF2D3148) : const Color(0xFFE5E7EB);
  Color get _navActive =>
      _isDarkMode ? Colors.white : const Color(0xFF4044C8);
  Color get _navInactive =>
      _isDarkMode ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF);

  Widget _buildScreen(int index) {
    if (!_visitedScreens.contains(index)) {
      return Container(color: _bg);
    }
    switch (index) {
      case 0:
        return HomeScreenBody(
          key: _homeKey,
          isDarkMode: _isDarkMode,
          onGoToLearn: () => _switchTab(1),
          onGoToProfile: () => _switchTab(3),
        );
      case 1:
        return LearnScreen(key: _learnKey, isDarkMode: _isDarkMode);
      case 2:
        return InsightsTabScreen(key: _insightsKey, isDarkMode: _isDarkMode);
      case 3:
        return ProfileScreen(
          key: _profileKey,
          isDarkMode: _isDarkMode,
          onDarkModeChanged: _onDarkModeChanged,
        );
      default:
        return Container(color: _bg);
    }
  }

  void _switchTab(int index) {
    if (!mounted) return;
    setState(() {
      _visitedScreens.add(index);
      _selectedIndex = index;
    });
    if (index == 0) _homeKey.currentState?.refreshData();
    if (index == 1) _learnKey.currentState?.refreshData();
    if (index == 2) _insightsKey.currentState?.refreshData();
    if (index == 3) _profileKey.currentState?.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _selectedIndex,
        children: List.generate(4, (i) => _buildScreen(i)),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: _navBg,
        border: Border(top: BorderSide(color: _navBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 'Home', 0),
              _buildNavItem(Icons.school, 'Learn', 1),
              _buildNavItem(Icons.insights, 'Insights', 2),
              _buildNavItem(Icons.person, 'Profile', 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isActive = _selectedIndex == index;
    return InkWell(
      onTap: () => _switchTab(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24,
                color: isActive ? _navActive : _navInactive),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? _navActive : _navInactive,
                  fontWeight:
                  isActive ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String label;
  final bool isDarkMode;
  const PlaceholderScreen(
      {super.key, required this.label, this.isDarkMode = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDarkMode ? const Color(0xFF0F1117) : const Color(0xFFF8F9FA),
      child: Center(
        child: Text(
          '$label\nComing Soon',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            color: isDarkMode
                ? const Color(0xFF9CA3AF)
                : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}