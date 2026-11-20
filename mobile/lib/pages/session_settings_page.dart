import 'package:flutter/material.dart';

import '../session_controller.dart';
import '../session_preferences.dart';
import '../theme.dart';

class SessionSettingsPage extends StatelessWidget {
  const SessionSettingsPage({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会话显示设置')),
      body: HudScaffoldBackground(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(HudSpacing.xl),
            children: [
              Text(
                '显示多少会话',
                style: HudText.title.copyWith(fontSize: 17),
              ),
              const SizedBox(height: HudSpacing.sm),
              Text(
                '默认只保留最近 10 条，减少长列表干扰。星标会话始终常驻，不占这个数量。',
                style: HudText.body.copyWith(color: HudColors.textSecondary),
              ),
              const SizedBox(height: HudSpacing.lg),
              for (final limit in SessionListLimit.values)
                _LimitOption(
                  limit: limit,
                  selected: controller.listLimit == limit,
                  onSelected: () => controller.setListLimit(limit),
                ),
              const SizedBox(height: HudSpacing.lg),
              Container(
                padding: const EdgeInsets.all(HudSpacing.lg),
                decoration: BoxDecoration(
                  color: HudColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: const Border.fromBorderSide(
                    BorderSide(color: HudColors.border),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '指定常驻会话',
                      style: HudText.title.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: HudSpacing.sm),
                    Text(
                      '在会话卡片上点星标，或进入详情页点星标，就会固定保留在列表中。星标状态与电脑同步。',
                      style: HudText.body.copyWith(
                        color: HudColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitOption extends StatelessWidget {
  const _LimitOption({
    required this.limit,
    required this.selected,
    required this.onSelected,
  });

  final SessionListLimit limit;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? HudColors.working : HudColors.textTertiary,
      ),
      title: Text(limit.label),
      subtitle:
          limit == SessionListLimit.all ? const Text('显示服务端返回的全部会话') : null,
      onTap: onSelected,
      contentPadding: EdgeInsets.zero,
    );
  }
}
