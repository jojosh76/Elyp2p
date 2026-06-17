import 'package:flutter/material.dart';

class FancyCard extends StatelessWidget {
  const FancyCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14.0);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.98)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.6),
            blurRadius: 0,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
