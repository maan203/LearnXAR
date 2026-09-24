import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  SignUpState createState() => SignUpState();
}

class SignUpState extends State<SignUp> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool isLoading = false;

  Future<void> _handleSignUp() async {
    if (nameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      _showSnackBar('Please fill all fields');
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      _showSnackBar('Passwords do not match');
      return;
    }

    if (passwordController.text.length < 6) {
      _showSnackBar('Password must be at least 6 characters');
      return;
    }

    setState(() {
      isLoading = true;
    });

    // Call Firebase Auth
    String? error = await _authService.signUp(
      name: nameController.text.trim(),
      email: emailController.text.trim(),
      password: passwordController.text,
    );

    setState(() {
      isLoading = false;
    });

    if (error != null) {
      // Show error
      _showSnackBar(error);
    } else {
      // Success - navigate to login
      if (!mounted) return;
      _showSnackBar('Account created successfully!');

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const Login()),
        );
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF482AD9),
              Color(0xFF26A38B),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    "LearnXAR",
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Start your AR learning adventure",
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFFF7F7F7),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          "Join LearnXAR",
                          style: TextStyle(
                            color: Color(0xFF6A53E7),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Sign up to start learning",
                          style: TextStyle(
                            color: Color(0xFFA0A5AE),
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Full Name",
                            style: TextStyle(
                              color: Color(0xFF1E1E1E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildInputField(
                          controller: nameController,
                          hint: "Enter your full name",
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Email",
                            style: TextStyle(
                              color: Color(0xFF1E1E1E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildInputField(
                          controller: emailController,
                          hint: "Enter your email",
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Password",
                            style: TextStyle(
                              color: Color(0xFF1E1E1E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildPasswordField(
                          controller: passwordController,
                          hint: "Enter your password",
                          icon: Icons.lock_outline,
                          obscureText: obscurePassword,
                          onToggle: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Confirm Password",
                            style: TextStyle(
                              color: Color(0xFF1E1E1E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildPasswordField(
                          controller: confirmPasswordController,
                          hint: "Confirm your password",
                          icon: Icons.lock_outline,
                          obscureText: obscureConfirmPassword,
                          onToggle: () {
                            setState(() {
                              obscureConfirmPassword = !obscureConfirmPassword;
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        InkWell(
                          onTap: isLoading ? null : _handleSignUp,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isLoading
                                    ? [
                                  const Color(0xFF4044C8).withOpacity(0.6),
                                  const Color(0xFF6A53E7).withOpacity(0.6),
                                ]
                                    : [
                                  const Color(0xFF4044C8),
                                  const Color(0xFF6A53E7),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: isLoading
                                  ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                                  : const Text(
                                "Sign Up",
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: isLoading
                              ? null
                              : () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => const Login()),
                            );
                          },
                          child: const Text(
                            "Already have an account? Sign in",
                            style: TextStyle(
                              color: Color(0xFF4044C8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFE0E0E0),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFAFAFA),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF9E9E9E),
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              enabled: !isLoading,
              style: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 12,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFE0E0E0),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFAFAFA),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF9E9E9E),
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              enabled: !isLoading,
              style: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 12,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          InkWell(
            onTap: isLoading ? null : onToggle,
            child: Icon(
              obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFF9E9E9E),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
}