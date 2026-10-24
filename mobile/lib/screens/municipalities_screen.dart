import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/domain.dart';
import '../core/ui.dart';

/// Municipality registry (admin only).
class MunicipalitiesScreen extends StatefulWidget {
  const MunicipalitiesScreen({super.key, this.onOpenCoordination});

  /// Opens the PDRRMO <-> MDRRMO/CDRRMO coordination module.
  final VoidCallback? onOpenCoordination;

  @override
  State<MunicipalitiesScreen> createState() => _MunicipalitiesScreenState();
}

class _MunicipalitiesScreenState extends State<MunicipalitiesScreen> {
  List<Map<String, dynamic>> _rows = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = rowsOf(await Api.instance.get('/municipalities'));
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

  List<Map<String, dynamic>> get _filtered {
    final term = _search.trim().toLowerCase();
    if (term.isEmpty) return _rows;
    return _rows.where((m) => [m['municipality_name'], m['description'], m['status']].any((v) => (v ?? '').toString().toLowerCase().contains(term))).toList();
  }

  Future<void> _view(int id) async {
    try {
      final item = mapOf(await Api.instance.get('/municipalities/$id'));
      if (!mounted) return;
      final status = str(item, 'status', 'inactive');
      showDetailSheet(
        context,
        title: str(item, 'municipality_name', 'Unnamed municipality'),
        kicker: 'Municipality details',
        icon: Icons.location_city_outlined,
        color: status == 'active' ? Ui.emerald : Ui.slate500,
        rows: [
          ('Status', status),
          ('Description', str(item, 'description', 'No description provided')),
          ('Created', Ui.formatDateTime(item['created_at'])),
          ('Last updated', Ui.formatDateTime(item['updated_at'])),
        ],
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openForm(item);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        ],
      );
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _edit(int id) async {
    try {
      final item = mapOf(await Ui.withLoading(context, 'Loading municipality...', () => Api.instance.get('/municipalities/$id')));
      if (mounted) _openForm(item);
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (!await Ui.confirm(context, 'Delete ${str(item, 'municipality_name')}?', message: 'This cannot be undone.', confirmText: 'Delete')) return;
    try {
      await Api.instance.delete('/municipalities/${item['id']}');
      if (!mounted) return;
      Ui.toast(context, 'Municipality deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MunicipalityForm(item: item),
    );
    if (saved == true) {
      if (mounted) Ui.toast(context, item == null ? 'Municipality added' : 'Municipality updated');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ModuleHeader(
            eyebrow: 'Municipal registry',
            title: 'Municipalities',
            subtitle: 'Maintain the jurisdiction directory, coverage notes and availability of every municipality and city.',
            icon: Icons.location_city_outlined,
            actions: [
              BannerButton(label: 'Add municipality', icon: Icons.add, onPressed: () => _openForm()),
              if (widget.onOpenCoordination != null) BannerButton(label: 'Alert / message LGUs', icon: Icons.forum_outlined, primary: false, onPressed: widget.onOpenCoordination),
              BannerButton(
                label: 'Export CSV',
                icon: Icons.download_outlined,
                primary: false,
                onPressed: rows.isEmpty
                    ? null
                    : () => Ui.exportCsv(context, 'municipalities', ['Municipality', 'Description', 'Status'], rows.map((m) => [m['municipality_name'], m['description'], m['status']]).toList()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchField(hint: 'Search municipalities', onChanged: (v) => setState(() => _search = v)),
          ListHeading('Records', count: rows.length),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          if (!_loading && rows.isEmpty) const EmptyNote('No municipalities found.'),
          ...rows.map((m) {
            final status = str(m, 'status', 'inactive');
            return RecordCard(
              title: str(m, 'municipality_name'),
              subtitle: str(m, 'description', 'No operational notes recorded.'),
              icon: Icons.location_city_outlined,
              accent: status == 'active' ? kGradBlue : const [Color(0xFF94A3B8), Color(0xFF64748B)],
              onTap: () => _view(intOf(m, 'id')),
              pills: [
                Pill(status == 'active' ? 'Active' : 'Inactive', color: status == 'active' ? Ui.emerald : Ui.slate500),
                const Pill('Municipal jurisdiction', color: Ui.slate500),
              ],
              actions: [
                ActionIconButton(icon: Icons.visibility_outlined, tooltip: 'View municipality', color: Ui.sky, onPressed: () => _view(intOf(m, 'id'))),
                ActionIconButton(icon: Icons.edit_outlined, tooltip: 'Edit municipality', color: Ui.amber, onPressed: () => _edit(intOf(m, 'id'))),
                ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete municipality', color: Ui.red, onPressed: () => _delete(m)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _MunicipalityForm extends StatefulWidget {
  const _MunicipalityForm({this.item});

  final Map<String, dynamic>? item;

  @override
  State<_MunicipalityForm> createState() => _MunicipalityFormState();
}

class _MunicipalityFormState extends State<_MunicipalityForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: str(widget.item, 'municipality_name'));
  late final TextEditingController _description = TextEditingController(text: str(widget.item, 'description'));
  late String _status = str(widget.item, 'status', 'active');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {'municipality_name': _name.text.trim(), 'description': _description.text.trim(), 'status': _status};
    try {
      if (widget.item != null) {
        await Api.instance.put('/municipalities/${widget.item!['id']}', payload);
      } else {
        await Api.instance.post('/municipalities', payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.item == null ? 'Add municipality' : 'Edit municipality', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Text('Keep municipal coverage, status, and operational notes current.', style: TextStyle(fontSize: 12.5, color: Ui.slate500)),
              const FieldLabel('Municipality name'),
              TextFormField(
                controller: _name,
                decoration: fieldDecoration('Enter municipality name'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter at least 2 characters' : null,
                textCapitalization: TextCapitalization.words,
              ),
              const FieldLabel('Description'),
              TextFormField(controller: _description, maxLines: 4, maxLength: 2000, decoration: fieldDecoration('Add coverage notes, key areas, or administrative context')),
              const FieldLabel('Status'),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: fieldDecoration('Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'active'),
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
                    child: FilledButton(onPressed: _busy ? null : _submit, child: const Text('Save municipality')),
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
