import 'package:flutter/material.dart';

/// One row in the list (one class + its student count).
class ClassCount {
  final String label;
  final int count;

  const ClassCount({required this.label, required this.count});
}

/// A compact "ranked bar list" showing students-per-class: each class gets
/// one row with its name on the left, a proportional horizontal bar in the
/// middle, and the exact count on the right.
///
/// This replaces the old vertical bar chart (which needed horizontal
/// scrolling and looked cramped with 10+ classes) and the donut chart
/// (which hid the exact numbers in a legend). Here every count is printed
/// right next to its class, and the list just grows downward — no
/// scrolling, no crowding, however many classes there are.
class ClassDistributionBarList extends StatelessWidget {
  final List<ClassCount> data;
  final Color color;

  const ClassDistributionBarList({
    super.key,
    required this.data,
    this.color = const Color(0xFF0F6E56), // teal 700
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child:
              Text("No data to chart yet.", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final maxValue = data
        .map((d) => d.count)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(1, 1 << 30);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    d.label,
                    style: const TextStyle(
                        fontSize: 12.5, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: d.count / maxValue,
                      minHeight: 14,
                      backgroundColor: color.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 26,
                  child: Text(
                    "${d.count}",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
