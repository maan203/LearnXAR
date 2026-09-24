import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResetARTimeScreen extends StatefulWidget {
  const ResetARTimeScreen({super.key});

  @override
  State<ResetARTimeScreen> createState() => _ResetARTimeScreenState();
}

class _ResetARTimeScreenState extends State<ResetARTimeScreen> {
  bool _isResetting = false;

  Future<void> _resetARData() async {
    setState(() => _isResetting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user logged in');

      final firestore = FirebaseFirestore.instance;
      final uid = user.uid;

      // 1. Set totalARSeconds = 0 on every moduleProgress document
      final progressSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('moduleProgress')
          .get();

      final List<Future<void>> progressWrites = progressSnap.docs.map((doc) {
        return doc.reference.update({'totalARSeconds': 0});
      }).toList();
      await Future.wait(progressWrites);

      // 2. Delete every arSessions document
      final sessionsSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('arSessions')
          .get();

      final List<Future<void>> deletes = sessionsSnap.docs.map((doc) {
        return doc.reference.delete();
      }).toList();
      await Future.wait(deletes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AR time data reset successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset AR Time Data'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 16),
              const Text(
                'This will set totalARSeconds to 0 for all modules and '
                'delete all arSession documents for the current user.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isResetting ? null : _resetARData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isResetting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Reset AR Time Data',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
