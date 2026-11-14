import 'dart:convert';

List<String> _addresses(
  Map<String, dynamic> value, {
  bool preferIpv6 = false,
}) {
  final ipv4 = (value['addresses'] as List?) ?? const [];
  final ipv6 = (value['ipv6Addresses'] as List?) ?? const [];
  final selected = preferIpv6 ? [...ipv6] : [...ipv4, ...ipv6];
  return selected.whereType<String>().where((item) => item.isNotEmpty).toList();
}

String normalizeLinkAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String formatLinkAddress(String address, int port) =>
    address.contains(':') && !address.startsWith('[')
        ? '[$address]:$port'
        : '$address:$port';

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

  factory PairingOffer.fromQr(
    String source, {
    bool preferIpv6 = false,
  }) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('二维码内容不是有效的 AgentHUD 配对信息');
    }
    if (value['v'] != 1) {
      throw const FormatException('不支持的配对协议版本');
    }
    final addresses = _addresses(value, preferIpv6: preferIpv6);
    if (addresses.isEmpty) {
      throw FormatException(
        preferIpv6 ? '配对信息中没有可用的 IPv6 地址' : '配对信息中没有可用的局域网地址',
      );
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
  Uri baseUri(String address) =>
      Uri(scheme: 'https', host: normalizeLinkAddress(address), port: port);

  factory LinkedDevice.fromPairing(Map<String, dynamic> value) => LinkedDevice(
        deviceId: value['deviceId'] as String,
        token: value['token'] as String,
        instanceId: value['instanceId'] as String,
        instanceName: value['instanceName'] as String? ?? 'AgentHUD',
        fingerprint: value['fingerprint'] as String,
        // 配对时勾选 IPv6 只决定「这一次先试哪个协议族」，设备必须同时保留
        // IPv4 与 IPv6，否则电脑换网（IPv6 前缀或 IPv4 变化）后旧地址全废，
        // 手机就再也连不上，只能重新扫码。
        addresses: _addresses(value),
        port: value['port'] as int,
      );

  LinkedDevice copyWith({List<String>? addresses, int? port}) => LinkedDevice(
        deviceId: deviceId,
        token: token,
        instanceId: instanceId,
        instanceName: instanceName,
        fingerprint: fingerprint,
        addresses: addresses ?? this.addresses,
        port: port ?? this.port,
      );

  factory LinkedDevice.fromJson(Map<String, dynamic> value) => LinkedDevice(
        deviceId: value['deviceId'] as String,
        token: value['token'] as String,
        instanceId: value['instanceId'] as String,
        instanceName: value['instanceName'] as String,
        fingerprint: value['fingerprint'] as String,
        addresses: _addresses(value),
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
    this.supportsRefresh = false,
    this.capabilities = const <String>{},
    this.addresses = const <String>[],
  });

  final int revision;
  final String instanceName;
  final bool privacyMode;
  final DateTime serverTime;
  final bool supportsRefresh;
  final Set<String> capabilities;

  /// 电脑当前真实的局域网地址，用于在电脑换网后自动更新本地保存的地址。
  final List<String> addresses;

  bool get supportsActions => capabilities.contains('write');
  bool get supportsPrompt => capabilities.contains('prompt');
  bool get supportsImages => capabilities.contains('images');
  bool get supportsConversation => capabilities.contains('conversation');

  MonitoringStatus copyWith({
    bool? supportsRefresh,
    Set<String>? capabilities,
    List<String>? addresses,
  }) =>
      MonitoringStatus(
        revision: revision,
        instanceName: instanceName,
        privacyMode: privacyMode,
        serverTime: serverTime,
        supportsRefresh: supportsRefresh ?? this.supportsRefresh,
        capabilities: capabilities ?? this.capabilities,
        addresses: addresses ?? this.addresses,
      );

  factory MonitoringStatus.fromJson(Map<String, dynamic> value) {
    final List<String> capabilities =
        (value['capabilities'] as List?)?.whereType<String>().toList() ??
            const <String>[];
    return MonitoringStatus(
      revision: value['revision'] as int,
      instanceName: value['instanceName'] as String? ?? 'AgentHUD',
      privacyMode: value['privacyMode'] as bool? ?? false,
      serverTime: DateTime.parse(value['serverTime'] as String),
      supportsRefresh: capabilities.contains('refresh'),
      capabilities: capabilities.toSet(),
      addresses: _addresses(value),
    );
  }
}

class PromptImageRef {
  const PromptImageRef({required this.index, required this.label});

  final int index;
  final String label;

  factory PromptImageRef.fromJson(Map<String, dynamic> value) => PromptImageRef(
        index: value['index'] as int? ?? 0,
        label: value['label'] as String? ?? '[图片]',
      );
}

class PromptSnapshot {
  const PromptSnapshot({
    required this.text,
    required this.sentAt,
    required this.images,
  });

  final String text;
  final DateTime? sentAt;
  final List<PromptImageRef> images;

  bool get isEmpty => text.isEmpty && images.isEmpty;

  factory PromptSnapshot.fromJson(Map<String, dynamic> value) => PromptSnapshot(
        text: value['text'] as String? ?? '',
        sentAt: value['sentAt'] == null
            ? null
            : DateTime.parse(value['sentAt'] as String),
        images: (value['images'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PromptImageRef.fromJson)
                .toList() ??
            const <PromptImageRef>[],
      );
}

class TaskRun {
  const TaskRun({
    required this.id,
    required this.objective,
    required this.summary,
    required this.actions,
    required this.filesChanged,
    required this.completedAt,
    required this.status,
  });

  final String id;
  final String objective;
  final String summary;
  final List<String> actions;
  final List<String> filesChanged;
  final DateTime completedAt;
  final String status;

