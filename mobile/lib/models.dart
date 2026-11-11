import 'dart:convert';

class PairingOffer {
  const PairingOffer({
    required this.instanceId,
    required this.instanceName,
    required this.addresses,
    required this.port,
    required this.fingerprint,
    required this.sessionId,
    required this.secret,
    required this.expiresAt,
  });

  final String instanceId;
  final String instanceName;
  final List<String> addresses;
  final int port;
  final String fingerprint;
  final String sessionId;
  final String secret;
  final DateTime expiresAt;

  factory PairingOffer.fromQr(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('二维码内容不是有效的 AgentHUD 配对信息');
    }
    if (value['v'] != 1) {
      throw const FormatException('不支持的配对协议版本');
    }
    final addresses = (value['addresses'] as List?)
        ?.whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
    if (addresses == null || addresses.isEmpty) {
      throw const FormatException('配对信息中没有可用的局域网地址');
    }
    return PairingOffer(
      instanceId: value['instanceId'] as String,
      instanceName: value['instanceName'] as String? ?? 'AgentHUD',
      addresses: addresses,
      port: value['port'] as int,
      fingerprint: value['fingerprint'] as String,
      sessionId: value['sessionId'] as String,
      secret: value['secret'] as String,
      expiresAt: DateTime.parse(value['expiresAt'] as String),
    );
  }
}

class LinkedDevice {
  const LinkedDevice({
    required this.deviceId,
    required this.token,
    required this.instanceId,
    required this.instanceName,
    required this.fingerprint,
    required this.addresses,
    required this.port,
  });

  final String deviceId;
  final String token;
  final String instanceId;
  final String instanceName;
  final String fingerprint;
  final List<String> addresses;
  final int port;

  String get id => '$instanceId/$deviceId';
  String get authorization => '$deviceId.$token';
  Uri baseUri(String address) => Uri(scheme: 'https', host: address, port: port);

  factory LinkedDevice.fromPairing(Map<String, dynamic> value) => LinkedDevice(
        deviceId: value['deviceId'] as String,
        token: value['token'] as String,
        instanceId: value['instanceId'] as String,
        instanceName: value['instanceName'] as String? ?? 'AgentHUD',
        fingerprint: value['fingerprint'] as String,
        addresses: (value['addresses'] as List).whereType<String>().toList(),
        port: value['port'] as int,
      );

  factory LinkedDevice.fromJson(Map<String, dynamic> value) => LinkedDevice(
        deviceId: value['deviceId'] as String,
        token: value['token'] as String,
        instanceId: value['instanceId'] as String,
        instanceName: value['instanceName'] as String,
        fingerprint: value['fingerprint'] as String,
        addresses: (value['addresses'] as List).whereType<String>().toList(),
        port: value['port'] as int,
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'token': token,
        'instanceId': instanceId,
        'instanceName': instanceName,
        'fingerprint': fingerprint,
        'addresses': addresses,
        'port': port,
      };
}

class MonitoringStatus {
  const MonitoringStatus({
    required this.revision,
    required this.instanceName,
    required this.privacyMode,
    required this.serverTime,
  });

  final int revision;
  final String instanceName;
  final bool privacyMode;
  final DateTime serverTime;

  factory MonitoringStatus.fromJson(Map<String, dynamic> value) => MonitoringStatus(
        revision: value['revision'] as int,
        instanceName: value['instanceName'] as String? ?? 'AgentHUD',
        privacyMode: value['privacyMode'] as bool? ?? false,
        serverTime: DateTime.parse(value['serverTime'] as String),
      );
}

class AgentSession {
  const AgentSession({
    required this.id,
    required this.provider,
    required this.status,
    required this.confidence,
    required this.title,
    required this.projectName,
    required this.currentAction,
    required this.currentFiles,
    required this.startedAt,
    required this.lastActivityAt,
    required this.completedAt,
    required this.isLive,
    required this.summary,
    required this.gitBranch,
    required this.gitChangedFiles,
    required this.gitInsertions,
    required this.gitDeletions,
  });

  final String id;
  final String provider;
  final String status;
  final String confidence;
  final String title;
  final String projectName;
  final String currentAction;
  final List<String> currentFiles;
  final DateTime startedAt;
  final DateTime lastActivityAt;
  final DateTime? completedAt;
  final bool isLive;
  final String? summary;
  final String? gitBranch;
  final int? gitChangedFiles;
  final int? gitInsertions;
  final int? gitDeletions;

  bool get isActive => status == 'Starting' || status == 'Working' || status == 'WaitingUser';

  factory AgentSession.fromJson(Map<String, dynamic> value) => AgentSession(
        id: value['id'] as String,
        provider: value['provider'] as String? ?? 'Unknown',
        status: value['status'] as String? ?? 'Unknown',
        confidence: value['confidence'] as String? ?? 'Low',
        title: value['title'] as String? ?? '未命名任务',
        projectName: value['projectName'] as String? ?? '未知项目',
        currentAction: value['currentAction'] as String? ?? '',
        currentFiles: (value['currentFiles'] as List?)?.whereType<String>().toList() ?? const [],
        startedAt: DateTime.parse(value['startedAt'] as String),
        lastActivityAt: DateTime.parse(value['lastActivityAt'] as String),
        completedAt: value['completedAt'] == null ? null : DateTime.parse(value['completedAt'] as String),
        isLive: value['isLive'] as bool? ?? false,
        summary: value['summary'] as String?,
        gitBranch: value['gitBranch'] as String?,
        gitChangedFiles: value['gitChangedFiles'] as int?,
        gitInsertions: value['gitInsertions'] as int?,
        gitDeletions: value['gitDeletions'] as int?,
      );
}

String relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inSeconds < 60) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
  if (difference.inHours < 24) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  return '${value.year}/${value.month}/${value.day}';
}

String statusLabel(String value) => switch (value) {
      'Starting' => '启动中',
      'Working' => '工作中',
      'WaitingUser' => '等待确认',
      'Idle' => '空闲',
      'Completed' => '已完成',
      'Failed' => '出错',
      _ => '未知',
    };
