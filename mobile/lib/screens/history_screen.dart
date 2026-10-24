import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/domain.dart';
import '../core/session.dart';
import '../core/ui.dart';

/// Historical disaster records (admin CRUD, resident read-only).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _search = '';
  String _typeFilter = '';
  String _municipalityFilter = '';
  bool _loading = true;
  int _shown = 40;

  bool get _admin => Session.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMunicipalities();
  }

  Future<void> _load() async {
    try {
      final rows = rowsOf(await Api.instance.get('/historical-disasters'));
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
    return _rows.where((r) {
      if (_typeFilter.isNotEmpty && str(r, 'disaster_type') != _typeFilter) return false;
      if (_municipalityFilter.isNotEmpty && str(r, 'municipality_id') != _municipalityFilter) return false;
      if (term.isEmpty) return true;
      return [
        r['title'],
        r['disaster_type'],
        r['event_name'],
        r['affected_barangays'],
        r['description'],
        r['municipality_name'],
        r['date_occurred'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(term));
    }).toList();
  }

  Future<Map<String, dynamic>?> _fetch(int id) async {
    try {
      return mapOf(await Api.instance.get('/historical-disasters/$id'));
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message);
      return null;
    }
  }

  Future<void> _view(int id) async {
    final item = await _fetch(id);
    if (item == null || !mounted) return;
    showDetailSheet(
      context,
      title: str(item, 'title'),
      kicker: 'Historical disaster record',
      icon: Icons.history,
      color: Ui.violet,
      body: str(item, 'description', 'No description provided.'),
      rows: [
        ('Type', str(item, 'disaster_type')),
        ('Municipality', str(item, 'municipality_name', 'Province-wide')),
        ('Date', str(item, 'date_occurred')),
        if (str(item, 'event_name').isNotEmpty) ('Event', str(item, 'event_name')),
        ('Affected barangays', '${intOf(item, 'affected_barangay_count')}${_barangays(item).isEmpty ? ' (municipality-wide or not reported)' : '\n${_barangays(item).join(', ')}'}'),
        ('Casualties', NumberFormat.decimalPattern().format(intOf(item, 'casualties'))),
        ('Injured', NumberFormat.decimalPattern().format(intOf(item, 'injured'))),
        ('Evacuated families', NumberFormat.decimalPattern().format(intOf(item, 'evacuated_families'))),
        ('Est. damages', Ui.money.format(dbl(item, 'damages') ?? 0)),
        if (str(item, 'source').isNotEmpty) ('Source', str(item, 'source')),
      ],
    );
  }

  List<String> _barangays(Map<String, dynamic> item) => (item['barangay_list'] as List? ?? const []).map((b) => b.toString()).toList();

  Widget _summary(List<Map<String, dynamic>> rows) {
    int sum(String key) => rows.fold<int>(0, (t, r) => t + intOf(r, key));
    final events = rows.map((r) => str(r, 'event_name', str(r, 'title'))).toSet().length;
    Widget tile(String label, String value, String note, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ui.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: Ui.slate400),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              note,
              style: const TextStyle(fontSize: 11, color: Ui.slate500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            tile('Events', '$events', '${rows.length} records', Ui.indigo),
            const SizedBox(width: 8),
            tile('Barangays', NumberFormat.decimalPattern().format(sum('affected_barangay_count')), 'affected', Ui.violet),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            tile('Casualties', NumberFormat.decimalPattern().format(sum('casualties')), '${sum('injured')} injured', Ui.red),
            const SizedBox(width: 8),
            tile('Evacuated', NumberFormat.decimalPattern().format(sum('evacuated_families')), 'families', Ui.emerald),
          ],
        ),
      ],
    );
  }

  Future<void> _edit(int id) async {
    final item = await _fetch(id);
    if (item != null && mounted) _openForm(item);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!await Ui.confirm(context, 'Delete ${str(row, 'title')}?', message: 'This cannot be undone.', confirmText: 'Delete')) return;
    try {
      await Api.instance.delete('/historical-disasters/${row['id']}');
      if (mounted) Ui.toast(context, 'Historical record deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _HistoryForm(item: item, municipalities: _municipalities),
    );
    if (saved == true) {
      if (mounted) Ui.toast(context, item == null ? 'Historical record added' : 'Historical record updated');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final types = <String>{..._rows.map((r) => str(r, 'disaster_type'))}.where((t) => t.isNotEmpty).toList()..sort();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ModuleHeader(
            eyebrow: 'Historical archive',
            title: 'Historical disasters',
            subtitle: 'Recorded incidents, affected barangays, casualties and estimated damages across the province.',
            icon: Icons.history,
            actions: [
              if (_admin) BannerButton(label: 'Add record', icon: Icons.add, onPressed: () => _openForm()),
              if (_admin)
                BannerButton(
                  label: 'Export CSV',
                  icon: Icons.download_outlined,
                  primary: false,
                  onPressed: rows.isEmpty
                      ? null
                      : () => Ui.exportCsv(
                          context,
                          'historical-disasters',
                          ['Title', 'Type', 'Event', 'Municipality', 'Date', 'Affected barangays', 'Barangays', 'Casualties', 'Injured', 'Damages', 'Description'],
                          rows
                              .map(
                                (r) => [
                                  r['title'],
                                  r['disaster_type'],
                                  r['event_name'],
                                  r['municipality_name'],
                                  r['date_occurred'],
                                  r['affected_barangay_count'],
                                  _barangays(r).join('; '),
                                  r['casualties'],
                                  r['injured'],
                                  r['damages'],
                                  r['description'],
                                ],
                              )
                              .toList(),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_loading) ...[_summary(rows), const SizedBox(height: 12)],
          SearchField(hint: 'Search records', onChanged: (v) => setState(() => _search = v)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _typeFilter,
                  isExpanded: true,
                  decoration: fieldDecoration('Type'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All types')),
                    ...types.map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(t, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _typeFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _municipalityFilter,
                  isExpanded: true,
                  decoration: fieldDecoration('Municipality'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All municipalities')),
                    ..._municipalities.map(
                      (m) => DropdownMenuItem(
                        value: str(m, 'id'),
                        child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _municipalityFilter = v ?? ''),
                ),
              ),
            ],
          ),
          ListHeading('Records', count: rows.length),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          if (!_loading && rows.isEmpty) const EmptyNote('No historical disaster records found.'),
          ...rows.take(_shown).map((r) {
            final type = str(r, 'disaster_type');
            return RecordCard(
              title: str(r, 'title'),
              subtitle: str(r, 'description', 'No description'),
              iconText: type.length >= 2 ? type.substring(0, 2).toUpperCase() : 'DR',
              accent: kGradViolet,
              onTap: () => _view(intOf(r, 'id')),
              body: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    _stat('Barangays', intOf(r, 'affected_barangay_count').toString(), Ui.violet),
                    const SizedBox(width: 8),
                    _stat('Casualties', '${intOf(r, 'casualties')}${intOf(r, 'injured') > 0 ? ' · ${intOf(r, 'injured')} inj.' : ''}', Ui.red),
                    const SizedBox(width: 8),
                    _stat('Damages', '₱${Ui.money.format(dbl(r, 'damages') ?? 0)}', Ui.amber),
                  ],
                ),
              ),
              pills: [
                Pill(type, color: Ui.violet),
                Pill(str(r, 'municipality_name', 'Province-wide'), color: Ui.slate500),
                Pill(str(r, 'date_occurred'), color: Ui.sky),
              ],
              actions: [
                ActionIconButton(icon: Icons.visibility_outlined, tooltip: 'View record', color: Ui.sky, onPressed: () => _view(intOf(r, 'id'))),
                if (_admin) ...[
                  ActionIconButton(icon: Icons.edit_outlined, tooltip: 'Edit record', color: Ui.amber, onPressed: () => _edit(intOf(r, 'id'))),
                  ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete record', color: Ui.red, onPressed: () => _delete(r)),
                ],
              ],
            );
          }),
          if (rows.length > _shown)
            OutlinedButton.icon(onPressed: () => setState(() => _shown += 40), icon: const Icon(Icons.expand_more), label: Text('Show more (${rows.length - _shown} remaining)')),
        ],
      ),
    );
  }
}

