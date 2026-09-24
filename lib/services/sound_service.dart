// ============================================
// FILE: lib/services/sound_service.dart
//
// HOW TO ADD REAL SOUNDS:
//   1. Download free short .mp3 files from mixkit.co
//      or any free SFX site.
//   2. Replace the placeholder files at:
//        assets/sounds/streak.mp3   ← celebration "level up" chime
//        assets/sounds/badge.mp3    ← achievement "coin/unlock" chime
//   3. Files are already declared in pubspec.yaml — no extra steps needed.
//
// Until real files are in place the app plays silently (errors are caught).
// ============================================
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  // Separate players so streak + badge sounds can overlap if needed
  final AudioPlayer _streakPlayer = AudioPlayer();
  final AudioPlayer _badgePlayer  = AudioPlayer();

  Future<void> playStreak() => _play(_streakPlayer, 'sounds/streak.mp3');
  Future<void> playBadge()  => _play(_badgePlayer,  'sounds/badge.mp3');

  Future<void> _play(AudioPlayer player, String asset) async {
    try {
      await player.play(AssetSource(asset));
    } catch (e) {
      // Fails silently when placeholder files are still in place.
      // Replace assets/sounds/*.mp3 with real audio files to enable sound.
      debugPrint('SoundService: could not play $asset — $e');
    }
  }

  void dispose() {
    _streakPlayer.dispose();
    _badgePlayer.dispose();
  }
}
