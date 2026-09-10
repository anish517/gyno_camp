import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/postgres_database_service.dart';
import '../core/services/session_service.dart';

class PostgresConfigState {
  final PostgresConfig config;
  final bool isTesting;
  final bool isMigrating;
  final bool isSyncing;
  final int? testLatencyMs;
  final String? testError;
  final PostgresSyncResult? lastSyncResult;
  final String? statusMessage;

  const PostgresConfigState({
    required this.config,
    this.isTesting = false,
    this.isMigrating = false,
    this.isSyncing = false,
    this.testLatencyMs,
    this.testError,
    this.lastSyncResult,
    this.statusMessage,
  });

  bool get isOperational => testLatencyMs != null && testError == null;

  PostgresConfigState copyWith({
    PostgresConfig? config,
    bool? isTesting,
    bool? isMigrating,
    bool? isSyncing,
    int? testLatencyMs,
    String? testError,
    PostgresSyncResult? lastSyncResult,
    String? statusMessage,
    bool clearTest = false,
  }) {
    return PostgresConfigState(
      config: config ?? this.config,
      isTesting: isTesting ?? this.isTesting,
      isMigrating: isMigrating ?? this.isMigrating,
      isSyncing: isSyncing ?? this.isSyncing,
      testLatencyMs: clearTest ? null : (testLatencyMs ?? this.testLatencyMs),
      testError: clearTest ? null : (testError ?? this.testError),
      lastSyncResult: lastSyncResult ?? this.lastSyncResult,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class PostgresConfigViewModel extends StateNotifier<PostgresConfigState> {
  final PostgresDatabaseService _postgresService;

  PostgresConfigViewModel({PostgresDatabaseService? postgresService})
      : _postgresService = postgresService ?? PostgresDatabaseService(),
        super(PostgresConfigState(
          config: SessionService.current?.getPostgresConfig() ?? const PostgresConfig(),
        ));

  void updateConfig(PostgresConfig newConfig) {
    state = state.copyWith(config: newConfig, clearTest: true);
    SessionService.current?.savePostgresConfig(newConfig);
  }

  Future<bool> testConnection() async {
    state = state.copyWith(isTesting: true, clearTest: true, statusMessage: 'Connecting to PostgreSQL server...');
    try {
      final latency = await _postgresService.testConnection(state.config);
      state = state.copyWith(
        isTesting: false,
        testLatencyMs: latency,
        statusMessage: 'Connection verified successfully! ($latency ms latency)',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isTesting: false,
        testError: e.toString(),
        statusMessage: 'Connection failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<bool> initializeSchema() async {
    state = state.copyWith(isMigrating: true, statusMessage: 'Verifying and creating database tables...');
    try {
      await _postgresService.initializePostgresSchema(config: state.config);
      state = state.copyWith(
        isMigrating: false,
        statusMessage: 'All PostgreSQL tables & indexes verified successfully!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isMigrating: false,
        testError: e.toString(),
        statusMessage: 'Schema initialization failed: $e',
      );
      return false;
    }
  }

  Future<PostgresSyncResult?> syncAllData() async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Synchronizing SQLite records to PostgreSQL...');
    try {
      final result = await _postgresService.syncSqliteToPostgres(config: state.config);
      if (result.success) {
        state = state.copyWith(
          isSyncing: false,
          lastSyncResult: result,
          statusMessage: 'Sync completed! ${result.totalRecords} records synced (${result.syncedPatients} patients, ${result.syncedVisits} visits).',
        );
      } else {
        state = state.copyWith(
          isSyncing: false,
          lastSyncResult: result,
          statusMessage: 'Sync encountered an error: ${result.errorMessage}',
        );
      }
      return result;
    } catch (e) {
      final failedResult = PostgresSyncResult(success: false, errorMessage: e.toString());
      state = state.copyWith(
        isSyncing: false,
        lastSyncResult: failedResult,
        statusMessage: 'Sync execution error: $e',
      );
      return failedResult;
    }
  }
}

final postgresConfigProvider = StateNotifierProvider<PostgresConfigViewModel, PostgresConfigState>((ref) {
  return PostgresConfigViewModel();
});
