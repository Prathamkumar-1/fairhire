import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FairnessScoreRing extends StatefulWidget {
  final double score;
  final double size;
  final bool animate;

  const FairnessScoreRing({
    super.key,
    required this.score,
    this.size = 160,
    this.animate = true,
  });

  @override
  State<FairnessScoreRing> createState() => _FairnessScoreRingState();
}

class _FairnessScoreRingState extends State<FairnessScoreRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0, end: widget.score / 100).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _verdictLabel() {
    if (widget.score >= 80) return 'PASS';
    if (widget.score >= 60) return 'CAUTION';
    return 'FAIL';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.scoreColor(widget.score);

    return Semantics(
      label:
          'Fairness score: ${widget.score.toStringAsFixed(0)} out of 100, ${_verdictLabel()}',
      child: AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        final progress = _animation.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: widget.size * 0.09,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: widget.size * 0.26,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                  Text(
                    '/ 100',
                    style: TextStyle(
                      fontSize: widget.size * 0.1,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ), // AnimatedBuilder
    ); // Semantics
  }
}
