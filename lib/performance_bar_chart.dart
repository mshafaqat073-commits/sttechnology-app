import 'package:flutter/material.dart';

/// One bar in the chart.
class PerformanceBarData {
  final String label;
  final double value;
  final Color color;

  const PerformanceBarData({
    required this.label,
    required this.value,
    this.color = Colors.indigo,
  });
}

/// A small, dependency-free bar chart (no external chart package needed —
/// keeps pubspec.yaml untouched). Used to show attendance breakdown,
/// result/percentage trend, etc. on the Parent & Teacher performance pages.
///
/// Values are shown as vertical bars scaled against [maxValue] (or the
/// highest bar if [maxValue] is not given), with the value printed above
/// each bar and the label below it. Horizontally scrollable so it never
/// overflows when there are many bars (e.g. many terms/dates).
class PerformanceBarChart extends StatelessWidget {
  final List<PerformanceBarData> bars;
  final double? maxValue;
  final double height;
  final String? valueSuffix;

  const PerformanceBarChart({
    super.key,
    required this.bars,
    this.maxValue,
    this.height = 160,
    this.valueSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text("No data to chart yet.",
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    double max = maxValue ??
        bars.map((b) => b.value).fold<double>(0, (a, b) => a > b ? a : b);
    if (max <= 0) max = 1;

    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: bars.map((b) {
            double fraction = (b.value / max).clamp(0.0, 1.0);
            double barHeight = (height - 44) * fraction;
            return Container(
              width: 56,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "${b.value % 1 == 0 ? b.value.toStringAsFixed(0) : b.value.toStringAsFixed(1)}$valueSuffix",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: b.color),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    height: barHeight < 4 ? 4 : barHeight,
                    width: 28,
                    decoration: BoxDecoration(
                      color: b.color,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    b.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black87),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// A compact horizontal progress-style meter (used for overall attendance %
/// / result % headline numbers, e.g. on top of the performance page).
class PerformanceMeter extends StatelessWidget {
  final String label;
  final double percentage; // 0-100
  final Color color;

  const PerformanceMeter({
    super.key,
    required this.label,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    double clamped = percentage.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text("${clamped.toStringAsFixed(1)}%",
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 10,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Shared remark logic — turns an attendance % + an academic % into a
/// short, color-coded remark. Used by both Parent & Teacher performance
/// pages so the wording/thresholds stay consistent across the app.
class PerformanceRemark {
  final String text;
  final Color color;
  final IconData icon;

  const PerformanceRemark(this.text, this.color, this.icon);

  static PerformanceRemark band(double value,
      {required String excellent,
      required String good,
      required String average,
      required String weak}) {
    if (value >= 90) {
      return PerformanceRemark(excellent, Colors.green, Icons.emoji_events);
    } else if (value >= 75) {
      return PerformanceRemark(good, Colors.blue, Icons.thumb_up);
    } else if (value >= 50) {
      return PerformanceRemark(
          average, Colors.orange, Icons.trending_flat);
    }
    return PerformanceRemark(weak, Colors.red, Icons.warning_amber_rounded);
  }

  static PerformanceRemark attendanceRemark(double attendancePercent) {
    return band(
      attendancePercent,
      excellent: "Excellent attendance",
      good: "Good attendance",
      average: "Average attendance — needs improvement",
      weak: "Poor attendance — needs serious improvement",
    );
  }

  static PerformanceRemark academicRemark(double avgPercentage) {
    return band(
      avgPercentage,
      excellent: "Excellent academic performance",
      good: "Good academic performance",
      average: "Average performance — needs improvement",
      weak: "Weak performance — needs focused attention",
    );
  }

  /// Combines attendance + academic remarks into one overall verdict.
  static PerformanceRemark overall(
      double attendancePercent, double avgPercentage,
      {bool hasResults = true, bool hasAttendance = true}) {
    if (!hasResults && !hasAttendance) {
      return const PerformanceRemark(
          "Not enough data yet to judge performance.",
          Colors.grey,
          Icons.info_outline);
    }
    double combined;
    if (hasResults && hasAttendance) {
      combined = (attendancePercent + avgPercentage) / 2;
    } else if (hasAttendance) {
      combined = attendancePercent;
    } else {
      combined = avgPercentage;
    }
    return band(
      combined,
      excellent: "Overall performance: Excellent",
      good: "Overall performance: Good",
      average: "Overall performance: Average — needs improvement",
      weak: "Overall performance: Needs serious attention",
    );
  }
}

/// A ready-made "Remarks" card used on both performance pages.
class PerformanceRemarkCard extends StatelessWidget {
  final PerformanceRemark remark;
  final List<String>? subRemarks;

  const PerformanceRemarkCard({
    super.key,
    required this.remark,
    this.subRemarks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: remark.color.withValues(alpha: 0.08),
        border: Border.all(color: remark.color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(remark.icon, color: remark.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remark.text,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: remark.color,
                      fontSize: 14),
                ),
              ),
            ],
          ),
          if (subRemarks != null && subRemarks!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...subRemarks!.map((s) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text("• $s",
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black87)),
                )),
          ],
        ],
      ),
    );
  }
}
