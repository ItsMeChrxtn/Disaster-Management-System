import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/domain.dart';
import '../core/notifications.dart';
import '../core/session.dart';
import '../core/ui.dart';

/// Alert center: manager CRUD + send, resident history + read receipts.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _search = '';
  String _municipalityFilter = '';
  String _typeFilter = '';
  String _levelFilter = '';
  String _statusFilter = '';
  bool _loading = true;

  bool get _manager => Session.instance.isManager;

  @override
  void initState() {
    super.initState();
    _load();
    if (Session.instance.isAdmin) _loadMunicipalities();
  }

  Future<void> _load() async {
    try {
      final rows = rowsOf(await Api.instance.get(_manager ? '/alerts/manage' : '/notifications/history'));
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
      if (!_manager) AlertNotifier.instance.refresh();
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

  String _statusOf(Map<String, dynamic> a) => _manager ? str(a, 'status') : (isRead(a) ? 'read' : 'unread');

  List<Map<String, dynamic>> get _filtered {
    final term = _search.trim().toLowerCase();
    return _rows.where((a) {
      final municipality = str(a, 'municipality_name', 'Province-wide');
      if (_municipalityFilter.isNotEmpty && municipality.toLowerCase() != _municipalityFilter.toLowerCase()) return false;
      if (_typeFilter.isNotEmpty && str(a, 'alert_type') != _typeFilter) return false;
      if (_levelFilter.isNotEmpty && str(a, 'alert_level') != _levelFilter) return false;
      if (_statusFilter.isNotEmpty && _statusOf(a) != _statusFilter) return false;
      if (term.isEmpty) return true;
      return [a['title'], a['message'], a['alert_type'], a['alert_level'], municipality].any((v) => (v ?? '').toString().toLowerCase().contains(term));
    }).toList();
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AlertForm(item: item, municipalities: _municipalities),
    );
    if (saved == true) {
      if (mounted) Ui.toast(context, item == null ? 'Alert draft created' : 'Alert updated');
      _load();
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    try {
      final item = mapOf(await Api.instance.get('/alerts/${row['id']}'));
      if (mounted) _openForm(item);
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _send(Map<String, dynamic> item) async {
    if (!await Ui.confirm(context, 'Send ${str(item, 'title')} now?', message: 'Residents in scope will be notified immediately.', confirmText: 'Send', danger: false)) return;
    try {
      if (!mounted) return;
      await Ui.withLoading(context, 'Sending alert...', () => Api.instance.post('/alerts/${item['id']}/send', {}));
      if (mounted) Ui.toast(context, 'Alert sent');
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (!await Ui.confirm(context, 'Delete ${str(item, 'title')}?', confirmText: 'Delete')) return;
    try {
      await Api.instance.delete('/alerts/${item['id']}');
      if (mounted) Ui.toast(context, 'Alert deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    try {
      await Api.instance.post('/notifications/${item['id']}/read', {});
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Color _statusColor(String status) => switch (status) {
    'sent' || 'read' => Ui.emerald,
    'draft' => Ui.amber,
    'unread' => Ui.red,
    _ => Ui.slate500,
  };

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final municipalityNames = <String>{
      'Province-wide',
      ..._rows.map((a) => str(a, 'municipality_name', 'Province-wide')),
      ..._municipalities.map((m) => str(m, 'municipality_name')),
    }.where((n) => n.isNotEmpty).toList()..sort();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ModuleHeader(
            eyebrow: _manager ? 'Alert command' : 'Notifications',
            title: _manager ? 'Alerts & advisories' : 'My alerts',
            subtitle: _manager ? 'Draft, target and publish emergency advisories to residents and partner offices.' : 'Emergency advisories for your municipality and province-wide bulletins.',
            icon: Icons.campaign_outlined,
            actions: [
              if (_manager) BannerButton(label: 'Create alert', icon: Icons.add_alert_outlined, onPressed: () => _openForm()),
              BannerButton(
                label: 'Export CSV',
                icon: Icons.download_outlined,
                primary: false,
                onPressed: rows.isEmpty
                    ? null
                    : () => Ui.exportCsv(
                        context,
                        'alerts',
                        ['Title', 'Message', 'Type', 'Level', 'Municipality', 'Status', 'Date'],
                        rows
                            .map((a) => [a['title'], a['message'], a['alert_type'], a['alert_level'], str(a, 'municipality_name', 'Province-wide'), _statusOf(a), a['sent_at'] ?? a['created_at']])
                            .toList(),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchField(hint: 'Search alerts', onChanged: (v) => setState(() => _search = v)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _municipalityFilter,
                  isExpanded: true,
                  decoration: fieldDecoration('Municipality'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All municipality')),
                    ...municipalityNames.map(
                      (n) => DropdownMenuItem(
                        value: n,
                        child: Text(n, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _municipalityFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _typeFilter,
                  isExpanded: true,
                  decoration: fieldDecoration('Type'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All type')),
                    ...Domain.alertTypes.entries.map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _typeFilter = v ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _levelFilter,
                  isExpanded: true,
                  decoration: fieldDecoration('Level'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All level')),
                    ...Domain.alertLevels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                  ],
                  onChanged: (v) => setState(() => _levelFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  isExpanded: true,
                  decoration: fieldDecoration('Status'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All status')),
                    if (_manager) ...const [DropdownMenuItem(value: 'draft', child: Text('Draft')), DropdownMenuItem(value: 'sent', child: Text('Sent'))],
                    if (!_manager) ...const [DropdownMenuItem(value: 'unread', child: Text('Unread')), DropdownMenuItem(value: 'read', child: Text('Read'))],
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? ''),
                ),
              ),
            ],
          ),
          ListHeading('Alerts', count: rows.length),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          if (!_loading && rows.isEmpty) const EmptyNote('No alerts found.'),
          ...rows.map((a) {
            final level = str(a, 'alert_level');
            final status = _statusOf(a);
            final levelColor = Domain.alertLevelColor(level);
            final unread = !_manager && !isRead(a);
            final accent = switch (level) {
              'critical' => kGradRed,
              'warning' => const [Color(0xFFFBBF24), Color(0xFFD97706)],
              'advisory' => kGradSky,
              _ => const [Color(0xFF94A3B8), Color(0xFF64748B)],
            };
            return RecordCard(
              title: str(a, 'title'),
              subtitle: str(a, 'message'),
              icon: level == 'critical' ? Icons.warning_amber_rounded : Icons.campaign_outlined,
              accent: accent,
              highlight: unread,
              body: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 13, color: Ui.slate400),
                    const SizedBox(width: 4),
                    Text(Ui.formatDateTime(a['sent_at'] ?? a['created_at']), style: const TextStyle(fontSize: 11.5, color: Ui.slate500)),
                  ],
                ),
              ),
              pills: [
                Pill(Ui.titleCase(str(a, 'alert_type')), color: Ui.indigo),
                Pill(Ui.titleCase(level), color: levelColor),
                Pill(str(a, 'municipality_name', 'Province-wide'), color: Ui.slate500),
                Pill(Ui.titleCase(status), color: _statusColor(status)),
              ],
              actions: [
                if (_manager) ...[
                  ActionIconButton(icon: Icons.edit_outlined, tooltip: 'Edit alert', color: Ui.amber, onPressed: () => _edit(a)),
                  if (status != 'sent') ActionIconButton(icon: Icons.send_outlined, tooltip: 'Send alert', color: Ui.emerald, onPressed: () => _send(a)),
                  ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete alert', color: Ui.red, onPressed: () => _delete(a)),
                ] else if (unread)
                  SmallButton(label: 'Mark as read', icon: Icons.check, color: Ui.emerald, onPressed: () => _markRead(a)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _AlertForm extends StatefulWidget {
  const _AlertForm({this.item, required this.municipalities});

  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> municipalities;

  @override
  State<_AlertForm> createState() => _AlertFormState();
}

class _AlertFormState extends State<_AlertForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: str(widget.item, 'title'));
  late final _message = TextEditingController(text: str(widget.item, 'message'));
  late String _type = str(widget.item, 'alert_type', 'emergency_alert');
  late String _level = str(widget.item, 'alert_level', 'warning');
  late String _municipalityId = Session.instance.isSubadmin ? (Session.instance.municipalityId?.toString() ?? '') : str(widget.item, 'municipality_id');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {'title': _title.text.trim(), 'alert_type': _type, 'alert_level': _level, 'municipality_id': _municipalityId, 'message': _message.text.trim()};
    try {
      if (widget.item != null) {
        await Api.instance.put('/alerts/${widget.item!['id']}', payload);
      } else {
        await Api.instance.post('/alerts', payload);
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
    final session = Session.instance;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.item == null ? 'Create alert' : 'Edit alert', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const FieldLabel('Alert title'),
              TextFormField(controller: _title, decoration: fieldDecoration('Alert title'), validator: (v) => (v == null || v.trim().length < 3) ? 'Enter at least 3 characters' : null),
              const FieldLabel('Alert type'),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: fieldDecoration('Type'),
                items: Domain.alertTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const FieldLabel('Alert level'),
              DropdownButtonFormField<String>(
                initialValue: _level,
                decoration: fieldDecoration('Level'),
                items: Domain.alertLevels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _level = v ?? _level),
              ),
              const FieldLabel('Municipality'),
              if (session.isSubadmin)
                TextFormField(initialValue: session.municipalityName.isEmpty ? 'Assigned municipality' : session.municipalityName, enabled: false, decoration: fieldDecoration(''))
              else
                DropdownButtonFormField<String>(
                  initialValue: _municipalityId,
                  isExpanded: true,
                  decoration: fieldDecoration('Province-wide'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Province-wide')),
                    ...widget.municipalities.map(
                      (m) => DropdownMenuItem(
                        value: str(m, 'id'),
                        child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _municipalityId = v ?? ''),
                ),
              const FieldLabel('Alert message'),
              TextFormField(
                controller: _message,
                maxLines: 6,
                decoration: fieldDecoration('Alert message'),
                validator: (v) => (v == null || v.trim().length < 5) ? 'Enter at least 5 characters' : null,
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
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Ui.slate900),
                      onPressed: _busy ? null : _submit,
                      child: const Text('Save draft'),
                    ),
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
