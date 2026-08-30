import 'package:flutter/material.dart';

/// Reusable responsive grid — import and use this in any
/// dashboard/page, so LayoutBuilder / crossAxisCount logic doesn't
/// need to be written separately in every file.
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

  /// Fallback for when mainSpacing/crossSpacing aren't given.
  final double spacing;
  final double? mainSpacing;
  final double? crossSpacing;

  /// If the grid is nested inside a scrollable Column/ListView (it
  /// shouldn't scroll itself), pass `shrinkWrap: true` and
  /// `physics: NeverScrollableScrollPhysics()`.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Optional override — if given, this will always be used instead
  /// of the width-based default aspectRatio (e.g. for form-field grids
  /// whose shape differs from dashboard cards).
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
