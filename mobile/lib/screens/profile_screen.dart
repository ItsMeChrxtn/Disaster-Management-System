import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/ui.dart';
import 'auth/auth_scaffold.dart';

/// Profile & security (profileForm + passwordForm in dashboard.js).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  final _fullname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _barangay = TextEditingController();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  List<Map<String, dynamic>> _municipalities = [];
  String _municipalityId = '';
  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_fullname, _email, _phone, _address, _barangay, _currentPassword, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([Api.instance.get('/auth/me'), Api.instance.get('/municipalities/options').catchError((_) => <dynamic>[])]);
      final me = mapOf(results[0]);
      if (!mounted) return;
      setState(() {
        _fullname.text = str(me, 'fullname');
        _email.text = str(me, 'email');
        _phone.text = str(me, 'phone');
        _address.text = str(me, 'address');
        _barangay.text = str(me, 'barangay');
        _municipalityId = str(me, 'municipality_id');
        _municipalities = rowsOf(results[1]);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        Ui.toast(context, e.message, icon: 'error');
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_profileForm.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    try {
      final updated = mapOf(
        await Api.instance.put('/auth/profile', {
          'fullname': _fullname.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'address': _address.text.trim(),
          'municipality_id': _municipalityId,
          'barangay': _barangay.text.trim(),
        }),
      );
      // Keep flags the profile endpoint does not echo back.
      final merged = {...?Session.instance.user, ...updated};
      await Session.instance.updateUser(merged);
      if (mounted) Ui.toast(context, 'Profile updated');
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordForm.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    try {
      final result = mapOf(await Api.instance.put('/auth/change-password', {'current_password': _currentPassword.text, 'password': _password.text, 'password_confirmation': _confirm.text}));
      _currentPassword.clear();
      _password.clear();
      _confirm.clear();
      await Session.instance.clearPasswordMustChange();
      if (mounted) Ui.toast(context, str(result, 'message', 'Password changed successfully'));
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final municipalityItems = [
      const DropdownMenuItem(value: '', child: Text('No municipality')),
      ..._municipalities.map(
        (m) => DropdownMenuItem(
          value: str(m, 'id'),
          child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    if (_municipalityId.isNotEmpty && !municipalityItems.any((i) => i.value == _municipalityId)) {
      municipalityItems.add(DropdownMenuItem(value: _municipalityId, child: Text('Municipality #$_municipalityId')));
    }
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ModuleHeader(eyebrow: 'Security profile', title: 'Profile & security', subtitle: 'Keep your contact details current and rotate your password regularly.', icon: Icons.person_outline),
          if (Session.instance.mustChangePassword)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Ui.amber),
              ),
              child: const Text('You are using a temporary password. Change it below before continuing.', style: TextStyle(color: Color(0xFF78350F), fontSize: 13)),
            ),
          const SizedBox(height: 16),
          SectionCard(
            child: Form(
              key: _profileForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Profile details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const FieldLabel('Full name'),
                  TextFormField(controller: _fullname, decoration: fieldDecoration('Full name'), validator: (v) => requiredValidator(v, 'Full name')),
                  const FieldLabel('Email'),
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: fieldDecoration('Email'), validator: emailValidator),
                  const FieldLabel('Phone'),
                  TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: fieldDecoration('Phone')),
                  const FieldLabel('Address'),
                  TextFormField(controller: _address, decoration: fieldDecoration('Address')),
                  const FieldLabel('Municipality'),
                  DropdownButtonFormField<String>(
                    initialValue: _municipalityId,
                    isExpanded: true,
                    decoration: fieldDecoration('Municipality'),
                    items: municipalityItems,
                    onChanged: (v) => setState(() => _municipalityId = v ?? ''),
                  ),
                  const FieldLabel('Barangay'),
                  TextFormField(controller: _barangay, decoration: fieldDecoration('Barangay')),
                  const SizedBox(height: 16),
                  PrimaryButton(label: 'Update profile', icon: Icons.save_outlined, onPressed: _savingProfile ? null : _saveProfile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Form(
              key: _passwordForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Change password', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const FieldLabel('Current password'),
                  PasswordField(controller: _currentPassword, hint: 'Current password', validator: (v) => requiredValidator(v, 'Current password')),
                  const FieldLabel('New password'),
                  PasswordField(controller: _password, hint: 'New password', validator: passwordValidator),
                  const FieldLabel('Confirm new password'),
                  PasswordField(controller: _confirm, hint: 'Confirm new password', validator: (v) => v != _password.text ? 'Passwords do not match' : null),
                  const SizedBox(height: 16),
                  PrimaryButton(label: 'Change password', icon: Icons.lock_outline, onPressed: _savingPassword ? null : _changePassword),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
