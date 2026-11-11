import 'dart:async';

import 'package:flutter/foundation.dart';

import 'link_api.dart';
import 'models.dart';

class SessionController extends ChangeNotifier {
  SessionController(this.device, {LinkApi? api}) : _api = api ?? LinkApi();

  final LinkedDevice device;
  final LinkApi _api;
  Timer? _timer;
  bool _isDisposed = false;

  List<AgentSession> _sessions = const [];
  MonitoringStatus? status;
  String? error;
  bool isRefreshing = false;
  DateTime? lastUpdated;
  String statusFilter = 'All';
  String providerFilter = 'All';

  List<AgentSession> get sessions {
    final filtered = _sessions.where((session) {
      final statusMatches = statusFilter == 'All' ||
          (statusFilter == 'Working' && (session.status == 'Working' || session.status == 'Starting')) ||
          (statusFilter == 'Waiting' && session.status == 'WaitingUser') ||
          session.status == statusFilter;
      final providerMatches = providerFilter == 'All' || session.provider == providerFilter;
      return statusMatches && providerMatches;
    }).toList();
    filtered.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return b.lastActivityAt.compareTo(a.lastActivityAt);
    });
    return filtered;
  }

  int get totalCount => _sessions.length;

  Future<void> start() async {
    await refresh();
    if (!_isDisposed) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
    }
  }

  Future<void> refresh() async {
    if (isRefreshing) return;
    isRefreshing = true;
    notifyListeners();
    try {
      final results = await Future.wait([_api.status(device), _api.sessions(device)]);
      status = results[0] as MonitoringStatus;
      _sessions = results[1] as List<AgentSession>;
      lastUpdated = DateTime.now();
      error = null;
    } on LinkApiException catch (exception) {
      error = exception.message;
    } catch (exception) {
      error = '读取会话失败：$exception';
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

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
    super.dispose();
  }
}
