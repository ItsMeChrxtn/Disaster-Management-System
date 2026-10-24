import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/domain.dart';
import '../core/session.dart';
import '../core/ui.dart';

/// Report generation and download (admin + sub admin).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _dateFrom = TextEditingController();
  final _dateTo = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _municipalities = [];
  String _type = 'hazard';
  String _format = 'pdf';
  String _municipalityId = '';
  String? _error;
  bool _generating = false;
  bool _loading = true;
  int? _downloading;

  @override
  void initState() {
    super.initState();
    _load();
    if (Session.instance.isAdmin) _loadMunicipalities();
  }

  @override
  void dispose() {
    _dateFrom.dispose();
    _dateTo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = rowsOf(await Api.instance.get('/reports'));
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

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(controller.text) ?? now, firstDate: DateTime(2000), lastDate: DateTime(now.year + 1));
    if (picked != null) setState(() => controller.text = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      await Api.instance.post('/reports', {
        'report_type': _type,
        'format': _format,
        'date_from': _dateFrom.text,
        'date_to': _dateTo.text,
        if (Session.instance.isAdmin && _municipalityId.isNotEmpty) 'municipality_id': _municipalityId,
      });
      if (!mounted) return;
      Ui.toast(context, 'Report generated successfully');
      _dateFrom.clear();
      _dateTo.clear();
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.errors.isEmpty ? e.message : '${e.message}\n${e.errors.values.join('\n')}');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _download(Map<String, dynamic> report) async {
    final id = intOf(report, 'id');
    setState(() => _downloading = id);
    try {
      final response = await Api.instance.download('/reports/$id/download');
      if (response.statusCode != 200) {
        String message = 'Download failed';
        try {
          message = (jsonDecode(response.body) as Map)['message']?.toString() ?? message;
        } catch (_) {}
        throw ApiException(message, status: response.statusCode);
      }
      final filename = str(report, 'file_path').split('/').last;
      final dir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory('${dir.path}/reports');
      if (!await reportsDir.exists()) await reportsDir.create(recursive: true);
      final file = File('${reportsDir.path}/${filename.isEmpty ? 'report-$id.${str(report, 'format', 'pdf')}' : filename}');
      await file.writeAsBytes(response.bodyBytes);
      if (!mounted) return;
      Ui.toast(context, 'Report downloaded');
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        // No viewer installed – fall back to the share sheet so the user can save it elsewhere.
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: filename));
      }
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message);
    } catch (e) {
      if (mounted) Ui.showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _delete(Map<String, dynamic> report) async {
    if (!await Ui.confirm(context, 'Delete this generated report?', confirmText: 'Delete')) return;
    try {
      await Api.instance.delete('/reports/${report['id']}');
      if (mounted) Ui.toast(context, 'Report deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) Ui.showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ModuleHeader(
            eyebrow: 'Reporting desk',
            title: 'Report generation',
            subtitle: 'Generate traceable PDF or Excel reports scoped to a municipality and reporting period.',
            icon: Icons.description_outlined,
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const GradientTile(icon: Icons.auto_awesome_outlined, colors: kGradBlue, size: 34),
                    const SizedBox(width: 10),
                    const Text('New report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                const FieldLabel('Report type'),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: fieldDecoration('Report type'),
                  items: Domain.reportTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const FieldLabel('Export format'),
                DropdownButtonFormField<String>(
                  initialValue: _format,
                  decoration: fieldDecoration('Format'),
                  items: const [
                    DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                    DropdownMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
                  ],
                  onChanged: (v) => setState(() => _format = v ?? _format),
                ),
                if (Session.instance.isAdmin) ...[
                  const FieldLabel('Municipality (optional)'),
                  DropdownButtonFormField<String>(
                    initialValue: _municipalityId,
                    isExpanded: true,
                    decoration: fieldDecoration('Province-wide'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Province-wide')),
                      ..._municipalities.map(
                        (m) => DropdownMenuItem(
                          value: str(m, 'id'),
                          child: Text(str(m, 'municipality_name'), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _municipalityId = v ?? ''),
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('From'),
                          TextField(
                            controller: _dateFrom,
                            readOnly: true,
                            onTap: () => _pickDate(_dateFrom),
                            decoration: fieldDecoration('Any date', suffix: const Icon(Icons.calendar_today_outlined, size: 18)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('To'),
                          TextField(
                            controller: _dateTo,
                            readOnly: true,
                            onTap: () => _pickDate(_dateTo),
                            decoration: fieldDecoration('Any date', suffix: const Icon(Icons.calendar_today_outlined, size: 18)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ErrorBanner(_error),
                const SizedBox(height: 16),
                PrimaryButton(label: _generating ? 'Generating...' : 'Generate report', icon: Icons.bolt_outlined, onPressed: _generating ? null : _generate),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListHeading('Generated reports', count: _rows.length),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            ),
          if (!_loading && _rows.isEmpty) const EmptyNote('No generated reports.'),
          ..._rows.map((r) {
            final label = Domain.reportTypes[str(r, 'report_type')] ?? str(r, 'report_type');
            final pdf = str(r, 'format').toLowerCase() == 'pdf';
            return RecordCard(
              title: label,
              subtitle: 'Generated by ${str(r, 'generated_by_name')} · ${Ui.formatUtcDateTime(r['generated_at'])}',
              icon: pdf ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined,
              accent: pdf ? kGradRed : kGradGreen,
              pills: [Pill(str(r, 'format').toUpperCase(), color: pdf ? Ui.red : Ui.emerald)],
              actions: [
                if (_downloading == intOf(r, 'id'))
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  SmallButton(label: 'Download', icon: Icons.download_outlined, color: Ui.indigo, onPressed: () => _download(r)),
                ActionIconButton(icon: Icons.delete_outline, tooltip: 'Delete report', color: Ui.red, onPressed: () => _delete(r)),
              ],
            );
          }),
        ],
      ),
    );
  }
}
