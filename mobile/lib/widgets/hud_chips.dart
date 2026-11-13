import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// ---------------------------------------------------------------------------
/// Provider icon mapping – semantic + recognizable at small sizes
/// ---------------------------------------------------------------------------
IconData hudProviderIcon(String provider) {
  switch (provider) {
    case 'Codex':
      return Icons.terminal_rounded;
    case 'Claude':
      return Icons.auto_awesome_rounded;
    case 'Pi':
      return Icons.hexagon_outlined;
    case 'OpenCode':
      return Icons.code_rounded;
    default:
      return Icons.smart_toy_outlined;
  }
}

/// ---------------------------------------------------------------------------
/// Status icon mapping – replaces plain dots with meaningful glyphs
/// ---------------------------------------------------------------------------
IconData hudStatusIcon(String status) {
  switch (status) {
    case 'Starting':
      return Icons.play_arrow_rounded;
    case 'Working':
      return Icons.bolt_rounded;
    case 'WaitingUser':
      return Icons.hourglass_top_rounded;
    case 'Completed':
      return Icons.check_rounded;
    case 'Failed':
      return Icons.error_outline_rounded;
    case 'Idle':
      return Icons.pause_circle_outline_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

/// ---------------------------------------------------------------------------
/// Provider glyph – rounded-square badge with gradient background
/// ---------------------------------------------------------------------------
class HudProviderGlyph extends StatelessWidget {
  const HudProviderGlyph({super.key, required this.provider, this.size = 18});

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.provider(provider);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          hudProviderIcon(provider),
          size: size * 0.52,
          color: color,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Status pill – compact badge with icon + label + optional pulse ring
/// ---------------------------------------------------------------------------
class HudStatusPill extends StatelessWidget {
  const HudStatusPill({
    super.key,
    required this.status,
    this.pulsing = false,
  });

  final String status;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.status(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.06),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(HudRadii.micro),
        border: Border.all(
          color: color.withValues(alpha: 0.32),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsing)
            _PulseRing(color: color)
          else
            Icon(
              hudStatusIcon(status),
              size: 10,
              color: color,
            ),
          const SizedBox(width: 4),
          Text(
            statusLabel(status),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Animated status dot with glow ring for list items
/// ---------------------------------------------------------------------------
class HudStatusDot extends StatelessWidget {
  const HudStatusDot({
    super.key,
    required this.color,
    required this.pulsing,
    this.size = 7,
  });

  final Color color;
  final bool pulsing;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!pulsing) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      );
    }
    return _AnimatedStatusDot(color: color, size: size);
  }
}

class _AnimatedStatusDot extends StatefulWidget {
  const _AnimatedStatusDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_AnimatedStatusDot> createState() => _AnimatedStatusDotState();
}

class _AnimatedStatusDotState extends State<_AnimatedStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;
        return SizedBox(
          width: widget.size + 6,
          height: widget.size + 6,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.4,
                child: Transform.scale(
                  scale: 1 + t * 1.2,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.45),
                      blurRadius: 6,
                      spreadRadius: 1.5,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------------
/// Tiny pulse ring used inside status pill
/// ---------------------------------------------------------------------------
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color});

  final Color color;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;
        return SizedBox(
          width: 10,
          height: 10,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.35,
                child: Transform.scale(
                  scale: 1 + t * 0.6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
