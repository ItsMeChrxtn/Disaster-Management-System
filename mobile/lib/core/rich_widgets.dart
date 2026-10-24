import 'package:flutter/material.dart';

import 'ui.dart';

/// Navy gradient module banner used at the top of every dashboard module
/// (web: .overview-hero). Actions render beneath the copy.
class ModuleHeader extends StatelessWidget {
  const ModuleHeader({super.key, required this.eyebrow, required this.title, required this.subtitle, required this.icon, this.actions = const [], this.trailing});

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: kNavyGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x590F172A), blurRadius: 40, offset: Offset(0, 22), spreadRadius: -18)],
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: GridOverlay()),
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .05)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.white.withValues(alpha: .18)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(eyebrow, color: const Color(0xFF93C5FD)),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.5, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 10),
                Text(subtitle, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.45)),
                if (actions.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: actions)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White (primary) or glass (secondary) pill button for use on the navy banner.
class BannerButton extends StatelessWidget {
  const BannerButton({super.key, required this.label, required this.icon, this.onPressed, this.primary = true});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? Colors.white : Colors.white.withValues(alpha: .12);
    final fg = primary ? Ui.navy : Colors.white;
    return Opacity(
      opacity: onPressed == null ? .55 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: primary ? null : Border.all(color: Colors.white.withValues(alpha: .25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium list row: left accent bar, gradient icon tile, title/subtitle,
/// optional body, pills row and action buttons.
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconText,
    this.accent = kGradBlue,
    this.pills = const [],
    this.actions = const [],
    this.body,
    this.onTap,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? iconText;
  final List<Color> accent;
  final List<Widget> pills;
  final List<Widget> actions;
  final Widget? body;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFFDF5) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ui.line),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -8)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: accent, begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (icon != null || iconText != null)
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: accent, begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: accent.last.withValues(alpha: .5), blurRadius: 16, offset: const Offset(0, 8), spreadRadius: -8)],
                            ),
                            child: iconText != null
                                ? Text(
                                    iconText!,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
                                  )
                                : Icon(icon, color: Colors.white, size: 20),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Ui.slate900, height: 1.25),
                              ),
                              if (subtitle != null && subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  subtitle!,
                                  style: const TextStyle(fontSize: 12.5, color: Ui.slate500, height: 1.4),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    ?body,
                    if (pills.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 6, runSpacing: 6, children: pills)],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented filter chips (web: .safe-zone-filter-buttons).
class SegmentedChips extends StatelessWidget {
  const SegmentedChips({super.key, required this.options, required this.value, required this.onChanged});

  /// (key, label, count or null)
  final List<(String, String, int?)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Ui.line),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: o.$1 == value ? const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0EA5E9)]) : null,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: o.$1 == value ? const [BoxShadow(color: Color(0x802563EB), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -8)] : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        o.$2,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: o.$1 == value ? Colors.white : Ui.slate500),
                      ),
                      if (o.$3 != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: o.$1 == value ? Colors.white.withValues(alpha: .22) : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            o.$3.toString(),
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: o.$1 == value ? Colors.white : Ui.slate500),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section label with count badge (web: .table-toolbar-title).
class ListHeading extends StatelessWidget {
  const ListHeading(this.title, {super.key, this.count, this.trailing});

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Ui.slate900),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Ui.primarySoft, borderRadius: BorderRadius.circular(999)),
              child: Text(
                count.toString(),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Ui.indigo),
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small outlined action button used on cards (web: .button-secondary .button-sm).
class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, required this.icon, this.onPressed, this.color = Ui.slate900});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Ui.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
