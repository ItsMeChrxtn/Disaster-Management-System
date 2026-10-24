import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/ui.dart';
import 'auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await Ui.withLoading(context, 'Signing you in...', () => Session.instance.login(_email.text.trim(), _password.text));
      if (!mounted) return;
      final mustChange = (user['password_must_change'] ?? '0').toString() == '1';
      Ui.toast(context, mustChange ? 'Please change your temporary password.' : 'Welcome, ${user['fullname']}.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) await Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Residents, MDRRMO sub admins, and PDRRMO admins use the same sign-in.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Email'),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, validator: emailValidator, decoration: fieldDecoration('name@example.gov.ph')),
            const FieldLabel('Password'),
            PasswordField(controller: _password, hint: 'Enter your password', validator: (v) => requiredValidator(v, 'Password'), textInputAction: TextInputAction.done),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.of(context).pushNamed('/forgot-password'), child: const Text('Forgot password?')),
            ),
            PrimaryButton(label: 'Sign in', onPressed: _busy ? null : _submit),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account?", style: TextStyle(color: Ui.slate500)),
                TextButton(onPressed: () => Navigator.of(context).pushNamed('/register'), child: const Text('Register')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