Widget _stat(String label, String value, Color color) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Ui.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: Ui.slate400),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

class _HistoryForm extends StatefulWidget {
  const _HistoryForm({this.item, required this.municipalities});

  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> municipalities;

  @override
  State<_HistoryForm> createState() => _HistoryFormState();
}

class _HistoryFormState extends State<_HistoryForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: str(widget.item, 'title'));
  late final _date = TextEditingController(text: str(widget.item, 'date_occurred'));
  late final _casualties = TextEditingController(text: str(widget.item, 'casualties', '0'));
  late final _damages = TextEditingController(text: str(widget.item, 'damages', '0'));
  late final _description = TextEditingController(text: str(widget.item, 'description'));
  late final _event = TextEditingController(text: str(widget.item, 'event_name'));
  late final _injured = TextEditingController(text: str(widget.item, 'injured', '0'));
  late final _families = TextEditingController(text: str(widget.item, 'evacuated_families', '0'));
  late final _barangays = TextEditingController(text: (widget.item?['barangay_list'] as List? ?? const []).join('\n'));
  late final _source = TextEditingController(text: str(widget.item, 'source'));
  late String _type = str(widget.item, 'disaster_type');
  late String _municipalityId = str(widget.item, 'municipality_id');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _date, _casualties, _damages, _description, _event, _injured, _families, _barangays, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_date.text) ?? now;
    final picked = await showDatePicker(context: context, initialDate: initial.isAfter(now) ? now : initial, firstDate: DateTime(1900), lastDate: now);
    if (picked != null) setState(() => _date.text = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {
      'title': _title.text.trim(),
      'disaster_type': _type,
      'municipality_id': _municipalityId,
      'date_occurred': _date.text,
      'casualties': _casualties.text.trim(),
      'damages': _damages.text.trim(),
      'description': _description.text.trim(),
      'event_name': _event.text.trim(),
      'injured': _injured.text.trim(),
      'evacuated_families': _families.text.trim(),
      'affected_barangays': _barangays.text,
      'source': _source.text.trim(),
    };
    try {
      if (widget.item != null) {
        await Api.instance.put('/historical-disasters/${widget.item!['id']}', payload);
      } else {
        await Api.instance.post('/historical-disasters', payload);
      }
      if (mounted) Navigator.pop(context, true);
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
    final types = [...Domain.disasterTypes];
    if (_type.isNotEmpty && !types.contains(_type)) types.add(_type);
    final municipalityItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Province-wide (all of Cavite)')),
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
              Text(widget.item == null ? 'Add historical record' : 'Edit historical record', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const FieldLabel('Record title'),
              TextFormField(controller: _title, decoration: fieldDecoration('e.g. Barangay flood event'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a record title' : null),
              const FieldLabel('Disaster type'),
              DropdownButtonFormField<String>(
                initialValue: _type.isEmpty ? null : _type,
                isExpanded: true,
                decoration: fieldDecoration('Select disaster type'),
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                validator: (v) => v == null ? 'Select a disaster type' : null,
                onChanged: (v) => setState(() => _type = v ?? ''),
              ),
              const FieldLabel('Municipality'),
              DropdownButtonFormField<String>(
                initialValue: _municipalityId,
                isExpanded: true,
                decoration: fieldDecoration('Select municipality'),
                items: municipalityItems,
                onChanged: (v) => setState(() => _municipalityId = v ?? ''),
              ),
              const FieldLabel('Date occurred'),
              TextFormField(
                controller: _date,
                readOnly: true,
                onTap: _pickDate,
                decoration: fieldDecoration('YYYY-MM-DD', suffix: const Icon(Icons.calendar_today_outlined, size: 18)),
                validator: (v) => (v == null || v.isEmpty) ? 'Select the date' : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Casualties'),
                        TextFormField(
                          controller: _casualties,
                          keyboardType: TextInputType.number,
                          decoration: fieldDecoration('0'),
                          validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Enter a number' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Estimated damages'),
                        TextFormField(
                          controller: _damages,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: fieldDecoration('0.00'),
                          validator: (v) => (double.tryParse(v ?? '') ?? -1) < 0 ? 'Enter an amount' : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const FieldLabel('Event / typhoon name'),
              TextFormField(
                controller: _event,
                maxLength: 160,
                decoration: fieldDecoration('e.g. Typhoon "Carina" (2024)').copyWith(counterText: ''),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Injured'),
                        TextFormField(controller: _injured, keyboardType: TextInputType.number, decoration: fieldDecoration('0')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Evacuated families'),
                        TextFormField(controller: _families, keyboardType: TextInputType.number, decoration: fieldDecoration('0')),
                      ],
                    ),
                  ),
                ],
              ),
              const FieldLabel('Affected barangays (one per line)'),
              TextFormField(controller: _barangays, maxLines: 4, decoration: fieldDecoration('Bancaan\nLabac\nMabulo')),
              const FieldLabel('Source'),
              TextFormField(
                controller: _source,
                maxLength: 255,
                decoration: fieldDecoration('e.g. PDRRMO SitRep 15').copyWith(counterText: ''),
              ),
              const FieldLabel('Description'),
              TextFormField(controller: _description, maxLines: 4, maxLength: 5000, decoration: fieldDecoration('Briefly describe the impact, affected areas, and response notes.')),
              ErrorBanner(_error),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(onPressed: _busy ? null : _submit, child: const Text('Save record')),
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
