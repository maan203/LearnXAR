// ============================================
// FILE: lib/screens/splash_screen.dart
// Animated splash with gradient, LearnXAR text,
// floating 3D-style DSA elements
// ============================================
import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Logo scale + fade
  late AnimationController _logoController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;

  // Tagline fade
  late AnimationController _taglineController;
  late Animation<double> _taglineFade;
  late Animation<Offset> _taglineSlide;

  // Floating elements
  late AnimationController _floatController;

  // Exit fade
  late AnimationController _exitController;
  late Animation<double> _exitFade;

  // Shimmer on text
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = CurvedAnimation(parent: _logoController, curve: Curves.elasticOut);
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeIn);

    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineFade = CurvedAnimation(parent: _taglineController, curve: Curves.easeIn);
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _taglineController, curve: Curves.easeOut));

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _taglineController.forward();

    // Stay on splash for total ~2.8s
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    await _exitController.forward();

    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
    _floatController.dispose();
    _exitController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _exitFade,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0D0F1E),
                Color(0xFF1A1D35),
                Color(0xFF2D2F5E),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // ── Floating DSA elements ──
              ..._buildFloatingElements(size),

              // ── Glow circle behind logo ──
              Center(
                child: AnimatedBuilder(
                  animation: _logoFade,
                  builder: (_, __) => Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4044C8)
                              .withValues(alpha: 0.3 * _logoFade.value),
                          blurRadius: 80,
                          spreadRadius: 30,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Main content ──
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo icon
                    ScaleTransition(
                      scale: _logoScale,
                      child: FadeTransition(
                        opacity: _logoFade,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4044C8), Color(0xFF6366F1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4044C8)
                                    .withValues(alpha: 0.5),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.view_in_ar_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // LearnXAR shimmer text
                    FadeTransition(
                      opacity: _logoFade,
                      child: AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (_, __) {
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              final shimmerX = _shimmerController.value * 2 - 0.5;
                              return LinearGradient(
                                colors: const [
                                  Colors.white,
                                  Color(0xFFB0B4FF),
                                  Colors.white,
                                  Color(0xFF6366F1),
                                  Colors.white,
                                ],
                                stops: [
                                  (shimmerX - 0.3).clamp(0.0, 1.0),
                                  (shimmerX - 0.1).clamp(0.0, 1.0),
                                  shimmerX.clamp(0.0, 1.0),
                                  (shimmerX + 0.1).clamp(0.0, 1.0),
                                  (shimmerX + 0.3).clamp(0.0, 1.0),
                                ],
                              ).createShader(bounds);
                            },
                            child: const Text(
                              'LearnXAR',
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tagline
                    SlideTransition(
                      position: _taglineSlide,
                      child: FadeTransition(
                        opacity: _taglineFade,
                        child: const Text(
                          'Learn DSA with AR & AI',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF9CA3AF),
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Loading dots
                    FadeTransition(
                      opacity: _taglineFade,
                      child: _LoadingDots(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFloatingElements(Size size) {
    final elements = [
      _FloatConfig(icon: Icons.data_array_rounded,    x: 0.08, y: 0.15, size: 32, delay: 0.0,  depth: 0.8),
      _FloatConfig(icon: Icons.account_tree_rounded,  x: 0.85, y: 0.12, size: 28, delay: 0.3,  depth: 0.5),
      _FloatConfig(icon: Icons.layers_rounded,        x: 0.12, y: 0.72, size: 36, delay: 0.6,  depth: 0.9),
      _FloatConfig(icon: Icons.sort_rounded,          x: 0.80, y: 0.68, size: 30, delay: 0.2,  depth: 0.6),
      _FloatConfig(icon: Icons.link_rounded,          x: 0.55, y: 0.08, size: 26, delay: 0.5,  depth: 0.4),
      _FloatConfig(icon: Icons.search_rounded,        x: 0.22, y: 0.42, size: 22, delay: 0.8,  depth: 0.3),
      _FloatConfig(icon: Icons.queue_rounded,         x: 0.75, y: 0.38, size: 24, delay: 0.15, depth: 0.7),
      _FloatConfig(icon: Icons.grid_on_rounded,       x: 0.48, y: 0.85, size: 28, delay: 0.45, depth: 0.5),
      _FloatConfig(icon: Icons.schema_rounded,        x: 0.92, y: 0.50, size: 20, delay: 0.7,  depth: 0.35),
      _FloatConfig(icon: Icons.code_rounded,          x: 0.03, y: 0.52, size: 20, delay: 0.9,  depth: 0.4),
    ];

    return elements.map((e) {
      return AnimatedBuilder(
        animation: _floatController,
        builder: (_, __) {
          final t = (_floatController.value + e.delay) % 1.0;
          final floatY = sin(t * 2 * pi) * 10 * e.depth;
          final floatX = cos(t * 2 * pi) * 5 * e.depth;
          final opacity = (0.15 + e.depth * 0.25) *
              _logoFade.value.clamp(0.0, 1.0);

          return Positioned(
            left: size.width * e.x + floatX,
            top: size.height * e.y + floatY,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                width: e.size + 16,
                height: e.size + 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4044C8).withValues(alpha: 0.15),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(e.icon,
                    color: const Color(0xFF818CF8), size: e.size * 0.7),
              ),
            ),
          );
        },
      );
    }).toList();
  }
}

class _FloatConfig {
  final IconData icon;
  final double x, y, size, delay, depth;
  const _FloatConfig({
    required this.icon, required this.x, required this.y,
    required this.size, required this.delay, required this.depth,
  });
}

// ── Animated loading dots ─────────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
            final scale = 0.6 + sin(t * pi) * 0.4;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFF4044C8),
                      const Color(0xFF818CF8),
                      sin(t * pi),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
