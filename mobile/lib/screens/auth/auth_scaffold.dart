import 'package:flutter/material.dart';

import '../../core/ui.dart';

/// Shared card layout for the login/register/verify/forgot/reset pages.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child, this.kicker = 'Disaster Map'});

  final String title;
  final String subtitle;
  final String kicker;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.slate100,
      body: Stack(
        children: [
          Container(
            height: 300,
            decoration: const BoxDecoration(gradient: kNavyGradient),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: .25,
                    child: Image.asset('assets/img/hero.jpg', fit: BoxFit.cover, cacheWidth: 1080, filterQuality: FilterQuality.low),
                  ),
                ),
                const Positioned.fill(child: GridOverlay(opacity: .05)),
              ],
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(10),
                          child: const SizedBox(width: 38, height: 38, child: Icon(Icons.arrow_back, color: Colors.white, size: 20)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 42, onDark: true)),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -.7),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: Color(0xFFCBD5E1), height: 1.5)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Ui.line),
                      boxShadow: const [BoxShadow(color: Color(0x590F172A), blurRadius: 40, offset: Offset(0, 22), spreadRadius: -18)],
                    ),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, required this.hint, this.validator, this.textInputAction});

  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      decoration: fieldDecoration(
        widget.hint,
        suffix: TextButton(onPressed: () => setState(() => _visible = !_visible), child: Text(_visible ? 'Hide' : 'Show')),
      ),
    );
  }
}

String? requiredValidator(String? value, [String label = 'This field']) => (value == null || value.trim().isEmpty) ? '$label is required' : null;

String? emailValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'Email is required';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

String? passwordValidator(String? value) {
  if (value == null || value.isEmpty) return 'Password is required';
  if (value.length < 8) return 'Password must be at least 8 characters';
  return null;
}
