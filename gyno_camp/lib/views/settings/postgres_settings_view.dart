import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/services/http_central_api_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/postgres_config_viewmodel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main View
// ─────────────────────────────────────────────────────────────────────────────
class PostgresSettingsView extends ConsumerStatefulWidget {
  const PostgresSettingsView({super.key});

  @override
  ConsumerState<PostgresSettingsView> createState() =>
      _PostgresSettingsViewState();
}

class _PostgresSettingsViewState extends ConsumerState<PostgresSettingsView> {
  // ── Controllers ───────────────────────────────────────────────────────────
  late TextEditingController _centralApiUrlController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _databaseController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  bool _obscurePassword = true;
  bool _useSsl = false;
  bool _directMode = false;
  bool _showAdvanced = false;

  // ── Connection status ─────────────────────────────────────────────────────
  _TestStatus _status = _TestStatus.idle;
  String? _statusMessage;
  int? _latencyMs;

  // ── Live background polling ───────────────────────────────────────────────
  Timer? _liveTimer;
  bool _isLivePinging = false;

  @override
  void initState() {
    super.initState();

    const envUrl =
        String.fromEnvironment('CENTRAL_SERVER_URL', defaultValue: '');
    String savedCentral = envUrl.isNotEmpty
        ? envUrl
        : (SessionService.current?.getCentralServerUrl() ??
            'http://192.168.16.113:8080');
    if (savedCentral == 'http://192.168.1.4:8080') {
      savedCentral = 'http://192.168.16.113:8080';
    }
    _centralApiUrlController = TextEditingController(text: savedCentral);

    final config = ref.read(postgresConfigProvider).config;
    final initialHost =
        config.host == '192.168.1.4' ? '192.168.16.113' : config.host;
    _hostController = TextEditingController(text: initialHost);
    _portController = TextEditingController(text: config.port.toString());
    _databaseController = TextEditingController(text: config.database);
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
    _useSsl = config.useSsl;
    _directMode = config.isDirectModeEnabled;

    // Immediate ping + recurring background check
    _pingOnce();
    _liveTimer =
        Timer.periodic(const Duration(seconds: 8), (_) => _pingOnce());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _centralApiUrlController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Background ping (silent) ──────────────────────────────────────────────
  Future<void> _pingOnce() async {
    if (_isLivePinging || !mounted) return;
    _isLivePinging = true;
    final target = _centralApiUrlController.text.trim();
    final sw = Stopwatch()..start();
    try {
      final res = await http.Client()
          .get(Uri.parse('$target/health'))
          .timeout(const Duration(seconds: 3));
      sw.stop();
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _status = _TestStatus.online;
          _latencyMs = sw.elapsedMilliseconds;
        });
        HttpCentralApiService.markServerOnline(target);
      } else {
        setState(() => _status = _TestStatus.error);
      }
    } catch (_) {
      if (mounted) setState(() => _status = _TestStatus.offline);
    } finally {
      _isLivePinging = false;
    }
  }

  // ── Test & Save (user action) ─────────────────────────────────────────────
  Future<void> _testAndSave() async {
    final target = _centralApiUrlController.text.trim();
    if (target.isEmpty) return;
    setState(() {
      _status = _TestStatus.testing;
      _statusMessage = null;
    });
    final sw = Stopwatch()..start();
    try {
      final res = await http.Client()
          .get(Uri.parse('$target/health'))
          .timeout(const Duration(seconds: 5));
      sw.stop();
      if (!mounted) return;
      if (res.statusCode == 200) {
        HttpCentralApiService.markServerOnline(target);
        await SessionService.current?.saveCentralServerUrl(target);
        _saveCurrentForm();
        setState(() {
          _status = _TestStatus.online;
          _latencyMs = sw.elapsedMilliseconds;
          _statusMessage =
              '✓ Connected to gynocamp_db  •  ${sw.elapsedMilliseconds} ms';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text('Saved — connected in ${sw.elapsedMilliseconds} ms'),
              ]),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      } else {
        setState(() {
          _status = _TestStatus.error;
          _statusMessage = 'Server responded with HTTP ${res.statusCode}';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _TestStatus.offline;
        _statusMessage =
            'Cannot reach $target — check your IP address and Wi-Fi.';
      });
    }
  }

  // ── Auto-detect ───────────────────────────────────────────────────────────
  Future<void> _autoDetect() async {
    setState(() {
      _status = _TestStatus.testing;
      _statusMessage = 'Scanning network for server…';
    });
    final candidates = [
      'http://192.168.16.113:8080',
      'http://127.0.0.1:8080',
      'http://localhost:8080',
      'http://192.168.1.4:8080',
      'http://192.168.1.110:8080',
      'http://10.0.2.2:8080',
    ];
    final saved = SessionService.current?.getCentralServerUrl();
    if (saved != null && saved.isNotEmpty && !candidates.contains(saved)) {
      candidates.insert(0, saved);
    }
    for (final c in candidates) {
      try {
        final sw = Stopwatch()..start();
        final res = await http.Client()
            .get(Uri.parse('$c/health'))
            .timeout(const Duration(milliseconds: 1500));
        sw.stop();
        if (res.statusCode == 200) {
          if (!mounted) return;
          _centralApiUrlController.text = c;
          HttpCentralApiService.markServerOnline(c);
          await SessionService.current?.saveCentralServerUrl(c);
          _saveCurrentForm();
          setState(() {
            _status = _TestStatus.online;
            _latencyMs = sw.elapsedMilliseconds;
            _statusMessage =
                'Auto-detected at $c  •  ${sw.elapsedMilliseconds} ms';
          });
          return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _status = _TestStatus.offline;
      _statusMessage =
          'No server found. Make sure bin/server.dart is running on your PC.';
    });
  }

  void _saveCurrentForm() {
    final port = int.tryParse(_portController.text.trim()) ?? 5432;
    final updated = PostgresConfig(
      host: _hostController.text.trim().isEmpty
          ? 'localhost'
          : _hostController.text.trim(),
      port: port,
      database: _databaseController.text.trim().isEmpty
          ? 'gynocamp_db'
          : _databaseController.text.trim(),
      username: _usernameController.text.trim().isEmpty
          ? 'postgres'
          : _usernameController.text.trim(),
      password: _passwordController.text,
      useSsl: _useSsl,
      isDirectModeEnabled: _directMode,
    );
    ref.read(postgresConfigProvider.notifier).updateConfig(updated);
    SessionService.current
        ?.saveCentralServerUrl(_centralApiUrlController.text.trim());
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final pgState = ref.watch(postgresConfigProvider);
    final vm = ref.read(postgresConfigProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Central Server Settings'),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Live status hero ──────────────────────────────────────
                _LiveStatusCard(
                    status: _status,
                    latencyMs: _latencyMs,
                    url: _centralApiUrlController.text),
                const SizedBox(height: 20),

                // ── Server address card ───────────────────────────────────
                _SectionCard(
                  icon: Icons.wifi_rounded,
                  title: 'Server Address',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // URL input
                      TextField(
                        controller: _centralApiUrlController,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'http://192.168.16.113:8080',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy URL',
                            onPressed: () => Clipboard.setData(ClipboardData(
                                text: _centralApiUrlController.text)),
                          ),
                        ),
                        onChanged: (_) => _saveCurrentForm(),
                      ),
                      const SizedBox(height: 14),
                      // Action buttons
                      Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryTeal,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: _status == _TestStatus.testing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.cable_rounded, size: 18),
                            label: Text(_status == _TestStatus.testing
                                ? 'Connecting…'
                                : 'Test & Save'),
                            onPressed: _status == _TestStatus.testing
                                ? null
                                : _testAndSave,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 13, horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.radar_rounded, size: 18),
                          label: const Text('Auto-Detect'),
                          onPressed: _status == _TestStatus.testing
                              ? null
                              : _autoDetect,
                        ),
                      ]),
                      // Status message
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        _StatusBanner(
                            status: _status, message: _statusMessage!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Sync operations ───────────────────────────────────────
                _SectionCard(
                  icon: Icons.sync_rounded,
                  title: 'Synchronisation',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OperationTile(
                        icon: Icons.upload_rounded,
                        label: 'Push all local data to PostgreSQL',
                        subtitle: 'Camps, patients, visits, staff',
                        color: Colors.indigo.shade600,
                        loading: pgState.isSyncing,
                        onTap: pgState.isSyncing
                            ? null
                            : () {
                                _saveCurrentForm();
                                vm.syncAllData();
                              },
                      ),
                      const Divider(height: 1),
                      _OperationTile(
                        icon: Icons.schema_rounded,
                        label: 'Verify / Initialize tables',
                        subtitle:
                            'Creates missing PostgreSQL tables safely',
                        color: Colors.orange.shade700,
                        loading: pgState.isMigrating,
                        onTap: pgState.isMigrating
                            ? null
                            : () {
                                _saveCurrentForm();
                                vm.initializeSchema();
                              },
                      ),
                      if (pgState.statusMessage != null) ...[
                        const SizedBox(height: 12),
                        _StatusBanner(
                          status: pgState.testError != null
                              ? _TestStatus.error
                              : (pgState.testLatencyMs != null
                                  ? _TestStatus.online
                                  : _TestStatus.testing),
                          message: pgState.statusMessage!,
                        ),
                      ],
                      if (pgState.lastSyncResult != null) ...[
                        const SizedBox(height: 14),
                        _SyncSummaryRow(result: pgState.lastSyncResult!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Advanced toggle ───────────────────────────────────────
                InkWell(
                  onTap: () =>
                      setState(() => _showAdvanced = !_showAdvanced),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    child: Row(children: [
                      Icon(
                        _showAdvanced
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showAdvanced
                            ? 'Hide advanced settings'
                            : 'Advanced settings  (PostgreSQL direct connection)',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ]),
                  ),
                ),

                if (_showAdvanced) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    icon: Icons.storage_rounded,
                    title: 'PostgreSQL Connection',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: _Field(
                              controller: _hostController,
                              label: 'Host / IP',
                              hint: 'localhost',
                              icon: Icons.dns_rounded,
                              onChanged: (_) => _saveCurrentForm(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: _Field(
                              controller: _portController,
                              label: 'Port',
                              hint: '5432',
                              icon: Icons.numbers_rounded,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _saveCurrentForm(),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _databaseController,
                          label: 'Database',
                          hint: 'gynocamp_db',
                          icon: Icons.data_array_rounded,
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: _usernameController,
                          label: 'Username',
                          hint: 'postgres',
                          icon: Icons.person_rounded,
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                const Icon(Icons.lock_rounded, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() =>
                                  _obscurePassword = !_obscurePassword),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300)),
                          ),
                          onChanged: (_) => _saveCurrentForm(),
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile.adaptive(
                          dense: true,
                          title: const Text('Require SSL / TLS',
                              style: TextStyle(fontSize: 13)),
                          value: _useSsl,
                          activeThumbColor: AppTheme.primaryTeal,
                          onChanged: (v) {
                            setState(() => _useSsl = v);
                            _saveCurrentForm();
                          },
                        ),
                        SwitchListTile.adaptive(
                          dense: true,
                          title: const Text('Direct PostgreSQL Mode',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text(
                              'Write directly with automatic SQLite backup',
                              style: TextStyle(fontSize: 12)),
                          value: _directMode,
                          activeThumbColor: AppTheme.primaryTeal,
                          onChanged: (v) {
                            setState(() => _directMode = v);
                            _saveCurrentForm();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Enums & sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

enum _TestStatus { idle, testing, online, offline, error }

/// Full-width hero that shows live server status at a glance.
class _LiveStatusCard extends StatelessWidget {
  final _TestStatus status;
  final int? latencyMs;
  final String url;
  const _LiveStatusCard(
      {required this.status, required this.latencyMs, required this.url});

  @override
  Widget build(BuildContext context) {
    final isOnline = status == _TestStatus.online;
    final isChecking = status == _TestStatus.idle ||
        status == _TestStatus.testing;
    final Color accent = isOnline
        ? const Color(0xFF16A34A)
        : (isChecking ? Colors.blueGrey : Colors.red.shade700);
    final Color bg = isOnline
        ? const Color(0xFFDCFCE7)
        : (isChecking ? const Color(0xFFEFF6FF) : const Color(0xFFFEE2E2));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(children: [
        // Pulsing dot
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: 0.4), blurRadius: 6)
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOnline
                    ? 'Online — Connected to gynocamp_db'
                    : (isChecking
                        ? 'Checking connection…'
                        : 'Offline — Server unreachable'),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: accent),
              ),
              if (isOnline && latencyMs != null)
                Text('$latencyMs ms  •  auto-sync every 8 s',
                    style: TextStyle(
                        fontSize: 12,
                        color: accent.withValues(alpha: 0.75))),
              if (!isOnline && !isChecking)
                Text(url,
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: accent.withValues(alpha: 0.7))),
            ],
          ),
        ),
        // Live badge
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isOnline ? 'LIVE' : (isChecking ? '…' : 'DOWN'),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: accent),
          ),
        ),
      ]),
    );
  }
}

