import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../device_store.dart';
import '../models.dart';
import 'pairing_page.dart';
import 'sessions_page.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('AgentHUD'), centerTitle: false),
      body: store.isEmpty ? const _EmptyDevices() : ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('已关联电脑', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          for (final device in store.devices) _DeviceCard(device: device),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PairingPage()),
        ),
        icon: const Icon(Icons.add_link),
        label: const Text('关联电脑'),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final LinkedDevice device;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: const CircleAvatar(child: Icon(Icons.computer)),
        title: Text(device.instanceName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${device.addresses.first}:${device.port} · 只读监控'),
        trailing: IconButton(
          icon: const Icon(Icons.link_off),
          tooltip: '移除设备',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('移除这台电脑？'),
                content: const Text('手机会删除本机保存的设备令牌。'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除')),
                ],
              ),
            );
            if (confirmed == true && context.mounted) {
              await context.read<DeviceStore>().remove(device.id);
            }
          },
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SessionsPage(device: device)),
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 58, color: Color(0xFF60A5FA)),
            SizedBox(height: 18),
            Text('还没有关联电脑', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            Text(
              '在 Windows AgentHUD 中打开“手机关联”，使用手机扫码或输入验证码即可开始只读监控。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9AA8BA), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
