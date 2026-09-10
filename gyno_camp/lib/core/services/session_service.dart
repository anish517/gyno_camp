import 'package:shared_preferences/shared_preferences.dart';

class PostgresConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool useSsl;
  final bool isDirectModeEnabled;

  const PostgresConfig({
    this.host = 'localhost',
    this.port = 5432,
    this.database = 'gynocamp_db',
    this.username = 'postgres',
    this.password = 'postgres',
    this.useSsl = false,
    this.isDirectModeEnabled = false,
  });

  PostgresConfig copyWith({
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    bool? useSsl,
    bool? isDirectModeEnabled,
  }) {
    return PostgresConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      isDirectModeEnabled: isDirectModeEnabled ?? this.isDirectModeEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'password': password,
      'useSsl': useSsl,
      'isDirectModeEnabled': isDirectModeEnabled,
    };
  }
}

class SessionService {
  static const String _keyUserId = 'gynocamp_session_user_id';
  static const String _keyUserEmail = 'gynocamp_session_user_email';
  static const String _keyUserRole = 'gynocamp_session_user_role';
  static const String _keyActiveCampId = 'gynocamp_session_active_camp_id';

  static const String _keyPgHost = 'gynocamp_pg_host';
  static const String _keyPgPort = 'gynocamp_pg_port';
  static const String _keyPgDatabase = 'gynocamp_pg_database';
  static const String _keyPgUsername = 'gynocamp_pg_username';
  static const String _keyPgPassword = 'gynocamp_pg_password';
  static const String _keyPgUseSsl = 'gynocamp_pg_use_ssl';
  static const String _keyPgDirectMode = 'gynocamp_pg_direct_mode';

  static SessionService? _instance;
  final SharedPreferences? _prefs;

  SessionService._(this._prefs);

  static Future<SessionService> getInstance([SharedPreferences? mockPrefs]) async {
    if (mockPrefs != null) {
      _instance = SessionService._(mockPrefs);
      return _instance!;
    }
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = SessionService._(prefs);
    }
    return _instance!;
  }

  /// Synchronous getter if already initialized
  static SessionService? get current => _instance;

  // Session & Authentication
  Future<void> saveUserSession({
    required String userId,
    required String email,
    required String role,
  }) async {
    if (_prefs == null) return;
    await _prefs.setString(_keyUserId, userId);
    await _prefs.setString(_keyUserEmail, email);
    await _prefs.setString(_keyUserRole, role);
  }

  String? getSavedUserId() => _prefs?.getString(_keyUserId);
  String? getSavedUserEmail() => _prefs?.getString(_keyUserEmail);
  String? getSavedUserRole() => _prefs?.getString(_keyUserRole);
  bool hasActiveSession() => getSavedUserId() != null && getSavedUserId()!.isNotEmpty;

  Future<void> clearSession() async {
    if (_prefs == null) return;
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserRole);
  }

  // Active Camp
  Future<void> saveActiveCampId(String campId) async {
    if (_prefs == null) return;
    await _prefs.setString(_keyActiveCampId, campId);
  }

  String? getSavedActiveCampId() => _prefs?.getString(_keyActiveCampId);

  Future<void> clearActiveCampId() async {
    if (_prefs == null) return;
    await _prefs.remove(_keyActiveCampId);
  }

  // PostgreSQL Connection Configuration
  Future<void> savePostgresConfig(PostgresConfig config) async {
    if (_prefs == null) return;
    await _prefs.setString(_keyPgHost, config.host);
    await _prefs.setInt(_keyPgPort, config.port);
    await _prefs.setString(_keyPgDatabase, config.database);
    await _prefs.setString(_keyPgUsername, config.username);
    await _prefs.setString(_keyPgPassword, config.password);
    await _prefs.setBool(_keyPgUseSsl, config.useSsl);
    await _prefs.setBool(_keyPgDirectMode, config.isDirectModeEnabled);
  }

  PostgresConfig getPostgresConfig() {
    if (_prefs == null) return const PostgresConfig();
    return PostgresConfig(
      host: _prefs.getString(_keyPgHost) ?? 'localhost',
      port: _prefs.getInt(_keyPgPort) ?? 5432,
      database: _prefs.getString(_keyPgDatabase) ?? 'gynocamp_db',
      username: _prefs.getString(_keyPgUsername) ?? 'postgres',
      password: _prefs.getString(_keyPgPassword) ?? 'postgres',
      useSsl: _prefs.getBool(_keyPgUseSsl) ?? false,
      isDirectModeEnabled: _prefs.getBool(_keyPgDirectMode) ?? false,
    );
  }
}
