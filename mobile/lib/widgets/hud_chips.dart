import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Provider icon mapping – semantic + recognizable at small sizes.
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

/// Status icon mapping.
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

/// Provider badge – quiet tinted square with a hairline ring.
class HudProviderGlyph extends StatelessWidget {
  const HudProviderGlyph({super.key, required this.provider, this.size = 22});

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.provider(provider);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Center(
        child: Icon(
          hudProviderIcon(provider),
          size: size * 0.54,
          color: color,
        ),
      ),
    );
  }
}

/// Provider name + glyph in one compact line.
class HudProviderTag extends StatelessWidget {
  const HudProviderTag({super.key, required this.provider, this.size = 18});

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.provider(provider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HudProviderGlyph(provider: provider, size: size),
        const SizedBox(width: HudSpacing.sm),
        Text(
          provider,
          style: HudText.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Status pill – dot + label, no gradient, no glow.
class HudStatusPill extends StatelessWidget {
  const HudStatusPill({
    super.key,
    required this.status,
    this.pulsing = false,
    this.dense = false,
  });

  final String status;
  final bool pulsing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.status(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 8,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HudStatusDot(
            color: color,
            pulsing: pulsing,
            size: dense ? 5 : 6,
          ),
          const SizedBox(width: 5),
          Text(
            statusLabel(status),
            style: TextStyle(
              fontSize: dense ? 10.5 : 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status dot. Pulsing uses a soft expanding ring; static stays flat.
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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
      duration: HudMotion.pulse,
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
          width: widget.size + 5,
          height: widget.size + 5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.28,
                child: Transform.scale(
                  scale: 1 + t * 1.4,
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Neutral key-value row used by detail sections.
class HudFactRow extends StatelessWidget {
  const HudFactRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor = HudColors.textPrimary,
    this.mono = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: HudColors.textTertiary),
            const SizedBox(width: HudSpacing.md),
          ],
          SizedBox(
            width: 84,
            child: Text(label, style: HudText.caption),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: (mono ? HudText.mono : HudText.bodySecondary).copyWith(
                color: valueColor,
                fontSize: mono ? 11.5 : 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
