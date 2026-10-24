import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../core/ui.dart';

const _categoryLabels = {'advisory': 'Advisory', 'directive': 'Directive', 'situation_report': 'Situation report', 'request': 'Request', 'response': 'Response', 'general': 'Message'};

/// PDRRMO <-> MDRRMO/CDRRMO coordination channel (mirrors frontend/assets/js/coordination.js).
/// Admin: list of every municipality channel plus "All LGUs" broadcasts. Sub-admin: own channel.
class CoordinationScreen extends StatefulWidget {
  const CoordinationScreen({super.key});

  @override
  State<CoordinationScreen> createState() => _CoordinationScreenState();
}

class _CoordinationScreenState extends State<CoordinationScreen> {
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;
  String _search = '';

  bool get _isAdmin => Session.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = mapOf(await Api.instance.get('/coordination/channels'));
      final rows = rowsOf(data['channels']);
      if (!mounted) return;
      setState(() {
        _channels = rows;
        _loading = false;
      });
      if (!_isAdmin && rows.isNotEmpty && _openedOnce == false) {
        _openedOnce = true;
        _openThread(rows.first['municipality_id'].toString(), rows.first);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Ui.toast(context, e.message, icon: 'error');
    }
  }

  bool _openedOnce = false;

  Future<void> _openThread(String id, Map<String, dynamic>? channel) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ThreadScreen(channelId: id, channel: channel, channels: _channels),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.instance;
    final term = _search.trim().toLowerCase();
    final rows = _channels.where((c) => term.isEmpty || str(c, 'municipality_name').toLowerCase().contains(term)).toList();
    final unread = _channels.fold<int>(0, (t, c) => t + intOf(c, 'unread'));
    final pending = _channels.where((c) => intOf(c, 'pending_ack') > 0).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ModuleHeader(
            eyebrow: _isAdmin ? 'Municipalities · LGU coordination' : '${session.lguOffice} ↔ PDRRMO',
            title: _isAdmin ? 'Coordination channel' : session.municipalityName,
            subtitle: _isAdmin
                ? 'Send directives and advisories to every MDRRMO / CDRRMO and receive their situation reports.'
                : 'Report incidents and needs to the Provincial DRRM Office and acknowledge provincial directives.',
            icon: Icons.forum_outlined,
            actions: [
              if (_isAdmin) BannerButton(label: 'Message all LGUs', icon: Icons.campaign_outlined, onPressed: () => _openThread('all', null)),
              if (!_isAdmin && _channels.isNotEmpty)
                BannerButton(label: 'Open channel', icon: Icons.chat_outlined, onPressed: () => _openThread(_channels.first['municipality_id'].toString(), _channels.first)),
            ],
          ),
          const SizedBox(height: 12),
          if (_isAdmin)
            SectionCard(
              child: Row(
                children: [
                  IconTile(icon: Icons.mark_email_unread_outlined, color: unread > 0 ? Ui.red : Ui.emerald, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(unread > 0 ? '$unread new report${unread == 1 ? '' : 's'} from LGUs' : 'No unread LGU reports', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          pending > 0 ? '$pending LGU${pending == 1 ? '' : 's'} still to acknowledge a directive' : 'All directives acknowledged',
                          style: const TextStyle(fontSize: 12, color: Ui.slate500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_isAdmin) ...[const SizedBox(height: 12), SearchField(hint: 'Search municipality', onChanged: (v) => setState(() => _search = v))],
          ListHeading(_isAdmin ? 'Municipal channels' : 'Your channel', count: rows.length),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          if (!_loading && rows.isEmpty) const EmptyNote('No channels found.'),
          ...rows.map((c) {
            final last = c['last_message'] is Map ? Map<String, dynamic>.from(c['last_message'] as Map) : null;
            final office = str(c, 'office', 'MDRRMO');
            return RecordCard(
              title: str(c, 'municipality_name'),
              subtitle: last == null
                  ? (intOf(c, 'officers') > 0 ? '${intOf(c, 'officers')} $office account(s)' : 'No officer account yet')
                  : '${str(last, 'direction') == 'to_province' ? office : 'PDRRMO'}: ${str(last, 'subject')}',
              icon: Icons.forum_outlined,
              accent: intOf(c, 'unread') > 0 ? kGradRed : kGradBlue,
              onTap: () => _openThread(c['municipality_id'].toString(), c),
              pills: [
                Pill(office, color: Ui.navy),
                if (intOf(c, 'unread') > 0) Pill('${intOf(c, 'unread')} new', color: Ui.red),
                if (intOf(c, 'pending_ack') > 0) Pill('${intOf(c, 'pending_ack')} awaiting ack', color: Ui.amber),
                if (last != null) Pill(Ui.formatDateTime(last['created_at']), color: Ui.slate500),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ThreadScreen extends StatefulWidget {
  const _ThreadScreen({required this.channelId, required this.channel, required this.channels});

  final String channelId;
  final Map<String, dynamic>? channel;
  final List<Map<String, dynamic>> channels;

  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _requiresAck = false;
  late String _category = Session.instance.isAdmin ? 'advisory' : 'situation_report';
  String _priority = 'normal';
  Timer? _poll;

  bool get _isAdmin => Session.instance.isAdmin;
  bool get _isBroadcast => widget.channelId == 'all';

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _subject.dispose();
    _body.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final data = mapOf(await Api.instance.get('/coordination/messages?municipality_id=${Uri.encodeComponent(widget.channelId)}'));
      if (!mounted) return;
      final before = _messages.length;
      setState(() {
        _messages = rowsOf(data['messages']);
        _loading = false;
      });
      if (!silent || _messages.length != before) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) Ui.toast(context, e.message, icon: 'error');
    }
  }

  Future<void> _send() async {
    if (_subject.text.trim().length < 2 || _body.text.trim().isEmpty) {
      Ui.toast(context, 'Enter a subject and a message.', icon: 'warning');
      return;
    }
    setState(() => _sending = true);
    final payload = <String, dynamic>{'category': _category, 'priority': _priority, 'subject': _subject.text.trim(), 'body': _body.text.trim(), 'requires_ack': _requiresAck};
    if (_isAdmin) payload['municipality_ids'] = _isBroadcast ? 'all' : [int.parse(widget.channelId)];
    try {
      await Api.instance.post('/coordination/messages', payload);
      _subject.clear();
      _body.clear();
      setState(() => _requiresAck = false);
      if (mounted) Ui.toast(context, 'Message sent');
      await _load();
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message, e.errors);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _acknowledge(Map<String, dynamic> m) async {
    try {
      await Api.instance.post('/coordination/messages/${m['id']}/acknowledge', {});
      if (mounted) Ui.toast(context, 'Acknowledged — the PDRRMO has been notified');
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message);
    }
  }

  Widget _message(Map<String, dynamic> m) {
    final mine = _isAdmin ? str(m, 'direction') == 'to_lgu' : str(m, 'direction') == 'to_province';
    final priority = str(m, 'priority', 'normal');
    final edge = priority == 'critical' ? Ui.red : (priority == 'urgent' ? Ui.amber : Colors.transparent);
    Widget? ack;
    if (str(m, 'direction') == 'to_lgu' && m['requires_ack'] == true) {
      if (_isBroadcast) {
        ack = Text(
          'Acknowledged by ${intOf(m, 'ack_count')} of ${widget.channels.length} LGUs',
          style: const TextStyle(fontSize: 11.5, color: Ui.slate500, fontWeight: FontWeight.w600),
        );
      } else if (m['acknowledged_at'] != null) {
        ack = Text(
          '✓ Acknowledged by ${str(m, 'acknowledged_by', 'LGU')} · ${Ui.formatDateTime(m['acknowledged_at'])}',
          style: const TextStyle(fontSize: 11.5, color: Ui.emerald, fontWeight: FontWeight.w700),
        );
      } else if (_isAdmin) {
        ack = const Text(
          'Awaiting acknowledgement',
          style: TextStyle(fontSize: 11.5, color: Ui.amber, fontWeight: FontWeight.w700),
        );
      } else {
        ack = FilledButton.icon(onPressed: () => _acknowledge(m), icon: const Icon(Icons.check, size: 16), label: const Text('Acknowledge'));
      }
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFF5F7FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(color: edge == Colors.transparent ? (mine ? const Color(0xFFC7D2FE) : Ui.line) : edge, width: edge == Colors.transparent ? 1 : 4),
              top: BorderSide(color: mine ? const Color(0xFFC7D2FE) : Ui.line),
              right: BorderSide(color: mine ? const Color(0xFFC7D2FE) : Ui.line),
              bottom: BorderSide(color: mine ? const Color(0xFFC7D2FE) : Ui.line),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${str(m, 'sender_office')} · ${str(m, 'sender_name')}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Ui.slate500),
                  ),
                  Pill(_categoryLabels[str(m, 'category')] ?? str(m, 'category'), color: Ui.indigo),
                  if (priority != 'normal') Pill(priority.toUpperCase(), color: priority == 'critical' ? Ui.red : Ui.amber),
                  if (m['is_broadcast'] == true && !_isBroadcast) const Pill('All LGUs', color: Ui.violet),
                ],
              ),
              const SizedBox(height: 6),
              Text(str(m, 'subject'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              const SizedBox(height: 4),
              Text(str(m, 'body'), style: const TextStyle(fontSize: 13, height: 1.45)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(Ui.formatDateTime(m['created_at']), style: const TextStyle(fontSize: 11, color: Ui.slate400)),
                  ?ack,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final title = _isBroadcast ? 'All MDRRMO / CDRRMO' : str(channel, 'municipality_name', Session.instance.municipalityName);
    final subtitle = _isBroadcast ? 'Province-wide broadcast' : '${str(channel, 'office', Session.instance.lguOffice)} ↔ PDRRMO';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Ui.slate500)),
          ],
        ),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: EmptyNote(_isAdmin ? 'No messages yet. Send an advisory or directive to start the channel.' : 'No messages yet. Send a situation report or request to the PDRRMO.'),
                    ),
                  )
                : ListView(controller: _scroll, padding: const EdgeInsets.all(14), children: _messages.map(_message).toList()),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Ui.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          isDense: true,
                          decoration: fieldDecoration('Type'),
                          items: _categoryLabels.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value, style: const TextStyle(fontSize: 13)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _category = v ?? 'general'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _priority,
                          isDense: true,
                          decoration: fieldDecoration('Priority'),
                          items: const [
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normal', style: TextStyle(fontSize: 13)),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text('Urgent', style: TextStyle(fontSize: 13)),
                            ),
                            DropdownMenuItem(
                              value: 'critical',
                              child: Text('Critical', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                          onChanged: (v) => setState(() => _priority = v ?? 'normal'),
                        ),
                      ),
                    ],
                  ),
                  if (_isAdmin)
                    CheckboxListTile(
                      value: _requiresAck,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Require acknowledgement', style: TextStyle(fontSize: 13)),
                      onChanged: (v) => setState(() => _requiresAck = v ?? false),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _subject,
                    maxLength: 180,
                    decoration: fieldDecoration('Subject').copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _body,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 5000,
                          decoration: fieldDecoration('Write the message, report or instruction…').copyWith(counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(minimumSize: const Size(52, 48), padding: EdgeInsets.zero),
                        child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
