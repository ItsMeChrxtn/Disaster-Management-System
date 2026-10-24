import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/emailjs.dart';
import '../../core/ui.dart';
import 'auth_scaffold.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _email.text = widget.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _currentEmail => _email.text.trim();

  Future<void> _verify() async {
    if (_currentEmail.isEmpty) {
      Ui.showError(context, 'Enter your email address first.');
      return;
    }
    if (_code.text.length != 6) {
      Ui.showError(context, 'Please enter the full 6-digit code.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Ui.withLoading(context, 'Verifying…', () => Api.instance.post('/auth/verify-email', {'email': _currentEmail, 'code': _code.text}));
      if (!mounted) return;
      Ui.toast(context, str(result, 'message', 'Email verified successfully. You can now sign in.'));
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) await Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_currentEmail.isEmpty) {
      Ui.showError(context, 'Enter your email address first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Ui.withLoading(context, 'Sending a new code…', () async {
        final data = await Api.instance.post('/auth/resend-verification', {'email': _currentEmail});
        final verification = mapOf(data['verification']);
        final sent = await EmailJs.sendVerification(verification);
        return (verification: verification, sent: sent);
      });
      if (!mounted) return;
      await Ui.showSuccess(
        context,
        result.sent ? 'Code sent' : 'Code generated',
        result.sent ? 'Check ${str(result.verification, 'to_email')} for your new verification code.' : 'We generated a new code but could not email it automatically. Please try again shortly.',
      );
    } on ApiException catch (e) {
      if (mounted) await Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'Enter the 6-digit code we emailed you to activate your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.email == null || widget.email!.isEmpty) ...[
            const FieldLabel('Email'),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: fieldDecoration('you@example.com')),
          ] else
            Text('Code sent to ${widget.email}', style: const TextStyle(color: Ui.slate500)),
          const FieldLabel('Verification code'),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 14, fontWeight: FontWeight.w800),
            decoration: fieldDecoration('••••••'),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Verify email', onPressed: _busy ? null : _verify),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _resend, child: const Text('Resend code')),
        ],
      ),
    );
  }
}
