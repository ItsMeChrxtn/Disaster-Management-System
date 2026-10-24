import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/ui.dart';
import 'auth_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _token.text = widget.token ?? '';
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await Ui.withLoading(
        context,
        'Updating password…',
        () => Api.instance.post('/auth/reset-password', {'token': _token.text.trim(), 'password': _password.text, 'password_confirmation': _confirm.text}),
      );
      if (!mounted) return;
      Ui.toast(context, str(result, 'message', 'Password updated.'));
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) await Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset password',
      subtitle: 'Paste the reset token you received and choose a new password.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Reset token'),
            TextFormField(controller: _token, validator: (v) => requiredValidator(v, 'Reset token'), decoration: fieldDecoration('Reset token')),
            const FieldLabel('New password'),
            PasswordField(controller: _password, hint: 'At least 8 characters', validator: passwordValidator),
            const FieldLabel('Confirm new password'),
            PasswordField(controller: _confirm, hint: 'Repeat the new password', validator: (v) => v != _password.text ? 'Passwords do not match' : null),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Update password', onPressed: _busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}
