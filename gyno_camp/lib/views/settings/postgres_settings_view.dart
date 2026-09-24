import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/services/http_central_api_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/postgres_config_viewmodel.dart';

class PostgresSettingsView extends ConsumerStatefulWidget {
  const PostgresSettingsView({super.key});

  @override
  ConsumerState<PostgresSettingsView> createState() => _PostgresSettingsViewState();
}

class _PostgresSettingsViewState extends ConsumerState<PostgresSettingsView> {
  late TextEditingController _centralApiUrlController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _databaseController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _useSsl = false;
  bool _directMode = false;

  bool _isTestingCentralApi = false;
  String? _centralApiStatus;
  bool? _centralApiOnline;

  @override
  void initState() {
    super.initState();
    final savedCentral = SessionService.current?.getCentralServerUrl() ?? 'http://192.168.1.4:8080';
    _centralApiUrlController = TextEditingController(text: savedCentral);
    final config = ref.read(postgresConfigProvider).config;
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _databaseController = TextEditingController(text: config.database);
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
    _useSsl = config.useSsl;
    _directMode = config.isDirectModeEnabled;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _centralApiUrlController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testCentralApi() async {
    final target = _centralApiUrlController.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _isTestingCentralApi = true;
      _centralApiStatus = 'Pinging $target/health...';
      _centralApiOnline = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('$target/health');
      final client = http.Client();
      final res = await client.get(uri).timeout(const Duration(seconds: 4));
      stopwatch.stop();
      if (res.statusCode == 200) {
        setState(() {
          _isTestingCentralApi = false;
          _centralApiOnline = true;
          _centralApiStatus = 'Central Cloud Sync API is ONLINE! (${stopwatch.elapsedMilliseconds} ms latency)';
        });
        HttpCentralApiService.markServerOnline(target);
        await SessionService.current?.saveCentralServerUrl(target);
      } else {
        setState(() {
          _isTestingCentralApi = false;
          _centralApiOnline = false;
          _centralApiStatus = 'Server reachable but returned HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _isTestingCentralApi = false;
        _centralApiOnline = false;
        _centralApiStatus = 'Connection failed: Cannot reach $target. Check IP and Wi-Fi connection.';
      });
    }
  }

  Future<void> _autoDetectCentralApi() async {
    setState(() {
      _isTestingCentralApi = true;
      _centralApiStatus = 'Probing candidate host IPs...';
      _centralApiOnline = null;
    });
    final candidates = [
      'http://192.168.1.4:8080',
      'http://127.0.0.1:8080',
      'http://192.168.1.110:8080',
      'http://localhost:8080',
      'http://10.0.2.2:8080',
    ];
    for (final c in candidates) {
      try {
        final uri = Uri.parse('$c/health');
        final res = await http.Client().get(uri).timeout(const Duration(milliseconds: 1500));
        if (res.statusCode == 200) {
          _centralApiUrlController.text = c;
          setState(() {
            _isTestingCentralApi = false;
            _centralApiOnline = true;
            _centralApiStatus = 'Auto-detected online server at $c!';
          });
          HttpCentralApiService.markServerOnline(c);
          await SessionService.current?.saveCentralServerUrl(c);
          return;
        }
      } catch (_) {}
    }
    setState(() {
      _isTestingCentralApi = false;
      _centralApiOnline = false;
      _centralApiStatus = 'No active server found. Ensure bin/server.dart is running on PC!';
    });
  }

  void _saveCurrentForm() {
    final port = int.tryParse(_portController.text.trim()) ?? 5432;
    final updated = PostgresConfig(
      host: _hostController.text.trim().isEmpty ? 'localhost' : _hostController.text.trim(),
      port: port,
      database: _databaseController.text.trim().isEmpty ? 'gynocamp_db' : _databaseController.text.trim(),
      username: _usernameController.text.trim().isEmpty ? 'postgres' : _usernameController.text.trim(),
      password: _passwordController.text,
      useSsl: _useSsl,
      isDirectModeEnabled: _directMode,
    );
    ref.read(postgresConfigProvider.notifier).updateConfig(updated);
    SessionService.current?.saveCentralServerUrl(_centralApiUrlController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final pgState = ref.watch(postgresConfigProvider);
    final vm = ref.read(postgresConfigProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PostgreSQL Server Configuration'),
        backgroundColor: AppTheme.primaryTeal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryTeal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storage_rounded, color: AppTheme.primaryTeal, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Persistent Enterprise Database Engine',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimaryLight),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Configure connection parameters for PostgreSQL. Patient records and medical anamneses can be synchronized between local field SQLite and central PostgreSQL.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Central Cloud Sync REST API Card (Port 8080)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_sync_rounded, color: AppTheme.primaryTeal, size: 28),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Central Cloud REST API (Port 8080)',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                              ),
                            ),
                            if (_centralApiOnline == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    const Text('ONLINE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                              )
                            else if (_centralApiOnline == false)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    const Text('OFFLINE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Primary sync endpoint used by Android Tablets & Chrome to share camps, patients, medicines, and clinical visits.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _centralApiUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Central Server API URL',
                            hintText: 'http://192.168.1.4:8080 or http://127.0.0.1:8080',
                            prefixIcon: Icon(Icons.wifi_rounded),
                          ),
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              icon: _isTestingCentralApi
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.network_check_rounded, size: 18),
                              label: Text(_isTestingCentralApi ? 'Checking...' : 'Ping Central API'),
                              onPressed: _isTestingCentralApi ? null : _testCentralApi,
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              icon: const Icon(Icons.radar_rounded, size: 18),
                              label: const Text('Auto-Detect Server'),
                              onPressed: _isTestingCentralApi ? null : _autoDetectCentralApi,
                            ),
                          ],
                        ),
                        if (_centralApiStatus != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _centralApiOnline == true
                                  ? Colors.green.shade50
                                  : (_centralApiOnline == false ? Colors.red.shade50 : Colors.blue.shade50),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _centralApiOnline == true
                                    ? Colors.green.shade300
                                    : (_centralApiOnline == false ? Colors.red.shade300 : Colors.blue.shade300),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _centralApiOnline == true
                                      ? Icons.check_circle_outline_rounded
                                      : (_centralApiOnline == false ? Icons.error_outline_rounded : Icons.info_outline_rounded),
                                  color: _centralApiOnline == true
                                      ? Colors.green.shade700
                                      : (_centralApiOnline == false ? Colors.red.shade700 : Colors.blue.shade700),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _centralApiStatus!,
                                    style: TextStyle(
                                      color: _centralApiOnline == true
                                          ? Colors.green.shade900
                                          : (_centralApiOnline == false ? Colors.red.shade900 : Colors.blue.shade900),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Server Parameters Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connection Settings',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _hostController,
                                decoration: const InputDecoration(
                                  labelText: 'Host / IP Address',
                                  hintText: 'localhost or 192.168.1.100',
                                  prefixIcon: Icon(Icons.dns_rounded),
                                ),
                                onChanged: (_) => _saveCurrentForm(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _portController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                  hintText: '5432',
                                  prefixIcon: Icon(Icons.numbers_rounded),
                                ),
                                onChanged: (_) => _saveCurrentForm(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _databaseController,
                          decoration: const InputDecoration(
                            labelText: 'Database Name',
                            hintText: 'gynocamp_db',
                            prefixIcon: Icon(Icons.data_array_rounded),
                          ),
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            hintText: 'postgres',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Require SSL / TLS'),
                          subtitle: const Text('Enable secure encrypted transmission to remote database servers'),
                          value: _useSsl,
                          activeThumbColor: AppTheme.primaryTeal,
                          onChanged: (val) {
                            setState(() => _useSsl = val);
                            _saveCurrentForm();
                          },
                        ),
                        SwitchListTile(
                          title: const Text('Direct PostgreSQL Mode'),
                          subtitle: const Text('Directly write to PostgreSQL with automatic SQLite backup'),
                          value: _directMode,
                          activeThumbColor: AppTheme.primaryTeal,
                          onChanged: (val) {
                            setState(() => _directMode = val);
                            _saveCurrentForm();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Operations
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Operations & Synchronizations',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              icon: pgState.isTesting
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.network_ping_rounded),
                              label: Text(pgState.isTesting ? 'Testing...' : 'Test Connection'),
                              onPressed: pgState.isTesting
                                  ? null
                                  : () {
                                      _saveCurrentForm();
                                      vm.testConnection();
                                    },
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              icon: pgState.isMigrating
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.table_chart_rounded),
                              label: Text(pgState.isMigrating ? 'Initializing...' : 'Initialize / Verify Tables'),
                              onPressed: pgState.isMigrating
                                  ? null
                                  : () {
                                      _saveCurrentForm();
                                      vm.initializeSchema();
                                    },
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.indigo.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              icon: pgState.isSyncing
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.cloud_sync_rounded),
                              label: Text(pgState.isSyncing ? 'Syncing...' : 'Sync SQLite -> PostgreSQL'),
                              onPressed: pgState.isSyncing
                                  ? null
                                  : () {
                                      _saveCurrentForm();
                                      vm.syncAllData();
                                    },
                            ),
                          ],
                        ),

                        if (pgState.statusMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: pgState.testError != null
                                  ? Colors.red.shade50
                                  : (pgState.testLatencyMs != null ? Colors.green.shade50 : Colors.blue.shade50),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: pgState.testError != null
                                    ? Colors.red.shade200
                                    : (pgState.testLatencyMs != null ? Colors.green.shade200 : Colors.blue.shade200),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  pgState.testError != null
                                      ? Icons.error_outline_rounded
                                      : (pgState.testLatencyMs != null ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded),
                                  color: pgState.testError != null
                                      ? Colors.red.shade700
                                      : (pgState.testLatencyMs != null ? Colors.green.shade700 : Colors.blue.shade700),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    pgState.statusMessage!,
                                    style: TextStyle(
                                      color: pgState.testError != null
                                          ? Colors.red.shade900
                                          : (pgState.testLatencyMs != null ? Colors.green.shade900 : Colors.blue.shade900),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Last Sync Summary Card
                if (pgState.lastSyncResult != null)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Last Sync Summary',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _buildMetricChip('Patients Synced', pgState.lastSyncResult!.syncedPatients.toString(), Icons.people),
                              _buildMetricChip('Visits Synced', pgState.lastSyncResult!.syncedVisits.toString(), Icons.medical_services),
                              _buildMetricChip('Camps Synced', pgState.lastSyncResult!.syncedCamps.toString(), Icons.location_on),
                              _buildMetricChip('Staff Synced', pgState.lastSyncResult!.syncedUsers.toString(), Icons.badge),
                              if (pgState.lastSyncResult!.duration != null)
                                _buildMetricChip('Duration', '${pgState.lastSyncResult!.duration!.inMilliseconds} ms', Icons.timer),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryTeal),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}
