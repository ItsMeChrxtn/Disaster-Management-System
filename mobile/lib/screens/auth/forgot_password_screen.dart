import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/ui.dart';
import 'auth_scaffold.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _debugToken;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await Ui.withLoading(context, 'Requesting secure reset…', () => Api.instance.post('/auth/forgot-password', {'email': _email.text.trim()}));
      if (!mounted) return;
      setState(() => _debugToken = result['debug_reset_token']?.toString());
      await Ui.showSuccess(context, 'Request received', str(result, 'message'));
    } on ApiException catch (e) {
      if (mounted) await Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Forgot password',
      subtitle: 'Enter your account email to request a password reset token.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Email'),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, validator: emailValidator, decoration: fieldDecoration('you@example.com')),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Request reset', onPressed: _busy ? null : _submit),
            if (_debugToken != null) ...[const SizedBox(height: 12), SelectableText('Development reset token: $_debugToken', style: const TextStyle(fontSize: 12, color: Ui.slate500))],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: _debugToken))),
              child: const Text('I already have a reset token'),
            ),
          ],
        ),
      ),
    );
  }
}
