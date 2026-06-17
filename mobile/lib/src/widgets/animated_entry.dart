import 'package:flutter/material.dart';

class AnimatedEntry extends StatefulWidget {
  const AnimatedEntry({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<Offset> _offset = Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  late final Animation<double> _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    if (widget.delay > Duration.zero) {
      Future.delayed(widget.delay, () { if (mounted) _ctrl.forward(); });
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}
