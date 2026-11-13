import 'dart:async';

import 'package:flutter/foundation.dart';

import 'link_api.dart';
import 'models.dart';

class SessionController extends ChangeNotifier {
  SessionController(this.device, {MonitoringApi? api})
      : _api = api ?? LinkApi();

  final LinkedDevice device;
  final MonitoringApi _api;
  Timer? _timer;
  bool _isDisposed = false;
  int _consecutiveFailures = 0;
  DateTime? _nextRetryAt;

  List<AgentSession> _sessions = const [];
  String? _sessionsEtag;
  final Map<String, Uint8List> _imageCache = {};
  final Map<String, Future<Uint8List>> _imageRequests = {};
  MonitoringStatus? status;
  String? error;
  String? actionError;
  bool isRefreshing = false;
  DateTime? lastUpdated;
  String statusFilter = 'All';
  String providerFilter = 'All';

  SessionActionsApi? get _actions =>
      _api is SessionActionsApi ? _api as SessionActionsApi : null;

  bool get supportsActions => status?.supportsActions ?? false;
  bool get supportsPrompt => status?.supportsPrompt ?? false;
  bool get supportsImages => status?.supportsImages ?? false;
  bool get supportsConversation => status?.supportsConversation ?? false;

  final Map<String, MessageDelivery> _deliveries = {};
  final Map<String, Timer> _deliveryPollers = {};

  List<AgentSession> get sessions {
    final filtered = _sessions.where((session) {
      final statusMatches = _matchesStatus(session.status, statusFilter);
      final providerMatches =
          providerFilter == 'All' || session.provider == providerFilter;
      return statusMatches && providerMatches;
    }).toList();
    filtered.sort((a, b) {
      if (a.isImportant != b.isImportant) return a.isImportant ? -1 : 1;
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return b.lastActivityAt.compareTo(a.lastActivityAt);
    });
    return filtered;
  }

