import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One slice of the donut (one class + its student count).
class ClassCount {
  final String label;
  final int count;

  const ClassCount({required this.label, required this.count});
}

/// A compact donut chart showing students-per-class, with a legend.
///
/// Replaces the old horizontally-scrolling bar chart on the admin
/// dashboard: with many classes (10+) the bar chart needed horizontal
/// scrolling and looked cramped inside the dashboard card. A donut is a
/// fixed, predictable size no matter how many classes there are, and the
/// legend below it wraps neatly instead of scrolling — no external chart
/// package needed, so pubspec.yaml stays untouched.
class ClassDistributionDonutChart extends StatelessWidget {
  final List<ClassCount> data;
  final double size;

  const ClassDistributionDonutChart({
    super.key,
    required this.data,
    this.size = 150,
  });

  // A pleasant, high-contrast palette that cycles if there are more
  // classes than colors.
  static const List<Color> _palette = [
    Color(0xFF0F766E), // teal 700
    Color(0xFF2563EB), // blue 600
    Color(0xFFF59E0B), // amber 500
    Color(0xFFDB2777), // pink 600
    Color(0xFF7C3AED), // violet 600
    Color(0xFF16A34A), // green 600
    Color(0xFFDC2626), // red 600
    Color(0xFF0891B2), // cyan 600
    Color(0xFFCA8A04), // yellow 600
    Color(0xFF9333EA), // purple 600
    Color(0xFFEA580C), // orange 600
    Color(0xFF4F46E5), // indigo 600
    Color(0xFF059669), // emerald 600
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: size,
        child: const Center(
          child:
              Text("No data to chart yet.", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final total = data.fold<int>(0, (a, b) => a + b.count);
    final slices = <_Slice>[
      for (var i = 0; i < data.length; i++)
        _Slice(
          label: data[i].label,
          value: data[i].count,
          color: _palette[i % _palette.length],
        ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _DonutPainter(slices: slices, total: total),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "$total",
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const Text(
                    "Students",
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final s in slices)
                _LegendChip(
                  color: s.color,
                  label: s.label,
                  count: s.value,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Slice {
  final String label;
  final int value;
  final Color color;

  const _Slice({required this.label, required this.value, required this.color});
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _LegendChip(
      {required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          "$label ($count)",
          style: const TextStyle(fontSize: 11.5, color: Colors.black87),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  final int total;

  _DonutPainter({required this.slices, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.34;
    final rect = Rect.fromCircle(
        center: center, radius: radius - strokeWidth / 2 - 2);

    double startAngle = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      // Small gap between slices for visual separation.
      final gap = slices.length > 1 ? 0.02 : 0.0;
      canvas.drawArc(rect, startAngle + gap / 2, sweep - gap, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.total != total;
  }
}
