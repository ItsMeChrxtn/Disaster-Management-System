import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/domain.dart';
import '../core/ui.dart';

/// User administration (admin only).
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _search = '';
  String _roleFilter = '';
  String _statusFilter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMunicipalities();
  }

  Future<void> _load() async {
    try {
      final rows = rowsOf(await Api.instance.get('/users'));
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        Ui.toast(context, e.message, icon: 'error');
      }
    }
  }

  Future<void> _loadMunicipalities() async {
    try {
      final rows = rowsOf(await Api.instance.get('/municipalities/options'));
      if (mounted) setState(() => _municipalities = rows);
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filtered {
    final term = _search.trim().toLowerCase();
    return _rows.where((u) {
      if (_roleFilter.isNotEmpty && str(u, 'role') != _roleFilter) return false;
      if (_statusFilter.isNotEmpty && str(u, 'status') != _statusFilter) return false;
      if (term.isEmpty) return true;
      return [u['fullname'], u['email'], u['role'], u['municipality_name'], u['status'], u['barangay']].any((v) => (v ?? '').toString().toLowerCase().contains(term));
    }).toList();
  }

  Future<Map<String, dynamic>?> _fetch(int id) async {
    try {
      return mapOf(await Api.instance.get('/users/$id'));
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
      return null;
    }
  }

  Future<void> _view(int id) async {
    final item = await _fetch(id);
    if (item == null || !mounted) return;
    showDetailSheet(
      context,
      title: str(item, 'fullname'),
      kicker: 'User details',
      icon: Icons.person_outline,
      rows: [
        ('Email', str(item, 'email')),
        ('Phone', str(item, 'phone', '-')),
        ('Address', str(item, 'address', '-')),
        ('Municipality', str(item, 'municipality_name', '-')),
        ('Barangay', str(item, 'barangay', '-')),
        ('Role', str(item, 'role')),
        ('Status', str(item, 'status')),
      ],
    );
  }

  Future<void> _action(String action, Map<String, dynamic> row) async {
    final item = await _fetch(intOf(row, 'id'));
    if (item == null || !mounted) return;
    final name = str(item, 'fullname');
    try {
      switch (action) {
        case 'edit':
          await _openForm(item);
        case 'disable':
          if (!await Ui.confirm(context, 'Disable $name?', confirmText: 'Disable')) return;
          await Api.instance.put('/users/${item['id']}/disable', {});
          if (mounted) Ui.toast(context, 'User disabled');
          _load();
        case 'activate':
          if (!await Ui.confirm(context, 'Activate $name?', confirmText: 'Activate', danger: false)) return;
          await Api.instance.put('/users/${item['id']}/activate', {});
          if (mounted) Ui.toast(context, 'User activated');
          _load();
        case 'delete':
          if (!await Ui.confirm(context, 'Delete $name?', message: 'This account will no longer be usable.', confirmText: 'Delete')) return;
          await Api.instance.delete('/users/${item['id']}');
          if (mounted) Ui.toast(context, 'User deleted');
          _load();
      }
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _UserForm(item: item, municipalities: _municipalities),
    );
    if (result == null || !mounted) return;
    final temporary = result['temporary_password']?.toString();
    if (item == null && temporary != null && temporary.isNotEmpty) {
      final created = mapOf(result['user']);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, color: Ui.emerald, size: 40),
          title: const Text('User created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${str(created, 'fullname', 'User')}${str(created, 'email').isNotEmpty ? ' (${str(created, 'email')})' : ''} was created.'),
              const SizedBox(height: 10),
              const Text('Temporary password:'),
              const SizedBox(height: 4),
              SelectableText(temporary, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      );
    } else {
      Ui.toast(context, str(result, 'message', item == null ? 'User created' : 'User updated'));
    }
    _load();
  }

  Color _statusColor(String status) => switch (status) {
    'active' => Ui.emerald,
    'disabled' => Ui.amber,
    'deleted' => Ui.red,
    _ => Ui.slate500,
  };

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ModuleHeader(
            eyebrow: 'User administration',
            title: 'Users',
            subtitle: 'Manage roles, municipality assignments and account status for every system account.',
            icon: Icons.people_outline,
            actions: [
              BannerButton(label: 'Create user', icon: Icons.person_add_alt_1_outlined, onPressed: () => _openForm()),
              BannerButton(
                label: 'Export CSV',
                icon: Icons.download_outlined,
                primary: false,
                onPressed: rows.isEmpty
                    ? null
                    : () => Ui.exportCsv(context, 'users', [
                        'Name',
                        'Email',
                        'Role',
                        'Municipality',
                        'Barangay',
                        'Status',
                      ], rows.map((u) => [u['fullname'], u['email'], u['role'], u['municipality_name'], u['barangay'], u['status']]).toList()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchField(hint: 'Search name, email, municipality', onChanged: (v) => setState(() => _search = v)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _roleFilter,
                  decoration: fieldDecoration('Role'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All roles')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'subadmin', child: Text('Sub Admin')),
                    DropdownMenuItem(value: 'resident', child: Text('Resident')),
                  ],
                  onChanged: (v) => setState(() => _roleFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  decoration: fieldDecoration('Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All status')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
                    DropdownMenuItem(value: 'deleted', child: Text('Deleted')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? ''),
                ),
              ),
            ],
          ),
          ListHeading('Accounts', count: rows.length),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          if (!_loading && rows.isEmpty) const EmptyNote('No users found.'),
          ...rows.map((u) {
            final name = str(u, 'fullname');
            final status = str(u, 'status');
            final role = str(u, 'role');
            final initials = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).map((p) => p[0]).join().toUpperCase();
            return RecordCard(
              title: name,
              subtitle: str(u, 'email'),
              iconText: initials.length > 2 ? initials.substring(0, 2) : initials,
              accent: role == 'admin'
                  ? kGradViolet
                  : role == 'subadmin'
                  ? kGradSky
                  : kGradBlue,
              onTap: () => _view(intOf(u, 'id')),
              pills: [
                Pill(Ui.titleCase(role == 'subadmin' ? 'Sub Admin' : role), color: Ui.indigo),
                Pill(str(u, 'municipality_name', 'No municipality'), color: Ui.slate500),
                Pill(Ui.titleCase(status), color: _statusColor(status)),
              ],
              actions: [
                ActionIconButton(icon: Icons.visibility_outlined, tooltip: 'View user', color: Ui.sky, onPressed: () => _view(intOf(u, 'id'))),
                ActionIconButton(icon: Icons.edit_outlined, tooltip: 'Edit user', color: Ui.amber, onPressed: () => _action('edit', u)),
                if (status == 'active') ActionIconButton(icon: Icons.block, tooltip: 'Disable user', color: Ui.orange, onPressed: () => _action('disable', u)),
                if (status == 'disabled') ActionIconButton(icon: Icons.check, tooltip: 'Activate user', color: Ui.emerald, onPressed: () => _action('activate', u)),
                if (status != 'deleted') ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete user', color: Ui.red, onPressed: () => _action('delete', u)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _UserForm extends StatefulWidget {
  const _UserForm({this.item, required this.municipalities});

  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> municipalities;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _form = GlobalKey<FormState>();
  late final _fullname = TextEditingController(text: str(widget.item, 'fullname'));
  late final _email = TextEditingController(text: str(widget.item, 'email'));
  late final _phone = TextEditingController(text: str(widget.item, 'phone'));
  late final _address = TextEditingController(text: str(widget.item, 'address'));
  late final _barangay = TextEditingController(text: str(widget.item, 'barangay'));
  final _password = TextEditingController();
  late String _municipalityId = str(widget.item, 'municipality_id');
  late String _role = str(widget.item, 'role', 'resident');
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_fullname, _email, _phone, _address, _barangay, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {
      'fullname': _fullname.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'municipality_id': _municipalityId,
      'barangay': _barangay.text.trim(),
      'role': _role,
      'password': _password.text,
    };
    try {
      final result = widget.item != null ? await Api.instance.put('/users/${widget.item!['id']}', payload) : await Api.instance.post('/users', payload);
      if (mounted) Navigator.pop(context, mapOf(result));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.errors.isEmpty ? e.message : '${e.message}\n${e.errors.values.join('\n')}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    final municipalityItems = [
      const DropdownMenuItem(value: '', child: Text('No municipality')),
      ...widget.municipalities.map(
        (m) => DropdownMenuItem(
          value: str(m, 'id'),
          child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    if (_municipalityId.isNotEmpty && !municipalityItems.any((i) => i.value == _municipalityId)) {
      municipalityItems.add(DropdownMenuItem(value: _municipalityId, child: Text(str(widget.item, 'municipality_name', 'Municipality #$_municipalityId'))));
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(editing ? 'Edit user' : 'Create user', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const FieldLabel('Full name'),
              TextFormField(
                controller: _fullname,
                decoration: fieldDecoration('Full name'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the full name' : null,
                textCapitalization: TextCapitalization.words,
              ),
              const FieldLabel('Email'),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: fieldDecoration('Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
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
              const FieldLabel('Role'),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: fieldDecoration('Role'),
                items: const [
                  DropdownMenuItem(value: 'resident', child: Text('Resident')),
                  DropdownMenuItem(value: 'subadmin', child: Text('Sub Admin')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'resident'),
              ),
              const FieldLabel('Password'),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: fieldDecoration(
                  editing ? 'Leave blank to keep current password' : 'Auto-generated if left blank',
                  suffix: TextButton(onPressed: () => setState(() => _showPassword = !_showPassword), child: Text(_showPassword ? 'Hide' : 'Show')),
                ),
                validator: (v) => (v != null && v.isNotEmpty && v.length < 8) ? 'Password must be at least 8 characters' : null,
              ),
              const SizedBox(height: 6),
              Text(
                editing ? 'Leave password blank while editing to keep it unchanged.' : 'Leave password blank to auto-generate a temporary password.',
                style: const TextStyle(fontSize: 11.5, color: Ui.slate500),
              ),
              ErrorBanner(_error),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(onPressed: _busy ? null : _submit, child: const Text('Save user')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
