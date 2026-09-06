import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audit_log_model.dart';
import '../repositories/audit_repository.dart';

class AuditLogState {
  final List<AuditLogModel> logs;
  final bool isLoading;
  final String? errorMessage;

  const AuditLogState({
    this.logs = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  AuditLogState copyWith({
    List<AuditLogModel>? logs,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuditLogState(
      logs: logs ?? this.logs,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuditLogViewModel extends StateNotifier<AuditLogState> {
  final IAuditRepository _repository;

  AuditLogViewModel(this._repository) : super(const AuditLogState()) {
    loadRecentLogs();
  }

  Future<void> loadRecentLogs() async {
    state = state.copyWith(isLoading: true);
    try {
      final logs = await _repository.getRecentLogs(limit: 100);
      state = state.copyWith(logs: logs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final auditRepositoryProvider = Provider<IAuditRepository>((ref) {
  return AuditRepository();
});

final auditLogProvider = StateNotifierProvider<AuditLogViewModel, AuditLogState>((ref) {
  final repo = ref.watch(auditRepositoryProvider);
  return AuditLogViewModel(repo);
});
