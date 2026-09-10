import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/postgres_config_viewmodel.dart';

class PostgresSettingsView extends ConsumerStatefulWidget {
  const PostgresSettingsView({super.key});

  @override
  ConsumerState<PostgresSettingsView> createState() => _PostgresSettingsViewState();
}

class _PostgresSettingsViewState extends ConsumerState<PostgresSettingsView> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _databaseController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _useSsl = false;
  bool _directMode = false;

  @override
  void initState() {
    super.initState();
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
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
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