  factory TaskRun.fromJson(Map<String, dynamic> value) => TaskRun(
        id: value['id'] as String,
        objective: value['objective'] as String? ?? '',
        summary: value['summary'] as String? ?? '',
        actions: (value['actions'] as List?)?.whereType<String>().toList() ??
            const <String>[],
        filesChanged:
            (value['filesChanged'] as List?)?.whereType<String>().toList() ??
                const <String>[],
        completedAt: DateTime.parse(value['completedAt'] as String),
        status: value['status'] as String? ?? 'Completed',
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
    this.titleSource = 'Automatic',
    this.hasCustomTitle = false,
    this.isImportant = false,
    this.latestPrompt,
    this.runs = const [],
    this.conversation,
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
  final String titleSource;
  final bool hasCustomTitle;
  final bool isImportant;
  final PromptSnapshot? latestPrompt;
  final List<TaskRun> runs;
  final ConversationState? conversation;

  bool get isActive =>
      status == 'Starting' || status == 'Working' || status == 'WaitingUser';

  bool get canSendMessage {
    if (conversation == null) return false;
    return conversation!.enabled &&
        (conversation!.state == 'ready' ||
            conversation!.state == 'waitingUser');
  }

  AgentSession copyWith({
    String? title,
    String? titleSource,
    bool? hasCustomTitle,
    bool? isImportant,
    PromptSnapshot? latestPrompt,
    List<TaskRun>? runs,
    ConversationState? conversation,
  }) =>
      AgentSession(
        id: id,
        provider: provider,
        status: status,
        confidence: confidence,
        title: title ?? this.title,
        projectName: projectName,
        currentAction: currentAction,
        currentFiles: currentFiles,
        startedAt: startedAt,
        lastActivityAt: lastActivityAt,
        completedAt: completedAt,
        isLive: isLive,
        summary: summary,
        gitBranch: gitBranch,
        gitChangedFiles: gitChangedFiles,
        gitInsertions: gitInsertions,
        gitDeletions: gitDeletions,
        titleSource: titleSource ?? this.titleSource,
        hasCustomTitle: hasCustomTitle ?? this.hasCustomTitle,
        isImportant: isImportant ?? this.isImportant,
        latestPrompt: latestPrompt ?? this.latestPrompt,
        runs: runs ?? this.runs,
        conversation: conversation ?? this.conversation,
      );

  factory AgentSession.fromJson(Map<String, dynamic> value) => AgentSession(
        id: value['id'] as String,
        provider: value['provider'] as String? ?? 'Unknown',
        status: value['status'] as String? ?? 'Unknown',
        confidence: value['confidence'] as String? ?? 'Low',
        title: value['title'] as String? ?? '未命名任务',
        projectName: value['projectName'] as String? ?? '未知项目',
        currentAction: value['currentAction'] as String? ?? '',
        currentFiles:
            (value['currentFiles'] as List?)?.whereType<String>().toList() ??
                const [],
        startedAt: DateTime.parse(value['startedAt'] as String),
        lastActivityAt: DateTime.parse(value['lastActivityAt'] as String),
        completedAt: value['completedAt'] == null
            ? null
            : DateTime.parse(value['completedAt'] as String),
        isLive: value['isLive'] as bool? ?? false,
        summary: value['summary'] as String?,
        gitBranch: value['gitBranch'] as String?,
        gitChangedFiles: value['gitChangedFiles'] as int?,
        gitInsertions: value['gitInsertions'] as int?,
        gitDeletions: value['gitDeletions'] as int?,
        titleSource: value['titleSource'] as String? ?? 'Automatic',
        hasCustomTitle: value['hasCustomTitle'] as bool? ?? false,
        isImportant: value['isImportant'] as bool? ?? false,
        latestPrompt: value['latestPrompt'] is Map<String, dynamic>
            ? PromptSnapshot.fromJson(
                value['latestPrompt'] as Map<String, dynamic>,
              )
            : null,
        runs: (value['runs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(TaskRun.fromJson)
                .toList() ??
            const <TaskRun>[],
        conversation: value['conversation'] is Map<String, dynamic>
            ? ConversationState.fromJson(
                value['conversation'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ConversationState {
  const ConversationState({
    required this.enabled,
    required this.state,
    this.reason,
  });

  final bool enabled;
  final String state;
  final String? reason;

  factory ConversationState.fromJson(Map<String, dynamic> value) =>
      ConversationState(
        enabled: value['enabled'] as bool? ?? false,
        state: value['state'] as String? ?? 'unsupported',
        reason: value['reason'] as String?,
      );
}

class MessageDelivery {
  const MessageDelivery({
    required this.deliveryId,
    required this.clientMessageId,
    required this.status,
    this.error,
  });

  final String deliveryId;
  final String clientMessageId;
  final String status;
  final String? error;

  factory MessageDelivery.fromJson(Map<String, dynamic> value) =>
      MessageDelivery(
        deliveryId: value['deliveryId'] as String? ?? '',
        clientMessageId: value['clientMessageId'] as String? ?? '',
        status: value['status'] as String? ?? 'failed',
        error: value['error'] as String?,
      );

  bool get isFinal =>
      status == 'observed' || status == 'failed' || status == 'delivered';
}

String relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inSeconds < 60) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
  if (difference.inHours < 24) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  return '${value.year}/${value.month}/${value.day}';
}

String titleSourceLabel(String value) => switch (value) {
      'AI' => 'AI 概括',
      'User' => '我的备注',
      'Automatic' => '本地概括',
      _ => '自动标题',
    };

String statusLabel(String value) => switch (value) {
      'Starting' => '启动中',
      'Working' => '工作中',
      'WaitingUser' => '等待确认',
      'Idle' => '空闲',
      'Completed' => '已完成',
      'Failed' => '出错',
      _ => '状态待确认',
    };
