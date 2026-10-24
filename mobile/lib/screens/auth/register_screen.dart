import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/emailjs.dart';
import '../../core/ui.dart';
import 'auth_scaffold.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _fullname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _barangay = TextEditingController();
  final _password = TextEditingController();
  List<Map<String, dynamic>> _municipalities = [];
  String? _municipalityId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMunicipalities();
  }

  @override
  void dispose() {
    for (final c in [_fullname, _email, _phone, _address, _barangay, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMunicipalities() async {
    try {
      final rows = rowsOf(await Api.instance.get('/municipalities/options'));
      if (mounted) setState(() => _municipalities = rows);
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message, e.errors);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result = await Ui.withLoading(context, 'Creating resident account…', () async {
        final data = await Api.instance.post('/auth/register', {
          'fullname': _fullname.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'address': _address.text.trim(),
          'municipality_id': _municipalityId,
          'barangay': _barangay.text.trim(),
          'password': _password.text,
        });
        final verification = mapOf(data['verification']);
        final sent = await EmailJs.sendVerification(verification);
        return (verification: verification, sent: sent);
      });
      if (!mounted) return;
      final email = str(result.verification, 'to_email');
      Ui.toast(
        context,
        result.sent ? 'Registration complete. We sent a 6-digit code to $email.' : 'Registration complete, but the verification email could not be sent automatically. Use "Resend code".',
        icon: result.sent ? 'success' : 'warning',
      );
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: email)));
    } on ApiException catch (e) {
      if (mounted) await Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create resident account',
      subtitle: 'Register to receive municipality-targeted alerts and evacuation guidance.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Full name'),
            TextFormField(controller: _fullname, validator: (v) => requiredValidator(v, 'Full name'), decoration: fieldDecoration('Complete legal name'), textCapitalization: TextCapitalization.words),
            const FieldLabel('Email'),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, validator: emailValidator, decoration: fieldDecoration('you@example.com')),
            const FieldLabel('Phone'),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, validator: (v) => requiredValidator(v, 'Phone'), decoration: fieldDecoration('09XX XXX XXXX')),
            const FieldLabel('Address'),
            TextFormField(controller: _address, validator: (v) => requiredValidator(v, 'Address'), decoration: fieldDecoration('Street and subdivision')),
            const FieldLabel('Municipality'),
            DropdownButtonFormField<String>(
              initialValue: _municipalityId,
              isExpanded: true,
              decoration: fieldDecoration('Select municipality'),
              items: _municipalities.map((m) => DropdownMenuItem(value: str(m, 'id'), child: Text(str(m, 'municipality_name')))).toList(),
              validator: (v) => v == null ? 'Municipality is required' : null,
              onChanged: (v) => setState(() => _municipalityId = v),
            ),
            const FieldLabel('Barangay'),
            TextFormField(controller: _barangay, validator: (v) => requiredValidator(v, 'Barangay'), decoration: fieldDecoration('Barangay')),
            const FieldLabel('Password'),
            PasswordField(controller: _password, hint: 'At least 8 characters', validator: passwordValidator),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Create account', onPressed: _busy ? null : _submit),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already registered?', style: TextStyle(color: Ui.slate500)),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Sign in')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
