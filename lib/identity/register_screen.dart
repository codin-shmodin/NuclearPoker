import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';

/// First-run register screen: a username and a password, no restrictions on
/// either. Submitting saves the account (see [AccountStore]) and signs you in.
/// Type **admin** as the username to unlock everything.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onSubmit});

  /// Called with the entered username + password (username non-empty).
  final void Function(String username, String password) onSubmit;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _username.text.trim();
    if (name.isEmpty) return;
    widget.onSubmit(name, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundTop, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('☢️', style: TextStyle(fontSize: 34)),
                          SizedBox(width: 10),
                          Text(
                            'NUCLEAR',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: AppColors.goldBright,
                            ),
                          ),
                          Text(
                            'POKER',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create an account to save your progress.',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                      const SizedBox(height: 28),
                      _field(_username, 'Username', autofocus: true),
                      const SizedBox(height: 12),
                      _field(_password, 'Password', obscure: true, onGo: true),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.goldDeep,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _submit,
                          child: const Text('Register & Play',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ).animate().fadeIn(duration: 400.ms),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool obscure = false, bool autofocus = false, bool onGo = false}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      obscureText: obscure,
      textInputAction: onGo ? TextInputAction.go : TextInputAction.next,
      onSubmitted: onGo ? (_) => _submit() : null,
      style: const TextStyle(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.feltDark.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