/// Consistent card wrapper with header icon + title.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 18, color: AppTheme.primaryTeal),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryLight)),
            ]),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(18), child: child),
        ],
      ),
    );
  }
}

/// Coloured banner shown below buttons.
class _StatusBanner extends StatelessWidget {
  final _TestStatus status;
  final String message;
  const _StatusBanner(
      {required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    final ok = status == _TestStatus.online;
    final err = status == _TestStatus.error ||
        status == _TestStatus.offline;
    final bg = ok
        ? Colors.green.shade50
        : (err ? Colors.red.shade50 : Colors.blue.shade50);
    final border = ok
        ? Colors.green.shade200
        : (err ? Colors.red.shade200 : Colors.blue.shade200);
    final fg = ok
        ? Colors.green.shade800
        : (err ? Colors.red.shade800 : Colors.blue.shade800);
    final ico = ok
        ? Icons.check_circle_outline_rounded
        : (err
            ? Icons.error_outline_rounded
            : Icons.info_outline_rounded);

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(ico, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 13,
                    color: fg,
                    fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

/// Tappable list-tile style operation row.
class _OperationTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;
  const _OperationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.loading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color))
            : Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: Colors.grey.shade600)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }
}

/// Small chip row showing the last sync result counts.
class _SyncSummaryRow extends StatelessWidget {
  final dynamic result;
  const _SyncSummaryRow({required this.result});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 8, children: [
      _chip('Patients', result.syncedPatients.toString(),
          Icons.people_rounded),
      _chip('Visits', result.syncedVisits.toString(),
          Icons.medical_services_rounded),
      _chip('Camps', result.syncedCamps.toString(),
          Icons.location_on_rounded),
      _chip('Staff', result.syncedUsers.toString(),
          Icons.badge_rounded),
      if (result.duration != null)
        _chip('Time', '${result.duration!.inMilliseconds} ms',
            Icons.timer_rounded),
    ]);
  }

  Widget _chip(String label, String value, IconData icon) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppTheme.primaryTeal),
        const SizedBox(width: 5),
        Text('$label ',
            style:
                const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// Reusable text field with consistent styling.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
      onChanged: onChanged,
    );
  }
}
