import 'package:flutter/material.dart';

class ResponsivePage extends StatelessWidget {
  const ResponsivePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxWidth > 900 ? 860.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: max, child: child),
        );
      },
    );
  }
}
