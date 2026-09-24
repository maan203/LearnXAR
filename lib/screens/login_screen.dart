import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'main_scaffold.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  LoginState createState() => LoginState();
}

class LoginState extends State<Login> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool obscurePassword = true;
  bool isLoading = false;

  Future<void> _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showSnackBar('Please fill all fields');
      return;
    }

    setState(() {
      isLoading = true;
    });

    // Call Firebase Auth
    String? error = await _authService.signIn(
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
      // Success - navigate to home
      if (!mounted) return;
      _showSnackBar('Successfully logged in!');

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScaffold()),
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
                  const SizedBox(height: 40),
                  const Text(
                    "LearnXAR",
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Experience Data Structures in\nAugmented Reality",
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 15,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFFF7F7F7),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          "Welcome Back",
                          style: TextStyle(
                            color: Color(0xFF6A53E7),
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Sign in to continue your AR learning journey",
                          style: TextStyle(
                            color: Color(0xFFA0A5AE),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Email",
                            style: TextStyle(
                              color: Color(0xFF1E1E1E),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildInputField(
                          controller: emailController,
                          hint: "Enter your email",
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Password",
                            style: TextStyle(
                              color: Color(0xFF1E1E1E),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 28),
                        InkWell(
                          onTap: isLoading ? null : _handleLogin,
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                                "Sign In",
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        InkWell(
                          onTap: isLoading
                              ? null
                              : () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (context) => const SignUp()),
                            );
                          },
                          child: const Text(
                            "Don't have an account? Sign up",
                            style: TextStyle(
                              color: Color(0xFF4044C8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
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
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFFAFAFA),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF9E9E9E),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              enabled: !isLoading,
              style: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFFAFAFA),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF9E9E9E),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              enabled: !isLoading,
              style: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          InkWell(
            onTap: isLoading ? null : onToggle,
            child: Icon(
              obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFF9E9E9E),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}