  AgentSession? sessionById(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  int get totalCount => _sessions.length;

  int countForStatus(String filter) => _sessions
      .where((session) => _matchesStatus(session.status, filter))
      .length;

  int countForProvider(String filter) => filter == 'All'
      ? _sessions.length
      : _sessions.where((session) => session.provider == filter).length;

  bool _matchesStatus(String status, String filter) {
    if (filter == 'All') return true;
    if (filter == 'Working') return status == 'Working' || status == 'Starting';
    if (filter == 'Waiting') return status == 'WaitingUser';
    return status == filter;
  }

  Future<void> start() async {
    await refresh(scan: true);
    if (!_isDisposed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final active = _sessions.any((session) => session.isActive);
        final interval = active ? 1 : 2;
        final last = lastUpdated;
        if (last == null ||
            DateTime.now().difference(last) >= Duration(seconds: interval)) {
          refresh();
        }
      });
    }
  }

  Future<void> refresh({bool scan = false}) async {
    if (isRefreshing || _isDisposed) return;
    if (!scan &&
        _nextRetryAt != null &&
        DateTime.now().isBefore(_nextRetryAt!)) {
      return;
    }
    isRefreshing = true;
    if (lastUpdated == null) notifyListeners();
    try {
      var current = await _api.status(device);
      if (scan && current.supportsRefresh) {
        final supported = await _api.refresh(device);
        if (!supported) {
          current = current.copyWith(supportsRefresh: false);
        } else {
          current = await _api.status(device);
        }
      }
      status = current;
      final result = await _api.sessions(device, etag: _sessionsEtag);
      if (result.sessions != null) _sessions = result.sessions!;
      _sessionsEtag = result.etag;
      lastUpdated = DateTime.now();
      _consecutiveFailures = 0;
      _nextRetryAt = null;
      error = null;
    } on LinkApiException catch (exception) {
      _recordFailure();
      error = exception.message;
    } catch (exception) {
      _recordFailure();
      error = '读取会话失败：$exception';
    } finally {
      isRefreshing = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  void _recordFailure() {
    _consecutiveFailures += 1;
    _nextRetryAt = DateTime.now().add(
      Duration(seconds: _consecutiveFailures >= 3 ? 5 : 2),
    );
  }

  Future<bool> renameSession(AgentSession session, String title) async {
    final SessionActionsApi? actions = _actions;
    if (actions == null) {
      actionError = '当前电脑版本不支持远程改名。';
      notifyListeners();
      return false;
    }
    final int index = _sessions.indexWhere((item) => item.id == session.id);
    if (index < 0) return false;

    final String normalized = title.trim();
    final AgentSession previous = _sessions[index];
    final bool hasCustom = normalized.isNotEmpty;
    _sessions = List<AgentSession>.of(_sessions)
      ..[index] = previous.copyWith(
        title: hasCustom ? normalized : previous.title,
        titleSource: hasCustom ? 'User' : 'Automatic',
        hasCustomTitle: hasCustom,
      );
    actionError = null;
    notifyListeners();

    try {
      final String applied =
          await actions.setSessionTitle(device, session.id, normalized);
      final int updated = _sessions.indexWhere((item) => item.id == session.id);
      if (updated >= 0) {
        _sessions = List<AgentSession>.of(_sessions)
          ..[updated] = _sessions[updated].copyWith(
            title: applied,
            titleSource: hasCustom ? 'User' : 'Automatic',
            hasCustomTitle: hasCustom,
          );
      }
      notifyListeners();
      await refresh();
      return true;
    } catch (exception) {
      final int rollback =
          _sessions.indexWhere((item) => item.id == session.id);
      if (rollback >= 0) {
        _sessions = List<AgentSession>.of(_sessions)..[rollback] = previous;
      }
      actionError = '改名失败：${_message(exception)}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setImportant(AgentSession session, bool important) async {
    final SessionActionsApi? actions = _actions;
    if (actions == null) {
      actionError = '当前电脑版本不支持远程星标。';
      notifyListeners();
      return false;
    }
    final int index = _sessions.indexWhere((item) => item.id == session.id);
    if (index < 0) return false;

    final AgentSession previous = _sessions[index];
    _sessions = List<AgentSession>.of(_sessions)
      ..[index] = previous.copyWith(isImportant: important);
    actionError = null;
    notifyListeners();

    try {
      final bool applied =
          await actions.setSessionImportant(device, session.id, important);
      final int updated = _sessions.indexWhere((item) => item.id == session.id);
      if (updated >= 0) {
        _sessions = List<AgentSession>.of(_sessions)
          ..[updated] = _sessions[updated].copyWith(isImportant: applied);
      }
      notifyListeners();
      await refresh();
      return true;
    } catch (exception) {
      final int rollback =
          _sessions.indexWhere((item) => item.id == session.id);
      if (rollback >= 0) {
        _sessions = List<AgentSession>.of(_sessions)..[rollback] = previous;
      }
      actionError = '星标失败：${_message(exception)}';
      notifyListeners();
      return false;
    }
  }

  Future<Uint8List?> loadPromptImage(String sessionId, int index) async {
    final String key = '$sessionId:$index';
    final Uint8List? cached = _imageCache[key];
    if (cached != null) return cached;
    final Future<Uint8List>? pending = _imageRequests[key];
    if (pending != null) {
      try {
        return await pending;
      } catch (exception) {
        return null;
      }
    }

    final SessionActionsApi? actions = _actions;
    if (actions == null || !supportsImages) return null;
    final Future<Uint8List> request =
        actions.promptImage(device, sessionId, index);
    _imageRequests[key] = request;
    try {
      final Uint8List bytes = await request;
      if (bytes.isNotEmpty) _imageCache[key] = bytes;
      return bytes;
    } catch (exception) {
      return null;
    } finally {
      _imageRequests.remove(key);
    }
  }

  Future<MessageDelivery?> sendMessage(
    AgentSession session,
    String clientMessageId,
    String text,
  ) async {
    final SessionActionsApi? actions = _actions;
    if (actions == null || !supportsConversation) {
      actionError = '当前电脑或设备未开启对话模式。';
      notifyListeners();
      return null;
    }
    if (!session.canSendMessage) {
      actionError = _conversationReason(session) ?? '当前会话无法接收消息。';
      notifyListeners();
      return null;
    }
    actionError = null;
    notifyListeners();
    try {
      final MessageDelivery delivery = await actions.sendMessage(
        device,
        session.id,
        clientMessageId,
        text,
      );
      _deliveries[delivery.deliveryId] = delivery;
      notifyListeners();
      _pollDelivery(delivery.deliveryId);
      return delivery;
    } catch (exception) {
      actionError = '发送失败：${_message(exception)}';
      notifyListeners();
      return null;
    }
  }

  MessageDelivery? deliveryStatus(String deliveryId) => _deliveries[deliveryId];

  void _pollDelivery(String deliveryId) {
    _deliveryPollers[deliveryId]?.cancel();
    _deliveryPollers[deliveryId] = Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) async {
        final SessionActionsApi? actions = _actions;
        if (actions == null) {
          timer.cancel();
          return;
        }
        try {
          final MessageDelivery delivery =
              await actions.deliveryStatus(device, deliveryId);
          _deliveries[deliveryId] = delivery;
          if (!_isDisposed) notifyListeners();
          if (delivery.isFinal) {
            timer.cancel();
            _deliveryPollers.remove(deliveryId);
          }
        } catch (exception) {
          timer.cancel();
          _deliveryPollers.remove(deliveryId);
        }
      },
    );
  }

  String? _conversationReason(AgentSession session) {
    if (session.conversation == null) return null;
    return session.conversation!.reason;
  }

  void clearActionError() {
    if (actionError == null) return;
    actionError = null;
    notifyListeners();
  }

  static String _message(Object exception) =>
      exception is LinkApiException ? exception.message : '$exception';

  void setStatusFilter(String value) {
    statusFilter = value;
    notifyListeners();
  }

  void setProviderFilter(String value) {
    providerFilter = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    for (final Timer timer in _deliveryPollers.values) {
      timer.cancel();
    }
    _deliveryPollers.clear();
    _api.close();
    super.dispose();
  }
}
