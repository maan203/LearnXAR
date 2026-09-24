import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign Up with Email & Password
  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      // Create user
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await userCredential.user?.updateDisplayName(name);

      // Store user data in Firestore
      await _firestore.collection('users').doc(userCredential.user?.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return null; // Success
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        return 'The password is too weak.';
      } else if (e.code == 'email-already-in-use') {
        return 'An account already exists for this email.';
      } else {
        return e.message ?? 'An error occurred during signup.';
      }
    } catch (e) {
      return 'An unexpected error occurred: $e';
    }
  }

  // Sign In with Email & Password
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null; // Success
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return 'No user found with this email.';
      } else if (e.code == 'wrong-password') {
        return 'Incorrect password.';
      } else if (e.code == 'invalid-email') {
        return 'Invalid email address.';
      } else if (e.code == 'invalid-credential') {
        return 'Invalid credentials. Please check your email and password.';
      } else {
        return e.message ?? 'An error occurred during login.';
      }
    } catch (e) {
      return 'An unexpected error occurred: $e';
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return _auth.currentUser != null;
  }

  // Get user data from Firestore
  Future<Map<String, dynamic>?> getUserData() async {
    if (currentUser == null) return null;

    DocumentSnapshot doc = await _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .get();

    return doc.data() as Map<String, dynamic>?;
  }

  // Reset Password
  Future<String?> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; // Success
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to send reset email';
    }
  }
}