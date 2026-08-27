import 'package:flutter/material.dart';

/// Reusable responsive grid — ise kisi bhi dashboard/page mein import
/// kar ke use karein, taake har file mein alag se LayoutBuilder /
/// crossAxisCount logic na likhna pade.
///
/// Usage:
/// ```dart
/// Expanded(
///   child: ResponsiveGrid(
///     children: [
///       _dashboardCard(...),
///       _dashboardCard(...),
///     ],
///   ),
/// )
/// ```
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// Fallback jab mainSpacing/crossSpacing na diye gaye hon.
  final double spacing;
  final double? mainSpacing;
  final double? crossSpacing;

  /// Agar grid kisi scrollable Column/ListView ke andar nested ho
  /// (khud scroll nahi karna), to `shrinkWrap: true` aur
  /// `physics: NeverScrollableScrollPhysics()` pass karein.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Optional override — agar diya jaye to width-based default
  /// aspectRatio ke bajaye hamesha yehi use hoga (jaise form-field
  /// grids jinka shape dashboard cards se alag hota hai).
  final double? aspectRatio;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(20),
    this.spacing = 10,
    this.mainSpacing,
    this.crossSpacing,
    this.shrinkWrap = false,
    this.physics,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        double defaultAspectRatio;

        if (width >= 1200) {
          crossAxisCount = 5;
          defaultAspectRatio = 1.3;
        } else if (width >= 900) {
          crossAxisCount = 4;
          defaultAspectRatio = 1.2;
        } else if (width >= 600) {
          crossAxisCount = 3;
          defaultAspectRatio = 1.1;
        } else {
          crossAxisCount = 2;
          defaultAspectRatio = 1.0;
        }

        return GridView.count(
          padding: padding,
          shrinkWrap: shrinkWrap,
          physics: physics,
          crossAxisCount: crossAxisCount,
          childAspectRatio: aspectRatio ?? defaultAspectRatio,
          mainAxisSpacing: mainSpacing ?? spacing,
          crossAxisSpacing: crossSpacing ?? spacing,
          children: children,
        );
      },
    );
  }
}
