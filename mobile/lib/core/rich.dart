import 'package:flutter/material.dart';

import 'ui.dart';

/// Gradient primary button with glow (web: .button-primary in the rich layer).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.expand = true, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = danger ? const [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFFF97316)] : const [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0EA5E9)];
    final glow = danger ? const Color(0x99DC2626) : const Color(0x992563EB);
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: Colors.white), const SizedBox(width: 8)],
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
      ],
    );
    return Opacity(
      opacity: onPressed == null ? .6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, stops: const [0, .55, 1], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [BoxShadow(color: glow, blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -10)],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(9),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), child: child),
          ),
        ),
      ),
    );
  }
}

/// Translucent "glass" button for use on dark gradients (web: .button-glass).
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.label, this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withValues(alpha: .28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: Colors.white), const SizedBox(width: 8)],
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navy gradient used by hero blocks, the drawer header and the overview header.
const LinearGradient kNavyGradient = LinearGradient(colors: [Color(0xFF1E3A8A), Ui.navy2, Ui.navy], stops: [0, .45, 1], begin: Alignment.topRight, end: Alignment.bottomLeft);

/// Gradient icon tile with glow (web: .stat-icon / .feature-icon rich variants).
class GradientTile extends StatelessWidget {
  const GradientTile({super.key, required this.icon, required this.colors, this.size = 40});

  final IconData icon;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * .28),
        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .55), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -8)],
      ),
      child: Icon(icon, color: Colors.white, size: size * .5),
    );
  }
}

/// Subtle grid pattern painted over navy gradient panels (web: .overview-hero::before).
class GridOverlay extends StatelessWidget {
  const GridOverlay({super.key, this.opacity = .06});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _GridPainter(opacity)));
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.opacity != opacity;
}

const List<Color> kGradBlue = [Color(0xFF2563EB), Color(0xFF0EA5E9)];
const List<Color> kGradGreen = [Color(0xFF34D399), Color(0xFF059669)];
const List<Color> kGradRed = [Color(0xFFF87171), Color(0xFFDC2626)];
const List<Color> kGradOrange = [Color(0xFFF97316), Color(0xFFEA580C)];
const List<Color> kGradViolet = [Color(0xFFA78BFA), Color(0xFF6D28D9)];
const List<Color> kGradSky = [Color(0xFF38BDF8), Color(0xFF0284C7)];
