import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  Timer? _timer;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 6500), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF10231C), Color(0xFF0D3D46), Color(0xFF2A7E6F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Elysian Flee',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                height: 64,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    final dx = (t * 160) - 80;
                    final bounce = sin(t * pi * 4) * 7;
                    return Stack(
                      children: [
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Divider(color: Colors.white54, thickness: 1),
                        ),
                        Positioned(
                          left: 58 + dx,
                          top: 10 - bounce,
                          child: const Icon(Icons.directions_run, color: Colors.white, size: 32),
                        ),
                        Positioned(
                          left: 88 + dx,
                          top: 14 - bounce,
                          child: const Icon(Icons.inventory_2, color: Color(0xFFE3F76A), size: 22),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
