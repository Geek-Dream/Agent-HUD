import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

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
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(HudRadii.micro),
      ),
      child: Icon(
        hudProviderIcon(provider),
        size: size * 0.62,
        color: color,
      ),
    );
  }
}

class HudStatusPill extends StatelessWidget {
  const HudStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color = HudColors.status(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(HudRadii.micro),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
