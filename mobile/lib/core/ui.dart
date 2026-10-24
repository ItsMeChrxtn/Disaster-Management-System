import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'rich.dart';
export 'rich.dart';
export 'rich_widgets.dart';

/// SweetAlert2 equivalents from frontend/assets/js/alerts.js.
class Ui {
  Ui._();

  // Mirrors the web design tokens in frontend/assets/css/theme.css.
  static const Color indigo = Color(0xFF1D4ED8); // primary
  static const Color primarySoft = Color(0xFFEAF0FF);
  static const Color navy = Color(0xFF0F1B33);
  static const Color navy2 = Color(0xFF16294D);
  static const Color slate900 = Color(0xFF0B1220);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate100 = Color(0xFFF4F6FA);
  static const Color line = Color(0xFFE6EAF0);
  static const Color lineStrong = Color(0xFFD2D9E3);
  static const Color red = Color(0xFFDC2626);
  static const Color emerald = Color(0xFF059669);
  static const Color amber = Color(0xFFD97706);
  static const Color sky = Color(0xFF0284C7);
  static const Color violet = Color(0xFF6D28D9);
  static const Color orange = Color(0xFFEA580C);

  static void toast(BuildContext context, String message, {String icon = 'success'}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final color = switch (icon) {
      'error' => red,
      'warning' => amber,
      'info' => sky,
      _ => emerald,
    };
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)));
  }

  static Future<void> showError(BuildContext context, String message, [Map<String, dynamic>? errors]) {
    final details = (errors ?? {}).entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: red, size: 40),
        title: const Text('Something went wrong'),
        content: Text(details.isEmpty ? message : '$message\n\n$details'),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  static Future<void> showSuccess(BuildContext context, String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: emerald, size: 40),
        title: Text(title),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  static Future<bool> confirm(BuildContext context, String title, {String message = 'This action cannot be undone.', String confirmText = 'Confirm', bool danger = true}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(danger ? Icons.warning_amber_rounded : Icons.help_outline, color: danger ? red : indigo, size: 40),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger ? red : indigo),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Runs [task] while a blocking progress dialog is visible.
  static Future<T> withLoading<T>(BuildContext context, String message, Future<T> Function() task) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
  }

  static String formatDateTime(dynamic value) {
    if (value == null) return '-';
    var text = value.toString();
    if (text.isEmpty) return '-';
    if (!text.contains('T')) text = text.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return value.toString();
    return DateFormat('MMM d, y h:mm a').format(parsed.toLocal());
  }

  static String formatUtcDateTime(dynamic value) {
    if (value == null) return '-';
    var text = value.toString().replaceFirst(' ', 'T');
    if (!text.endsWith('Z')) text = '${text}Z';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return value.toString();
    return DateFormat('MMM d, y h:mm a').format(parsed.toLocal());
  }

  static final NumberFormat money = NumberFormat('#,##0.00');

  static String titleCase(dynamic value) {
    return value.toString().replaceAll('_', ' ').split(' ').where((part) => part.isNotEmpty).map((part) => part[0].toUpperCase() + part.substring(1)).join(' ');
  }

  /// Equivalent of the SmartTable CSV/Excel export buttons: writes a CSV and
  /// opens the Android share sheet.
  static Future<void> exportCsv(BuildContext context, String name, List<String> headers, List<List<dynamic>> rows) async {
    String cell(dynamic value) {
      final text = (value ?? '').toString();
      return '"${text.replaceAll('"', '""')}"';
    }

    final buffer = StringBuffer()..writeln(headers.map(cell).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(cell).join(','));
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.csv');
    await file.writeAsString(buffer.toString());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: '$name export',
      ),
    );
  }
}

/// Small helpers for the untyped JSON rows returned by the API.
String str(dynamic map, String key, [String fallback = '']) {
  if (map is! Map) return fallback;
  final value = map[key];
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

double? dbl(dynamic map, String key) {
  if (map is! Map) return null;
  final value = map[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int intOf(dynamic map, String key, [int fallback = 0]) {
  if (map is! Map) return fallback;
  final value = map[key];
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

List<Map<String, dynamic>> rowsOf(dynamic data) {
  if (data is! List) return [];
  return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, dynamic> mapOf(dynamic data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

/// Common widgets (mirror the web components in theme.css).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.line),
        boxShadow: const [
          BoxShadow(color: Color(0x0D0F172A), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4), spreadRadius: -6),
        ],
      ),
      child: child,
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.textColor});

  final String text;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor ?? color, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Text(text, style: const TextStyle(color: Ui.slate500)),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = Ui.indigo, this.rule = false});

  final String text;
  final Color color;

  /// Prefix with a short gradient rule (web: .section-heading .eyebrow::before).
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: color),
    );
    if (!rule) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 3,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(colors: kGradBlue),
          ),
        ),
        Flexible(child: label),
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Ui.slate900, letterSpacing: -.4, height: 1.2),
        ),
        if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: const TextStyle(color: Ui.slate500, fontSize: 13.5, height: 1.45))],
        if (actions.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: actions)],
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
      ),
    );
  }
}

InputDecoration fieldDecoration(String hint, {Widget? suffix}) =>
    InputDecoration(hintText: hint, isDense: true, suffixIcon: suffix, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12));

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(message!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13)),
    );
  }
}

class ActionIconButton extends StatelessWidget {
  const ActionIconButton({super.key, required this.icon, required this.tooltip, required this.color, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Ui.line),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller});

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: fieldDecoration(hint).copyWith(prefixIcon: const Icon(Icons.search, size: 19, color: Ui.slate400)),
    );
  }
}

/// Icon tile used by stat cards and list rows (web: .stat-icon / .user-avatar).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, this.size = 40, this.child});

  final IconData icon;
  final Color color;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(size * .28)),
      child: child ?? Icon(icon, color: color, size: size * .5),
    );
  }
}

/// Gradient location-pin brand tile + wordmark (web: .brand-mark).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.subtitle = 'Cavite Readiness Hub', this.onDark = false, this.size = 38});

  final String subtitle;
  final bool onDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: onDark ? null : const LinearGradient(colors: [Ui.indigo, Color(0xFF0EA5E9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            color: onDark ? Colors.white.withValues(alpha: .14) : null,
            borderRadius: BorderRadius.circular(size * .3),
            boxShadow: onDark ? null : const [BoxShadow(color: Color(0x661D4ED8), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -6)],
          ),
          child: Icon(Icons.location_on_outlined, color: Colors.white, size: size * .55),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Disaster Map',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: onDark ? Colors.white : Ui.slate900, height: 1.15),
            ),
            Text(subtitle, style: TextStyle(fontSize: 11.5, color: onDark ? const Color(0xFF93C5FD) : Ui.slate500, height: 1.2)),
          ],
        ),
      ],
    );
  }
}
