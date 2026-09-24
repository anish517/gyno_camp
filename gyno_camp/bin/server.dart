// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';

/// GynoCamp Central Cloud Synchronization REST API Server
/// Bridges Central PostgreSQL with Web Browsers (Chrome, Opera) and Android Tablets.
void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final host = InternetAddress.anyIPv4;

  final pgHost = Platform.environment['PGHOST'] ?? 'localhost';
  final pgPort = int.tryParse(Platform.environment['PGPORT'] ?? '5432') ?? 5432;
  final pgDb = Platform.environment['PGDATABASE'] ?? 'gynocamp_db';
  final pgUser = Platform.environment['PGUSER'] ?? 'postgres';
  final pgPassword = Platform.environment['PGPASSWORD'] ?? 'postgres';

  print('====================================================');
  print(' GynoCamp Central Cloud Synchronization Server');
  print('====================================================');
  print('Target PostgreSQL: $pgUser@$pgHost:$pgPort/$pgDb');

  final server = GynoCampSyncServer(
    pgHost: pgHost,
    pgPort: pgPort,
    pgDatabase: pgDb,
    pgUsername: pgUser,
    pgPassword: pgPassword,
  );

  await server.initialize();

  final httpServer = await HttpServer.bind(host, port);
  print('✓ Central Cloud Sync API listening on http://${httpServer.address.address}:$port');
  print('✓ CORS Enabled: Ready for Chrome, Opera, and Android Tablets');
  print('----------------------------------------------------');

  await for (final request in httpServer) {
    await server.handleRequest(request);
  }
}

class GynoCampSyncServer {
  final String pgHost;
  final int pgPort;
  final String pgDatabase;
  final String pgUsername;
  final String pgPassword;

  Connection? _connection;
  bool _isPgConnected = false;

  // SSE (Server-Sent Events) real-time push connections
  final List<_SseClient> _sseClients = [];

  // In-memory fallback cache if PostgreSQL is offline
  final Map<String, Map<String, dynamic>> _memCamps = {};
  final Map<String, Map<String, dynamic>> _memUsers = {};
  final Map<String, Map<String, dynamic>> _memPatients = {};
  final Map<String, Map<String, dynamic>> _memVisits = {};
  final Map<String, Map<String, dynamic>> _memLookups = {};
  final Map<String, Map<String, dynamic>> _memDevices = {};
  final List<Map<String, dynamic>> _memAuditLogs = [];
  final Map<String, String> _memDeletedEntities = {}; // id -> entity_type ('camp', 'user', 'lookup')

  GynoCampSyncServer({
    required this.pgHost,
    required this.pgPort,
    required this.pgDatabase,
    required this.pgUsername,
    required this.pgPassword,
  });

  Future<void> initialize() async {
    await _tryConnectPostgres();
  }

  Future<bool> _tryConnectPostgres() async {
    try {
      _connection = await Connection.open(
        Endpoint(
          host: pgHost,
          port: pgPort,
          database: pgDatabase,
          username: pgUsername,
          password: pgPassword,
        ),
        settings: const ConnectionSettings(
          sslMode: SslMode.disable,
          connectTimeout: Duration(seconds: 4),
          queryTimeout: Duration(seconds: 15),
        ),
      );
      _isPgConnected = true;
      print('✓ Successfully connected to central PostgreSQL database ($pgDatabase).');
      await _ensureTablesExist();
      return true;
    } catch (e) {
      _isPgConnected = false;
      print('! PostgreSQL not reachable at $pgHost:$pgPort ($e).');
      print('! Operating with High-Availability In-Memory Cloud Store.');
      return false;
    }
  }

  /// Auto-reconnect wrapper: checks connection health and reconnects if stale
  Future<bool> _ensurePgConnection() async {
    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute('SELECT 1;');
        return true;
      } catch (_) {
        print('! PostgreSQL connection stale, reconnecting...');
        _isPgConnected = false;
        _connection = null;
      }
    }
    return _tryConnectPostgres();
  }

  Future<void> _ensureTablesExist() async {
    if (!_isPgConnected || _connection == null) return;
    try {
      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS camps (
          id TEXT PRIMARY KEY,
          camp_code TEXT NOT NULL,
          name TEXT NOT NULL,
          district TEXT NOT NULL,
          municipality TEXT,
          ward TEXT,
          venue TEXT,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          status TEXT NOT NULL,
          assigned_staff_ids TEXT,
          total_patients_registered INTEGER NOT NULL DEFAULT 0,
          tenant_id TEXT DEFAULT 'tenant_default',
          organization_name TEXT DEFAULT 'Community Health Outreach Mission',
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ
        );
      ''');

      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          email TEXT NOT NULL,
          phone TEXT,
          role TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          last_login_at TIMESTAMPTZ,
          assigned_camp_ids TEXT,
          tenant_id TEXT DEFAULT 'tenant_default',
          tenant_name TEXT DEFAULT 'Outreach Health Center',
          password_hash TEXT,
          pin_hash TEXT,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        );
      ''');

      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS patients (
          id TEXT PRIMARY KEY,
          patient_id TEXT NOT NULL,
          camp_id TEXT NOT NULL,
          camp_code TEXT NOT NULL,
          intake_date TIMESTAMPTZ NOT NULL,
          first_name TEXT NOT NULL,
          surname TEXT NOT NULL,
          age INTEGER NOT NULL,
          spouse_or_father_name TEXT,
          relationship_type TEXT,
          mobile TEXT,
          province TEXT DEFAULT 'Bagmati',
          district TEXT,
          municipality TEXT,
          ward TEXT NOT NULL,
          contact_person TEXT,
          contact_mobile TEXT,
          marital_status TEXT,
          marital_age INTEGER,
          reasons_for_visit TEXT,
          consent_treatment INTEGER NOT NULL DEFAULT 1,
          consent_store_medical_info INTEGER NOT NULL DEFAULT 1,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ,
          created_by_user_id TEXT NOT NULL,
          created_by_device_id TEXT NOT NULL,
          tenant_id TEXT DEFAULT 'tenant_default',
          is_synced INTEGER NOT NULL DEFAULT 1,
          synced_at TIMESTAMPTZ
        );
      ''');

      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS clinical_visits (
          id TEXT PRIMARY KEY,
          patient_id TEXT NOT NULL,
          camp_id TEXT NOT NULL,
          visit_date TIMESTAMPTZ NOT NULL,
          deliveries INTEGER,
          living_children INTEGER,
          abortions INTEGER,
          anamnesis_json TEXT,
          uterus_inside INTEGER DEFAULT 1,
          vulva_remarks TEXT,
          vagina_remarks TEXT,
          cervix_remarks TEXT,
          uterus_remarks TEXT,
          pelvic_floor_tone TEXT DEFAULT 'normal',
          pop_anterior_stage INTEGER DEFAULT 0,
          pop_middle_stage INTEGER DEFAULT 0,
          pop_posterior_stage INTEGER DEFAULT 0,
          highest_pop_stage INTEGER DEFAULT 0,
          urine_test TEXT,
          pregnancy_test TEXT,
          systolic_bp INTEGER,
          diastolic_bp INTEGER,
          pulse INTEGER,
          spo2 INTEGER,
          glucose INTEGER,
          ecg_notes TEXT,
          diagnoses TEXT,
          counseling TEXT,
          pessary_type TEXT,
          pessary_size TEXT,
          surgical_referral TEXT,
          medications TEXT,
          custom_medication TEXT,
          follow_up_needed INTEGER,
          follow_up_destination TEXT,
          outtake_notes TEXT,
          surgery_done INTEGER DEFAULT 0,
          surgery_type TEXT,
          is_follow_up INTEGER DEFAULT 0,
          follow_up_notes TEXT,
          attending_doctor_names TEXT DEFAULT '',
          primary_doctor_name TEXT DEFAULT '',
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ,
          created_by_user_id TEXT NOT NULL,
          tenant_id TEXT DEFAULT 'tenant_default',
          is_synced INTEGER NOT NULL DEFAULT 1
        );
      ''');

      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          id TEXT PRIMARY KEY,
          timestamp TIMESTAMPTZ NOT NULL,
          user_id TEXT NOT NULL,
          user_name TEXT NOT NULL,
          user_role TEXT NOT NULL,
          action TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          details_json TEXT,
          device_id TEXT NOT NULL,
          record_hash TEXT NOT NULL,
          previous_hash TEXT,
          tenant_id TEXT DEFAULT 'tenant_default'
        );
      ''');

      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS devices (
          device_id TEXT PRIMARY KEY,
          device_name TEXT NOT NULL,
          model TEXT DEFAULT 'Android Tablet',
          hardware_fingerprint TEXT NOT NULL,
          status TEXT NOT NULL,
          registered_by_user_id TEXT,
          registered_by_name TEXT,
          otp_hash TEXT,
          otp_expires_at TIMESTAMPTZ,
          registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          approved_at TIMESTAMPTZ,
          approved_by_user_id TEXT,
          pin_hash TEXT,
          tenant_id TEXT DEFAULT 'tenant_default'
        );
      ''');

      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS lookup_items (
          id TEXT PRIMARY KEY,
          category TEXT NOT NULL,
          sub_category TEXT,
          code TEXT NOT NULL,
          label_en TEXT NOT NULL,
          label_ne TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          tenant_id TEXT DEFAULT 'tenant_default',
          camp_id TEXT,
          excluded_camp_ids TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0
        );
      ''');

      await _connection!.execute('ALTER TABLE clinical_visits ADD COLUMN IF NOT EXISTS surgery_done INTEGER DEFAULT 0;');
      await _connection!.execute('ALTER TABLE clinical_visits ADD COLUMN IF NOT EXISTS surgery_type TEXT;');
      await _connection!.execute('ALTER TABLE clinical_visits ADD COLUMN IF NOT EXISTS is_follow_up INTEGER DEFAULT 0;');
      await _connection!.execute('ALTER TABLE clinical_visits ADD COLUMN IF NOT EXISTS follow_up_notes TEXT;');
      await _connection!.execute('ALTER TABLE clinical_visits ADD COLUMN IF NOT EXISTS attending_doctor_names TEXT DEFAULT \'\';');
      await _connection!.execute('ALTER TABLE clinical_visits ADD COLUMN IF NOT EXISTS primary_doctor_name TEXT DEFAULT \'\';');
      await _connection!.execute('ALTER TABLE patients ADD COLUMN IF NOT EXISTS province TEXT DEFAULT \'Bagmati\';');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS sub_category TEXT;');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS is_deleted INTEGER NOT NULL DEFAULT 0;');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS label_ne TEXT;');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS tenant_id TEXT DEFAULT \'tenant_default\';');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS camp_id TEXT;');
      await _connection!.execute('ALTER TABLE lookup_items ADD COLUMN IF NOT EXISTS excluded_camp_ids TEXT;');
      await _connection!.execute('ALTER TABLE camps ADD COLUMN IF NOT EXISTS province TEXT DEFAULT \'Bagmati\';');
      await _connection!.execute('ALTER TABLE camps ADD COLUMN IF NOT EXISTS doctor_name TEXT DEFAULT \'\';');
      await _connection!.execute('ALTER TABLE camps ADD COLUMN IF NOT EXISTS doctor_names TEXT DEFAULT \'\';');
      await _connection!.execute('''
        CREATE TABLE IF NOT EXISTS deleted_entities (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      ''');
      await _connection!.execute("ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS tenant_id TEXT DEFAULT 'tenant_default';");
      await _connection!.execute("ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS record_hash TEXT DEFAULT '';");
      await _connection!.execute("ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS previous_hash TEXT;");
      await _connection!.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_patients_patient_id ON patients(patient_id);');
      await _connection!.execute("UPDATE users SET role = 'SUPER_ADMIN' WHERE id = 'usr-superadmin-01' OR LOWER(email) = 'admin@gynocamp.org';");
      // Auto-cleanup any orphaned patients or clinical visits in PostgreSQL
      await _connection!.execute('DELETE FROM patients WHERE camp_id NOT IN (SELECT id FROM camps);');
      await _connection!.execute('DELETE FROM clinical_visits WHERE camp_id NOT IN (SELECT id FROM camps);');
      await _seedDefaultLookupsIfEmpty();
      print('✓ Verified and initialized all PostgreSQL schema tables.');
    } catch (e) {
      print('! Schema verification note: $e');
    }
  }

  Future<void> _seedDefaultLookupsIfEmpty() async {
    if (!_isPgConnected || _connection == null) return;
    try {
      final complaintRow = await _connection!.execute("SELECT COUNT(*) FROM lookup_items WHERE category = 'chief_complaint';");
      if ((complaintRow.first[0] as int? ?? 0) == 0) {
        final defaultComplaints = [
          {'en': 'Lower Abdominal Pain', 'ne': 'तल्लो पेट दुख्ने', 'sub': 'Pelvic & Abdominal'},
          {'en': 'White / Foul Discharge', 'ne': 'सेतो वा गन्हाउने पानी बग्ने', 'sub': 'Infections & Discharge'},
          {'en': 'Pelvic Heaviness', 'ne': 'तल्लो पेट भारी हुने', 'sub': 'Pelvic Floor & Prolapse'},
          {'en': 'Burning Micturition', 'ne': 'पिसाब पोल्ने', 'sub': 'Urinary Symptoms'},
          {'en': 'Urinary Incontinence', 'ne': 'पिसाब चुहिने', 'sub': 'Urinary Symptoms'},
          {'en': 'Dyspareunia', 'ne': 'यौन सम्पर्कमा दुखाई', 'sub': 'Reproductive & Sexual'},
          {'en': 'Coital Bleeding', 'ne': 'सम्पर्कपछि रगत बग्ने', 'sub': 'Bleeding & Neoplasms'},
          {'en': 'Mass Per Vagina', 'ne': 'पाठेघर / मासु खस्ने', 'sub': 'Pelvic Floor & Prolapse'},
          {'en': 'Severe Backache', 'ne': 'कम्मर दुख्ने', 'sub': 'Musculoskeletal & General'},
        ];
        int idx = 0;
        for (final c in defaultComplaints) {
          idx++;
          final code = c['en']!.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
          await _connection!.execute(
            Sql.named('''
              INSERT INTO lookup_items (id, category, sub_category, code, label_en, label_ne, is_active, sort_order, tenant_id, is_deleted)
              VALUES (@id, 'chief_complaint', @sub, @code, @en, @ne, 1, @sort, 'tenant_default', 0)
              ON CONFLICT (id) DO NOTHING;
            '''),
            parameters: {
              'id': 'complaint-default-$idx',
              'sub': c['sub'],
              'code': code,
              'en': c['en'],
              'ne': c['ne'],
              'sort': idx,
            },
          );
        }
        print('✓ Seeded default chief complaints in PostgreSQL.');
      }

      final reasonCount = await _connection!.execute("SELECT COUNT(*) FROM lookup_items WHERE category = 'visit_reason';");
      if ((reasonCount.first[0] as int? ?? 0) == 0) {
        final defaultReasons = [
          {'en': 'Routine Checkup', 'ne': 'नियमित जाँच'},
          {'en': 'Pelvic Organ Prolapse', 'ne': 'पाठेघर खसेको'},
          {'en': 'Menstrual Disorder', 'ne': 'महिनावारी गडबडी'},
          {'en': 'Infertility Screening', 'ne': 'निःसन्तान जाँच'},
          {'en': 'Gynaecological Oncology', 'ne': 'स्त्री क्यान्सर जाँच'},
          {'en': 'Postnatal Follow-up', 'ne': 'सुत्केरीपछिको जाँच'},
        ];
        int idx = 0;
        for (final r in defaultReasons) {
          idx++;
          final code = r['en']!.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
          await _connection!.execute(
            Sql.named('''
              INSERT INTO lookup_items (id, category, sub_category, code, label_en, label_ne, is_active, sort_order, tenant_id, is_deleted)
              VALUES (@id, 'visit_reason', 'Reason for Visit', @code, @en, @ne, 1, @sort, 'tenant_default', 0)
              ON CONFLICT (id) DO NOTHING;
            '''),
            parameters: {
              'id': 'reason-default-$idx',
              'code': code,
              'en': r['en'],
              'ne': r['ne'],
              'sort': idx,
            },
          );
        }
        print('✓ Seeded default visit reasons in PostgreSQL.');
      }
    } catch (e) {
      print('! Seeding lookups note: $e');
    }
  }

  Future<void> handleRequest(HttpRequest request) async {
    // 1. Universal CORS Configuration for Cross-Browser & Cross-Origin Requests
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', '*');
    request.response.headers.set('Access-Control-Max-Age', '86400');
    request.response.headers.set('Content-Type', 'application/json; charset=utf-8');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    try {
      if (path != '/api/events') {
        await _ensurePgConnection();
      }

      if (request.method == 'GET' && (path == '/' || path == '/health' || path == '/api/status')) {
        await _handleHealth(request);
      } else if (request.method == 'POST' && path == '/api/sync/push') {
        await _handleSyncPush(request);
      } else if (request.method == 'GET' && path == '/api/sync/pull') {
        await _handleSyncPull(request);
      } else if (request.method == 'GET' && path == '/api/camps') {
        await _handleGetCamps(request);
      } else if (request.method == 'POST' && path == '/api/camps') {
        await _handlePostCamp(request);
      } else if (request.method == 'DELETE' && path == '/api/camps') {
        await _handleDeleteCamp(request);
      } else if (request.method == 'DELETE' && path == '/api/lookups') {
        await _handleDeleteLookup(request);
      } else if (request.method == 'GET' && path == '/api/users') {
        await _handleGetUsers(request);
      } else if (request.method == 'POST' && path == '/api/users') {
        await _handlePostUser(request);
      } else if (request.method == 'DELETE' && path == '/api/users') {
        await _handleDeleteUser(request);
      } else if (request.method == 'GET' && path == '/api/devices') {
        await _handleGetDevices(request);
      } else if (request.method == 'GET' && path == '/api/devices/check') {
        await _handleCheckDevice(request);
      } else if (request.method == 'POST' && path == '/api/devices') {
        await _handlePostDevice(request);
      } else if (request.method == 'POST' && path == '/api/devices/approve') {
        await _handleApproveDevice(request);
      } else if (request.method == 'POST' && path == '/api/devices/revoke') {
        await _handleRevokeDevice(request);
      } else if (request.method == 'GET' && path == '/api/events') {
        await _handleSseEvents(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'Endpoint not found', 'path': path}));
        await request.response.close();
      }
    } catch (e, st) {
      print('Error processing $path: $e\n$st');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  Future<void> _handleHealth(HttpRequest request) async {
    // Retry connecting to PostgreSQL if disconnected
    if (!_isPgConnected) {
      await _tryConnectPostgres();
    }

    final countCamps = _isPgConnected
        ? (await _connection!.execute('SELECT COUNT(*) FROM camps')).first[0]
        : _memCamps.length;
    final countPatients = _isPgConnected
        ? (await _connection!.execute('SELECT COUNT(*) FROM patients')).first[0]
        : _memPatients.length;

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({
      'status': 'online',
      'service': 'GynoCamp Central Cloud Synchronization API',
      'postgres_connected': _isPgConnected,
      'database': pgDatabase,
      'timestamp': DateTime.now().toIso8601String(),
      'metrics': {
        'total_camps': countCamps,
        'total_patients': countPatients,
      },
    }));
    await request.response.close();
  }

  Future<void> _handleSyncPush(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final patients = (data['patients'] as List<dynamic>?) ?? [];
    final visits = (data['clinical_visits'] as List<dynamic>?) ?? [];
    final auditLogs = (data['audit_logs'] as List<dynamic>?) ?? [];
    final camps = (data['camps'] as List<dynamic>?) ?? [];
    final users = (data['users'] as List<dynamic>?) ?? [];

    final syncedPatientIds = <String>[];
    final syncedVisitIds = <String>[];
    final syncedAuditLogIds = <String>[];
    final syncedLookupIds = <String>[];

    // Ensure DB connection
    if (!_isPgConnected) {
      await _tryConnectPostgres();
    }

    // 0. Process Lookup Items (medicines, diagnoses, etc.)
    final lookupItems = (data['lookup_items'] as List<dynamic>?) ?? [];
    for (final l in lookupItems) {
      final map = l as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _memLookups[id] = map;
      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO lookup_items (id, category, sub_category, code, label_en, label_ne, is_active, sort_order, tenant_id, camp_id, excluded_camp_ids, is_deleted)
              VALUES (@id, @category, @sub_category, @code, @label_en, @label_ne, @is_active, @sort_order, @tenant_id, @camp_id, @excluded_camp_ids, @is_deleted)
              ON CONFLICT (id) DO UPDATE SET
                category = EXCLUDED.category,
                sub_category = EXCLUDED.sub_category,
                code = EXCLUDED.code,
                label_en = EXCLUDED.label_en,
                label_ne = EXCLUDED.label_ne,
                is_active = EXCLUDED.is_active,
                sort_order = EXCLUDED.sort_order,
                tenant_id = EXCLUDED.tenant_id,
                camp_id = EXCLUDED.camp_id,
                excluded_camp_ids = EXCLUDED.excluded_camp_ids,
                is_deleted = EXCLUDED.is_deleted;
            '''),
            parameters: {
              'id': id,
              'category': map['category'] ?? 'unknown',
              'sub_category': map['sub_category'],
              'code': map['code'] ?? id,
              'label_en': map['label_en'] ?? '',
              'label_ne': map['label_ne'],
              'is_active': map['is_active'] ?? 1,
              'sort_order': map['sort_order'] ?? 0,
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
              'camp_id': map['camp_id'],
              'excluded_camp_ids': map['excluded_camp_ids'],
              'is_deleted': map['is_deleted'] ?? 0,
            },
          );
          syncedLookupIds.add(id);
        } catch (_) {}
      } else {
        syncedLookupIds.add(id);
      }
    }

    // 1. Process Camps
    for (final c in camps) {
      final map = c as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      final status = (map['status']?.toString() ?? 'DRAFT').toUpperCase();
      map['status'] = status;
      _memCamps[id] = map;

      if (status == 'OPEN') {
        _memCamps.forEach((key, val) {
          if (key != id && (val['status']?.toString() ?? '').toUpperCase() == 'OPEN') {
            val['status'] = 'CLOSED';
            val['updated_at'] = DateTime.now().toUtc().toIso8601String();
          }
        });
        if (_isPgConnected && _connection != null) {
          try {
            await _connection!.execute(
              Sql.named("UPDATE camps SET status = 'CLOSED', updated_at = NOW() WHERE id != @id AND status = 'OPEN'"),
              parameters: {'id': id},
            );
          } catch (_) {}
        }
      }

      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO camps (
                id, camp_code, name, province, district, municipality, ward, venue,
                start_date, end_date, status, assigned_staff_ids, total_patients_registered,
                tenant_id, organization_name, doctor_name, doctor_names, created_at, updated_at
              ) VALUES (
                @id, @camp_code, @name, @province, @district, @municipality, @ward, @venue,
                @start_date, @end_date, @status, @assigned_staff_ids, @total_patients_registered,
                @tenant_id, @organization_name, @doctor_name, @doctor_names, @created_at, @updated_at
              )
              ON CONFLICT (id) DO UPDATE SET
                camp_code = EXCLUDED.camp_code,
                name = EXCLUDED.name,
                province = EXCLUDED.province,
                district = EXCLUDED.district,
                municipality = EXCLUDED.municipality,
                ward = EXCLUDED.ward,
                venue = EXCLUDED.venue,
                start_date = EXCLUDED.start_date,
                end_date = EXCLUDED.end_date,
                status = CASE 
                  WHEN camps.status = 'OPEN' AND EXCLUDED.status = 'CLOSED' AND EXCLUDED.updated_at < camps.updated_at THEN camps.status
                  ELSE EXCLUDED.status
                END,
                assigned_staff_ids = EXCLUDED.assigned_staff_ids,
                total_patients_registered = EXCLUDED.total_patients_registered,
                tenant_id = EXCLUDED.tenant_id,
                organization_name = EXCLUDED.organization_name,
                doctor_name = EXCLUDED.doctor_name,
                doctor_names = EXCLUDED.doctor_names,
                updated_at = NOW();
            '''),
            parameters: {
              'id': id,
              'camp_code': map['camp_code'] ?? 'KTM01',
              'name': map['name'] ?? '',
              'province': map['province'] ?? 'Bagmati',
              'district': map['district'] ?? '',
              'municipality': map['municipality'],
              'ward': map['ward'],
              'venue': map['venue'],
              'start_date': map['start_date'] ?? DateTime.now().toUtc().toIso8601String(),
              'end_date': map['end_date'] ?? DateTime.now().toUtc().toIso8601String(),
              'status': (map['status']?.toString() ?? 'DRAFT').toUpperCase(),
              'assigned_staff_ids': map['assigned_staff_ids'],
              'total_patients_registered': map['total_patients_registered'] ?? 0,
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
              'organization_name': map['organization_name'] ?? 'Nepal Health Outreach Network',
              'doctor_name': map['doctor_name'] ?? '',
              'doctor_names': map['doctor_names'] ?? '',
              'created_at': map['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
              'updated_at': map['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
            },
          );
        } catch (e) {
          print('Error upserting camp $id in push: $e');
        }
      }
    }

    // 2. Process Users
    for (final u in users) {
      final map = u as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memUsers[id] = map;
      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO users (id, name, email, phone, role, is_active, last_login_at, assigned_camp_ids, tenant_id, tenant_name, password_hash, pin_hash)
              VALUES (@id, @name, @email, @phone, @role, @is_active, @last_login_at, @assigned_camp_ids, @tenant_id, @tenant_name, @password_hash, @pin_hash)
              ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                email = EXCLUDED.email,
                phone = EXCLUDED.phone,
                role = EXCLUDED.role,
                is_active = EXCLUDED.is_active,
                last_login_at = COALESCE(EXCLUDED.last_login_at, users.last_login_at),
                assigned_camp_ids = EXCLUDED.assigned_camp_ids,
                tenant_id = EXCLUDED.tenant_id,
                tenant_name = EXCLUDED.tenant_name,
                password_hash = COALESCE(EXCLUDED.password_hash, users.password_hash),
                pin_hash = COALESCE(EXCLUDED.pin_hash, users.pin_hash);
            '''),
            parameters: {
              'id': id,
              'name': map['name'] ?? '',
              'email': map['email'] ?? '',
              'phone': map['phone'],
              'role': map['role'] ?? 'data_taker',
              'is_active': map['is_active'] ?? 1,
              'last_login_at': map['last_login_at'],
              'assigned_camp_ids': map['assigned_camp_ids'],
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
              'tenant_name': map['tenant_name'] ?? 'Nepal Health Outreach Network',
              'password_hash': map['password_hash'],
              'pin_hash': map['pin_hash'],
            },
          );
        } catch (e) {
          print('Error upserting user $id in push: $e');
        }
      }
    }

    // 3. Process Patients
    for (final p in patients) {
      final map = p as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memPatients[id] = map;

      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO patients (
                id, patient_id, camp_id, camp_code, intake_date, first_name, surname, age,
                spouse_or_father_name, relationship_type, mobile, province, district, municipality, ward,
                contact_person, contact_mobile, marital_status, marital_age,
                reasons_for_visit, consent_treatment, consent_store_medical_info,
                created_at, created_by_user_id, created_by_device_id, tenant_id, is_synced, synced_at
              ) VALUES (
                @id, @patient_id, @camp_id, @camp_code, @intake_date, @first_name, @surname, @age,
                @spouse_or_father_name, @relationship_type, @mobile, @province, @district, @municipality, @ward,
                @contact_person, @contact_mobile, @marital_status, @marital_age,
                @reasons_for_visit, @consent_treatment, @consent_store_medical_info,
                @created_at, @created_by_user_id, @created_by_device_id, @tenant_id, 1, NOW()
              )
              ON CONFLICT (id) DO UPDATE SET
                patient_id = EXCLUDED.patient_id,
                camp_id = EXCLUDED.camp_id,
                camp_code = EXCLUDED.camp_code,
                intake_date = EXCLUDED.intake_date,
                first_name = EXCLUDED.first_name,
                surname = EXCLUDED.surname,
                age = EXCLUDED.age,
                spouse_or_father_name = EXCLUDED.spouse_or_father_name,
                relationship_type = EXCLUDED.relationship_type,
                mobile = EXCLUDED.mobile,
                province = EXCLUDED.province,
                district = EXCLUDED.district,
                municipality = EXCLUDED.municipality,
                ward = EXCLUDED.ward,
                contact_person = EXCLUDED.contact_person,
                contact_mobile = EXCLUDED.contact_mobile,
                marital_status = EXCLUDED.marital_status,
                marital_age = EXCLUDED.marital_age,
                reasons_for_visit = EXCLUDED.reasons_for_visit,
                consent_treatment = EXCLUDED.consent_treatment,
                consent_store_medical_info = EXCLUDED.consent_store_medical_info,
                updated_at = NOW(),
                synced_at = NOW();
            '''),
            parameters: {
              'id': id,
              'patient_id': map['patient_id'] ?? id,
              'camp_id': map['camp_id'] ?? '',
              'camp_code': map['camp_code'] ?? 'KTM01',
              'intake_date': map['intake_date'] ?? DateTime.now().toIso8601String(),
              'first_name': map['first_name'] ?? '',
              'surname': map['surname'] ?? '',
              'age': map['age'] ?? 30,
              'spouse_or_father_name': map['spouse_or_father_name'],
              'relationship_type': map['relationship_type'],
              'mobile': map['mobile'],
              'province': map['province'] ?? 'Bagmati',
              'district': map['district'],
              'municipality': map['municipality'],
              'ward': map['ward'] ?? '01',
              'contact_person': map['contact_person'],
              'contact_mobile': map['contact_mobile'],
              'marital_status': map['marital_status'] ?? 'married',
              'marital_age': map['marital_age'],
              'reasons_for_visit': map['reasons_for_visit'],
              'consent_treatment': (map['consent_treatment'] is bool)
                  ? (map['consent_treatment'] == true ? 1 : 0)
                  : (map['consent_treatment'] ?? 1),
              'consent_store_medical_info': (map['consent_store_medical_info'] is bool)
                  ? (map['consent_store_medical_info'] == true ? 1 : 0)
                  : (map['consent_store_medical_info'] ?? 1),
              'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
              'created_by_user_id': map['created_by_user_id'] ?? '',
              'created_by_device_id': map['created_by_device_id'] ?? '',
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
            },
          );
          syncedPatientIds.add(id);
        } catch (e) {
          print('Error inserting patient $id: $e');
        }
      } else {
        syncedPatientIds.add(id);
      }
    }

    // Recalculate total_patients_registered on camps
    if (_isPgConnected && _connection != null && patients.isNotEmpty) {
      try {
        await _connection!.execute('''
          UPDATE camps 
          SET total_patients_registered = (
            SELECT COUNT(*) FROM patients WHERE patients.camp_id = camps.id
          );
        ''');
      } catch (e) {
        print('Error recalculating total_patients_registered: $e');
      }
    }

    // 4. Process Clinical Visits
    for (final v in visits) {
      final map = v as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memVisits[id] = map;

      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO clinical_visits (
                id, patient_id, camp_id, visit_date, deliveries, living_children, abortions,
                anamnesis_json, uterus_inside, vulva_remarks, vagina_remarks, cervix_remarks,
                uterus_remarks, pelvic_floor_tone, pop_anterior_stage, pop_middle_stage,
                pop_posterior_stage, highest_pop_stage, urine_test, pregnancy_test,
                systolic_bp, diastolic_bp, pulse, spo2, glucose, ecg_notes, diagnoses,
                counseling, pessary_type, pessary_size, surgical_referral, medications,
                custom_medication, follow_up_needed, follow_up_destination, outtake_notes,
                surgery_done, surgery_type, is_follow_up, follow_up_notes, attending_doctor_names, primary_doctor_name,
                created_at, created_by_user_id, tenant_id, is_synced
              ) VALUES (
                @id, @patient_id, @camp_id, @visit_date, @deliveries, @living_children, @abortions,
                @anamnesis_json, @uterus_inside, @vulva_remarks, @vagina_remarks, @cervix_remarks,
                @uterus_remarks, @pelvic_floor_tone, @pop_anterior_stage, @pop_middle_stage,
                @pop_posterior_stage, @highest_pop_stage, @urine_test, @pregnancy_test,
                @systolic_bp, @diastolic_bp, @pulse, @spo2, @glucose, @ecg_notes, @diagnoses,
                @counseling, @pessary_type, @pessary_size, @surgical_referral, @medications,
                @custom_medication, @follow_up_needed, @follow_up_destination, @outtake_notes,
                @surgery_done, @surgery_type, @is_follow_up, @follow_up_notes, @attending_doctor_names, @primary_doctor_name,
                @created_at, @created_by_user_id, @tenant_id, 1
              )
              ON CONFLICT (id) DO UPDATE SET
                highest_pop_stage = EXCLUDED.highest_pop_stage,
                anamnesis_json = EXCLUDED.anamnesis_json,
                diagnoses = EXCLUDED.diagnoses,
                counseling = EXCLUDED.counseling,
                medications = EXCLUDED.medications,
                custom_medication = EXCLUDED.custom_medication,
                pessary_type = EXCLUDED.pessary_type,
                pessary_size = EXCLUDED.pessary_size,
                surgical_referral = EXCLUDED.surgical_referral,
                surgery_done = EXCLUDED.surgery_done,
                surgery_type = EXCLUDED.surgery_type,
                follow_up_needed = EXCLUDED.follow_up_needed,
                follow_up_destination = EXCLUDED.follow_up_destination,
                outtake_notes = EXCLUDED.outtake_notes,
                is_follow_up = EXCLUDED.is_follow_up,
                follow_up_notes = EXCLUDED.follow_up_notes,
                attending_doctor_names = EXCLUDED.attending_doctor_names,
                primary_doctor_name = EXCLUDED.primary_doctor_name,
                updated_at = NOW();
            '''),
            parameters: {
              'id': id,
              'patient_id': map['patient_id'] ?? '',
              'camp_id': map['camp_id'] ?? '',
              'visit_date': map['visit_date'] ?? DateTime.now().toIso8601String(),
              'deliveries': map['deliveries'],
              'living_children': map['living_children'],
              'abortions': map['abortions'],
              'anamnesis_json': map['anamnesis_json'],
              'uterus_inside': map['uterus_inside'] ?? 1,
              'vulva_remarks': map['vulva_remarks'],
              'vagina_remarks': map['vagina_remarks'],
              'cervix_remarks': map['cervix_remarks'],
              'uterus_remarks': map['uterus_remarks'],
              'pelvic_floor_tone': map['pelvic_floor_tone'] ?? 'normal',
              'pop_anterior_stage': map['pop_anterior_stage'] ?? 0,
              'pop_middle_stage': map['pop_middle_stage'] ?? 0,
              'pop_posterior_stage': map['pop_posterior_stage'] ?? 0,
              'highest_pop_stage': map['highest_pop_stage'] ?? 0,
              'urine_test': map['urine_test'],
              'pregnancy_test': map['pregnancy_test'],
              'systolic_bp': map['systolic_bp'],
              'diastolic_bp': map['diastolic_bp'],
              'pulse': map['pulse'],
              'spo2': map['spo2'],
              'glucose': map['glucose'],
              'ecg_notes': map['ecg_notes'],
              'diagnoses': map['diagnoses'],
              'counseling': map['counseling'],
              'pessary_type': map['pessary_type'],
              'pessary_size': map['pessary_size'],
              'surgical_referral': map['surgical_referral'],
              'medications': map['medications'],
              'custom_medication': map['custom_medication'],
              'follow_up_needed': (map['follow_up_needed'] is bool)
                  ? (map['follow_up_needed'] == true ? 1 : 0)
                  : (map['follow_up_needed'] ?? 0),
              'follow_up_destination': map['follow_up_destination'],
              'outtake_notes': map['outtake_notes'],
              'surgery_done': (map['surgery_done'] is bool)
                  ? (map['surgery_done'] == true ? 1 : 0)
                  : (map['surgery_done'] ?? 0),
              'surgery_type': map['surgery_type'],
              'is_follow_up': (map['is_follow_up'] is bool)
                  ? (map['is_follow_up'] == true ? 1 : 0)
                  : (map['is_follow_up'] ?? 0),
              'follow_up_notes': map['follow_up_notes'],
              'attending_doctor_names': map['attending_doctor_names'] ?? '',
              'primary_doctor_name': map['primary_doctor_name'] ?? '',
              'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
              'created_by_user_id': map['created_by_user_id'] ?? '',
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
            },
          );
          syncedVisitIds.add(id);
        } catch (e) {
          print('Error inserting clinical visit $id: $e');
        }
      } else {
        syncedVisitIds.add(id);
      }
    }

    // 5. Process Audit Logs (persisted to PostgreSQL)
    for (final a in auditLogs) {
      final map = a as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _memAuditLogs.add(map);

      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO audit_logs (
                id, timestamp, user_id, user_name, user_role, action, entity_type, entity_id, details_json, device_id, record_hash, previous_hash, tenant_id
              ) VALUES (
                @id, @timestamp, @user_id, @user_name, @user_role, @action, @entity_type, @entity_id, @details_json, @device_id, @record_hash, @previous_hash, @tenant_id
              )
              ON CONFLICT (id) DO NOTHING;
            '''),
            parameters: {
              'id': id,
              'timestamp': map['timestamp'] ?? DateTime.now().toIso8601String(),
              'user_id': map['user_id'] ?? '',
              'user_name': map['user_name'] ?? '',
              'user_role': map['user_role'] ?? '',
              'action': map['action'] ?? '',
              'entity_type': map['entity_type'] ?? '',
              'entity_id': map['entity_id'] ?? '',
              'details_json': map['details_json'],
              'device_id': map['device_id'] ?? '',
              'record_hash': map['record_hash'] ?? map['log_hash'] ?? '',
              'previous_hash': map['previous_hash'],
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
            },
          );
          syncedAuditLogIds.add(id);
        } catch (e) {
          print('Error inserting audit log $id: $e');
        }
      } else {
        syncedAuditLogIds.add(id);
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({
      'success': true,
      'server_timestamp': DateTime.now().toIso8601String(),
      'synced_patient_ids': syncedPatientIds,
      'synced_visit_ids': syncedVisitIds,
      'synced_audit_log_ids': syncedAuditLogIds,
      'synced_lookup_ids': syncedLookupIds,
      'conflict_entity_ids': [],
      'message': 'Successfully committed ${syncedPatientIds.length} patients, ${syncedVisitIds.length} visits, and ${syncedLookupIds.length} lookups to central cloud.',
    }));
    await request.response.close();

    // Broadcast SSE event to all connected clients so they pull immediately
    final pushDeviceId = data['device_id']?.toString() ?? '';
    _broadcastSseEvent('sync_update', {
      'action': 'push',
      'patients': syncedPatientIds.length,
      'visits': syncedVisitIds.length,
      'camps': camps.length,
      'timestamp': DateTime.now().toIso8601String(),
    }, excludeDeviceId: pushDeviceId);
  }

  Future<void> _handleSyncPull(HttpRequest request) async {
    if (!_isPgConnected) {
      await _tryConnectPostgres();
    }

    final tenantId = request.uri.queryParameters['tenant_id'];
    final since = request.uri.queryParameters['since'];

    final campsList = <Map<String, dynamic>>[];
    final usersList = <Map<String, dynamic>>[];
    final lookupList = <Map<String, dynamic>>[];
    final patientsList = <Map<String, dynamic>>[];
    final visitsList = <Map<String, dynamic>>[];

    final hasTenant = tenantId != null && tenantId.isNotEmpty && tenantId != 'global';
    final hasSince = since != null && since.isNotEmpty;

    if (_isPgConnected && _connection != null) {
      try {
        // Camps
        String campSql = '''
          SELECT id, camp_code, name, district, municipality, ward, venue,
                 start_date, end_date, status, assigned_staff_ids, total_patients_registered,
                 tenant_id, organization_name, created_at, updated_at, province, doctor_name, doctor_names
          FROM camps
        ''';
        final campConditions = <String>[];
        final campParams = <String, dynamic>{};
        if (hasTenant) {
          campConditions.add("(tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global')");
          campParams['tenant_id'] = tenantId;
        }
        if (hasSince) {
          campConditions.add("(updated_at >= @since::timestamptz OR created_at >= @since::timestamptz)");
          campParams['since'] = since;
        }
        if (campConditions.isNotEmpty) {
          campSql += ' WHERE ${campConditions.join(' AND ')}';
        }
        campSql += ' ORDER BY updated_at DESC NULLS LAST, created_at DESC;';

        final campRows = await _connection!.execute(
          Sql.named(campSql),
          parameters: campParams,
        );
        for (final row in campRows) {
          campsList.add({
            'id': row[0],
            'camp_code': row[1],
            'name': row[2],
            'district': row[3],
            'municipality': row[4],
            'ward': row[5],
            'venue': row[6],
            'start_date': row[7]?.toString(),
            'end_date': row[8]?.toString(),
            'status': row[9],
            'assigned_staff_ids': row[10],
            'total_patients_registered': row[11],
            'tenant_id': row[12],
            'organization_name': row[13],
            'created_at': row[14]?.toString(),
            'updated_at': row[15]?.toString(),
            'province': row[16] ?? 'Bagmati',
            'doctor_name': row[17] ?? '',
            'doctor_names': row[18] ?? '',
          });
        }

        // Users (return password_hash and pin_hash for offline authentication)
        String userSql = '''
          SELECT id, name, email, phone, role, is_active, last_login_at,
                 assigned_camp_ids, tenant_id, tenant_name, password_hash, pin_hash
          FROM users
        ''';
        final userParams = <String, dynamic>{};
        if (hasTenant) {
          userSql += " WHERE (tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global')";
          userParams['tenant_id'] = tenantId;
        }
        userSql += ' ORDER BY name ASC;';

        final userRows = await _connection!.execute(
          Sql.named(userSql),
          parameters: userParams,
        );
        for (final row in userRows) {
          usersList.add({
            'id': row[0],
            'name': row[1],
            'email': row[2],
            'phone': row[3],
            'role': row[4],
            'is_active': row[5],
            'last_login_at': row[6]?.toString(),
            'assigned_camp_ids': row[7],
            'tenant_id': row[8],
            'tenant_name': row[9],
            // Security: password_hash and pin_hash are NOT included in pull
            // Devices retain their locally-set credentials
          });
        }

        // Patients
        String patientSql = '''
          SELECT id, patient_id, camp_id, camp_code, intake_date,
                 first_name, surname, age, spouse_or_father_name, relationship_type,
                 mobile, COALESCE(province, 'Bagmati'), district, municipality, ward, contact_person, contact_mobile,
                 marital_status, marital_age, reasons_for_visit,
                 consent_treatment, consent_store_medical_info,
                 created_at, updated_at, created_by_user_id, created_by_device_id,
                 tenant_id, is_synced, synced_at
          FROM patients
        ''';
        final patientConditions = <String>['camp_id IN (SELECT id FROM camps)'];
        final patientParams = <String, dynamic>{};
        if (hasTenant) {
          patientConditions.add("(tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global')");
          patientParams['tenant_id'] = tenantId;
        }
        if (hasSince) {
          patientConditions.add("(updated_at >= @since::timestamptz OR created_at >= @since::timestamptz)");
          patientParams['since'] = since;
        }
        if (patientConditions.isNotEmpty) {
          patientSql += ' WHERE ${patientConditions.join(' AND ')}';
        }
        patientSql += ' ORDER BY intake_date DESC;';

        final patientRows = await _connection!.execute(
          Sql.named(patientSql),
          parameters: patientParams,
        );
        for (final row in patientRows) {
          patientsList.add({
            'id': row[0],
            'patient_id': row[1],
            'camp_id': row[2],
            'camp_code': row[3],
            'intake_date': row[4]?.toString(),
            'first_name': row[5],
            'surname': row[6],
            'age': row[7],
            'spouse_or_father_name': row[8],
            'relationship_type': row[9],
            'mobile': row[10],
            'province': row[11] ?? 'Bagmati',
            'district': row[12],
            'municipality': row[13],
            'ward': row[14],
            'contact_person': row[15],
            'contact_mobile': row[16],
            'marital_status': row[17],
            'marital_age': row[18],
            'reasons_for_visit': row[19],
            'consent_treatment': row[20],
            'consent_store_medical_info': row[21],
            'created_at': row[22]?.toString(),
            'updated_at': row[23]?.toString(),
            'created_by_user_id': row[24],
            'created_by_device_id': row[25],
            'tenant_id': row[26],
            'is_synced': 1,
            'synced_at': row[28]?.toString(),
          });
        }

        // Clinical Visits
        String visitSql = '''
          SELECT id, patient_id, camp_id, visit_date, deliveries, living_children, abortions,
                 anamnesis_json, uterus_inside, vulva_remarks, vagina_remarks, cervix_remarks,
                 uterus_remarks, pelvic_floor_tone, pop_anterior_stage, pop_middle_stage,
                 pop_posterior_stage, highest_pop_stage, urine_test, pregnancy_test,
                 systolic_bp, diastolic_bp, pulse, spo2, glucose, ecg_notes, diagnoses,
                 counseling, pessary_type, pessary_size, surgical_referral, medications,
                 custom_medication, follow_up_needed, follow_up_destination, outtake_notes,
                 created_at, updated_at, created_by_user_id, tenant_id,
                 COALESCE(surgery_done, 0), surgery_type,
                 COALESCE(is_follow_up, 0), follow_up_notes, attending_doctor_names, primary_doctor_name
          FROM clinical_visits
        ''';
        final visitConditions = <String>['camp_id IN (SELECT id FROM camps)'];
        final visitParams = <String, dynamic>{};
        if (hasTenant) {
          visitConditions.add("(tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global')");
          visitParams['tenant_id'] = tenantId;
        }
        if (hasSince) {
          visitConditions.add("(updated_at >= @since::timestamptz OR created_at >= @since::timestamptz)");
          visitParams['since'] = since;
        }
        if (visitConditions.isNotEmpty) {
          visitSql += ' WHERE ${visitConditions.join(' AND ')}';
        }
        visitSql += ' ORDER BY visit_date DESC;';

        final visitRows = await _connection!.execute(
          Sql.named(visitSql),
          parameters: visitParams,
        );
        for (final row in visitRows) {
          visitsList.add({
            'id': row[0],
            'patient_id': row[1],
            'camp_id': row[2],
            'visit_date': row[3]?.toString(),
            'deliveries': row[4],
            'living_children': row[5],
            'abortions': row[6],
            'anamnesis_json': row[7],
            'uterus_inside': row[8],
            'vulva_remarks': row[9],
            'vagina_remarks': row[10],
            'cervix_remarks': row[11],
            'uterus_remarks': row[12],
            'pelvic_floor_tone': row[13],
            'pop_anterior_stage': row[14],
            'pop_middle_stage': row[15],
            'pop_posterior_stage': row[16],
            'highest_pop_stage': row[17],
            'urine_test': row[18],
            'pregnancy_test': row[19],
            'systolic_bp': row[20],
            'diastolic_bp': row[21],
            'pulse': row[22],
            'spo2': row[23],
            'glucose': row[24],
            'ecg_notes': row[25],
            'diagnoses': row[26],
            'counseling': row[27],
            'pessary_type': row[28],
            'pessary_size': row[29],
            'surgical_referral': row[30],
            'medications': row[31],
            'custom_medication': row[32],
            'follow_up_needed': row[33],
            'follow_up_destination': row[34],
            'outtake_notes': row[35],
            'created_at': row[36]?.toString(),
            'updated_at': row[37]?.toString(),
            'created_by_user_id': row[38],
            'tenant_id': row[39],
            'surgery_done': row[40] is int ? row[40] : (row[40] == true ? 1 : 0),
            'surgery_type': row[41]?.toString(),
            'is_follow_up': row[42] is int ? row[42] : (row[42] == true ? 1 : 0),
            'follow_up_notes': row[43]?.toString(),
            'attending_doctor_names': row[44]?.toString() ?? '',
            'primary_doctor_name': row[45]?.toString() ?? '',
            'is_synced': 1,
          });
        }

        // Lookup items (now fully includes camp_id and excluded_camp_ids!)
        String lookupSql = '''
          SELECT id, category, sub_category, code, label_en, label_ne,
                 is_active, sort_order, tenant_id, is_deleted, camp_id, excluded_camp_ids
          FROM lookup_items
          WHERE is_deleted = 0
        ''';
        final lookupParams = <String, dynamic>{};
        if (hasTenant) {
          lookupSql += " AND (tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global')";
          lookupParams['tenant_id'] = tenantId;
        }
        lookupSql += ' ORDER BY category ASC, sort_order ASC;';

        final lookupRows = await _connection!.execute(
          Sql.named(lookupSql),
          parameters: lookupParams,
        );
        for (final row in lookupRows) {
          lookupList.add({
            'id': row[0],
            'category': row[1],
            'sub_category': row[2],
            'code': row[3],
            'label_en': row[4],
            'label_ne': row[5],
            'is_active': row[6],
            'sort_order': row[7],
            'tenant_id': row[8],
            'is_deleted': row[9],
            'camp_id': row[10],
            'excluded_camp_ids': row[11],
          });
        }
      } catch (e) {
        print('Error pulling from PG: $e');
      }
    }

    final deletedCampIds = <String>[];
    final deletedUserIds = <String>[];
    final deletedLookupIds = <String>[];

    if (_isPgConnected && _connection != null) {
      try {
        final deletedRows = await _connection!.execute('SELECT id, entity_type FROM deleted_entities;');
        for (final row in deletedRows) {
          final id = row[0]?.toString() ?? '';
          final type = row[1]?.toString() ?? '';
          if (id.isEmpty) continue;
          if (type == 'camp') deletedCampIds.add(id);
          if (type == 'user') deletedUserIds.add(id);
          if (type == 'lookup') deletedLookupIds.add(id);
        }
      } catch (e) {
        print('Error pulling deleted_entities from PG: $e');
      }
    }

    _memDeletedEntities.forEach((id, type) {
      if (type == 'camp' && !deletedCampIds.contains(id)) deletedCampIds.add(id);
      if (type == 'user' && !deletedUserIds.contains(id)) deletedUserIds.add(id);
      if (type == 'lookup' && !deletedLookupIds.contains(id)) deletedLookupIds.add(id);
    });

    // Merge in-memory records only if PostgreSQL is not connected
    if (!_isPgConnected) {
      if (campsList.isEmpty) {
        campsList.addAll(hasTenant ? _memCamps.values.where((c) => c['tenant_id'] == tenantId || c['tenant_id'] == 'tenant_default' || c['tenant_id'] == 'global') : _memCamps.values);
      }
      if (usersList.isEmpty) {
        usersList.addAll(hasTenant ? _memUsers.values.where((u) => u['tenant_id'] == tenantId || u['tenant_id'] == 'tenant_default' || u['tenant_id'] == 'global') : _memUsers.values);
      }
      if (patientsList.isEmpty) {
        patientsList.addAll(hasTenant ? _memPatients.values.where((p) => p['tenant_id'] == tenantId || p['tenant_id'] == 'tenant_default' || p['tenant_id'] == 'global') : _memPatients.values);
      }
      if (visitsList.isEmpty) {
        visitsList.addAll(hasTenant ? _memVisits.values.where((v) => v['tenant_id'] == tenantId || v['tenant_id'] == 'tenant_default' || v['tenant_id'] == 'global') : _memVisits.values);
      }
      if (lookupList.isEmpty) {
        final activeMem = _memLookups.values.where((l) => (l['is_deleted'] ?? 0) == 0);
        lookupList.addAll(hasTenant ? activeMem.where((l) => l['tenant_id'] == tenantId || l['tenant_id'] == 'tenant_default' || l['tenant_id'] == 'global') : activeMem);
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({
      'success': true,
      'server_timestamp': DateTime.now().toIso8601String(),
      'camps': campsList,
      'users': usersList,
      'lookup_items': lookupList,
      'patients': patientsList,
      'clinical_visits': visitsList,
      'deleted_camp_ids': deletedCampIds,
      'deleted_user_ids': deletedUserIds,
      'deleted_lookup_ids': deletedLookupIds,
      'message': 'Pulled ${campsList.length} camps, ${usersList.length} staff, ${patientsList.length} patients from cloud.',
    }));
    await request.response.close();
  }

  Future<void> _handleGetCamps(HttpRequest request) async {
    final tenantId = request.uri.queryParameters['tenant_id'];
    final hasTenant = tenantId != null && tenantId.isNotEmpty && tenantId != 'global';
    final list = <Map<String, dynamic>>[];
    if (_isPgConnected && _connection != null) {
      try {
        String sql = 'SELECT id, camp_code, name, district, municipality, ward, venue, '
            'start_date, end_date, status, assigned_staff_ids, total_patients_registered, '
            'tenant_id, organization_name, created_at, updated_at, province, doctor_name, doctor_names '
            'FROM camps ';
        final params = <String, dynamic>{};
        if (hasTenant) {
          sql += "WHERE (tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global') ";
          params['tenant_id'] = tenantId;
        }
        sql += 'ORDER BY updated_at DESC NULLS LAST, created_at DESC;';

        final rows = await _connection!.execute(
          Sql.named(sql),
          parameters: params,
        );
        for (final row in rows) {
          list.add({
            'id': row[0],
            'camp_code': row[1],
            'name': row[2],
            'district': row[3],
            'municipality': row[4],
            'ward': row[5],
            'venue': row[6],
            'start_date': row[7]?.toString(),
            'end_date': row[8]?.toString(),
            'status': row[9],
            'assigned_staff_ids': row[10],
            'total_patients_registered': row[11],
            'tenant_id': row[12],
            'organization_name': row[13],
            'created_at': row[14]?.toString(),
            'updated_at': row[15]?.toString(),
            'province': row[16] ?? 'Bagmati',
            'doctor_name': row[17] ?? '',
            'doctor_names': row[18] ?? '',
          });
        }
      } catch (e) {
        print('Error fetching camps from Postgres: $e');
      }
    }
    if (!_isPgConnected && list.isEmpty) {
      list.addAll(hasTenant ? _memCamps.values.where((c) => c['tenant_id'] == tenantId || c['tenant_id'] == 'tenant_default' || c['tenant_id'] == 'global') : _memCamps.values);
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(list));
    await request.response.close();
  }

  Future<void> _handlePostCamp(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final map = jsonDecode(body) as Map<String, dynamic>;
    final id = map['id']?.toString() ?? 'camp-${DateTime.now().millisecondsSinceEpoch}';
    map['id'] = id;
    final status = (map['status']?.toString() ?? 'DRAFT').toUpperCase();
    map['status'] = status;
    _memCamps[id] = map;

    // Enforce single active camp rule on server: when opening a camp, close all other open camps
    if (status == 'OPEN') {
      _memCamps.forEach((key, val) {
        if (key != id && (val['status']?.toString() ?? '').toUpperCase() == 'OPEN') {
          val['status'] = 'CLOSED';
          val['updated_at'] = DateTime.now().toUtc().toIso8601String();
        }
      });
      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named("UPDATE camps SET status = 'CLOSED', updated_at = NOW() WHERE id != @id AND status = 'OPEN'"),
            parameters: {'id': id},
          );
        } catch (_) {}
      }
    }

    final utcNow = DateTime.now().toUtc().toIso8601String();
    map['updated_at'] = utcNow;

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('''
            INSERT INTO camps (
              id, camp_code, name, province, district, municipality, ward, venue,
              start_date, end_date, status, assigned_staff_ids, total_patients_registered,
              tenant_id, organization_name, doctor_name, doctor_names, created_at, updated_at
            ) VALUES (
              @id, @camp_code, @name, @province, @district, @municipality, @ward, @venue,
              @start_date, @end_date, @status, @assigned_staff_ids, @total_patients_registered,
              @tenant_id, @organization_name, @doctor_name, @doctor_names, @created_at, @updated_at
            )
            ON CONFLICT (id) DO UPDATE SET
              camp_code = EXCLUDED.camp_code,
              name = EXCLUDED.name,
              province = EXCLUDED.province,
              district = EXCLUDED.district,
              municipality = EXCLUDED.municipality,
              ward = EXCLUDED.ward,
              venue = EXCLUDED.venue,
              start_date = EXCLUDED.start_date,
              end_date = EXCLUDED.end_date,
              status = EXCLUDED.status,
              assigned_staff_ids = EXCLUDED.assigned_staff_ids,
              total_patients_registered = EXCLUDED.total_patients_registered,
              tenant_id = EXCLUDED.tenant_id,
              organization_name = EXCLUDED.organization_name,
              doctor_name = EXCLUDED.doctor_name,
              doctor_names = EXCLUDED.doctor_names,
              updated_at = NOW();
          '''),
          parameters: {
            'id': id,
            'camp_code': map['camp_code'] ?? 'KTM01',
            'name': map['name'] ?? '',
            'province': map['province'] ?? 'Bagmati',
            'district': map['district'] ?? '',
            'municipality': map['municipality'],
            'ward': map['ward'],
            'venue': map['venue'],
            'start_date': map['start_date'] ?? utcNow,
            'end_date': map['end_date'] ?? utcNow,
            'status': status,
            'assigned_staff_ids': map['assigned_staff_ids'],
            'total_patients_registered': map['total_patients_registered'] ?? 0,
            'tenant_id': map['tenant_id'] ?? 'tenant_default',
            'organization_name': map['organization_name'] ?? 'Nepal Health Outreach Network',
            'doctor_name': map['doctor_name'] ?? '',
            'doctor_names': map['doctor_names'] ?? '',
            'created_at': map['created_at'] ?? utcNow,
            'updated_at': utcNow,
          },
        );
      } catch (e) {
        print('Error saving camp to Postgres: $e');
      }
    }

    request.response.statusCode = HttpStatus.created;
    request.response.write(jsonEncode(map));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'camp_upsert', 'camp_id': id, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleDeleteCamp(HttpRequest request) async {
    final id = request.uri.queryParameters['id'] ?? '';
    if (id.isNotEmpty) {
      _memCamps.remove(id);
      _memDeletedEntities[id] = 'camp';
      _memPatients.removeWhere((_, p) => p['camp_id'] == id);
      _memVisits.removeWhere((_, v) => v['camp_id'] == id);
      if (_isPgConnected && _connection != null) {
        try {
          // Delete related records first to satisfy foreign key constraints
          await _connection!.execute(
            Sql.named('DELETE FROM clinical_visits WHERE camp_id = @id'),
            parameters: {'id': id},
          );
          await _connection!.execute(
            Sql.named('DELETE FROM patients WHERE camp_id = @id'),
            parameters: {'id': id},
          );
          await _connection!.execute(
            Sql.named('DELETE FROM camps WHERE id = @id'),
            parameters: {'id': id},
          );
          await _connection!.execute(
            Sql.named("INSERT INTO deleted_entities (id, entity_type, deleted_at) VALUES (@id, 'camp', NOW()) ON CONFLICT (id) DO NOTHING;"),
            parameters: {'id': id},
          );
          // Auto-cleanup any orphaned patients or clinical visits in PG
          await _connection!.execute('DELETE FROM patients WHERE camp_id NOT IN (SELECT id FROM camps);');
          await _connection!.execute('DELETE FROM clinical_visits WHERE camp_id NOT IN (SELECT id FROM camps);');
          print('✓ Central Server deleted camp and associated records: $id');
        } catch (e) {
          print('Error deleting camp $id in Postgres: $e');
        }
      }
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({'success': true}));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'camp_delete', 'camp_id': id, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleGetUsers(HttpRequest request) async {
    final tenantId = request.uri.queryParameters['tenant_id'];
    final hasTenant = tenantId != null && tenantId.isNotEmpty && tenantId != 'global';
    final list = <Map<String, dynamic>>[];
    if (_isPgConnected && _connection != null) {
      try {
        String sql = 'SELECT id, name, email, phone, role, is_active, last_login_at, assigned_camp_ids, tenant_id, tenant_name, password_hash, pin_hash FROM users ';
        final params = <String, dynamic>{};
        if (hasTenant) {
          sql += "WHERE (tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global') ";
          params['tenant_id'] = tenantId;
        }
        sql += 'ORDER BY name ASC;';

        final rows = await _connection!.execute(
          Sql.named(sql),
          parameters: params,
        );
        for (final row in rows) {
          final uid = row[0]?.toString() ?? '';
          final uemail = row[2]?.toString().toLowerCase().trim() ?? '';
          final urole = (uid == 'usr-superadmin-01' || uemail == 'admin@gynocamp.org') ? 'SUPER_ADMIN' : row[4];
          list.add({
            'id': row[0],
            'name': row[1],
            'email': row[2],
            'phone': row[3],
            'role': urole,
            'is_active': row[5],
            'last_login_at': row[6]?.toString(),
            'assigned_camp_ids': row[7],
            'tenant_id': row[8],
            'tenant_name': row[9],
            'password_hash': row[10],
            'pin_hash': row[11],
          });
        }
      } catch (_) {}
    }
    if (!_isPgConnected && list.isEmpty) {
      final memList = hasTenant ? _memUsers.values.where((u) => u['tenant_id'] == tenantId || u['tenant_id'] == 'tenant_default' || u['tenant_id'] == 'global') : _memUsers.values;
      for (final u in memList) {
        final uCopy = Map<String, dynamic>.from(u);
        final uid = uCopy['id']?.toString() ?? '';
        final uemail = uCopy['email']?.toString().toLowerCase().trim() ?? '';
        if (uid == 'usr-superadmin-01' || uemail == 'admin@gynocamp.org') {
          uCopy['role'] = 'SUPER_ADMIN';
        }
        list.add(uCopy);
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(list));
    await request.response.close();
  }

  Future<void> _handlePostUser(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final map = jsonDecode(body) as Map<String, dynamic>;
    final id = map['id']?.toString() ?? 'usr-${DateTime.now().millisecondsSinceEpoch}';
    final isRootAdmin = id == 'usr-superadmin-01' || (map['email']?.toString().toLowerCase().trim() == 'admin@gynocamp.org');
    final roleVal = isRootAdmin ? 'SUPER_ADMIN' : (map['role'] ?? 'data_taker');
    map['role'] = roleVal;
    map['id'] = id;
    _memUsers[id] = map;

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('''
            INSERT INTO users (id, name, email, phone, role, is_active, last_login_at, assigned_camp_ids, tenant_id, tenant_name, password_hash, pin_hash)
            VALUES (@id, @name, @email, @phone, @role, @is_active, @last_login_at, @assigned_camp_ids, @tenant_id, @tenant_name, @password_hash, @pin_hash)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              email = EXCLUDED.email,
              phone = EXCLUDED.phone,
              role = EXCLUDED.role,
              is_active = EXCLUDED.is_active,
              last_login_at = COALESCE(EXCLUDED.last_login_at, users.last_login_at),
              assigned_camp_ids = EXCLUDED.assigned_camp_ids,
              tenant_id = EXCLUDED.tenant_id,
              tenant_name = EXCLUDED.tenant_name,
              password_hash = COALESCE(EXCLUDED.password_hash, users.password_hash),
              pin_hash = COALESCE(EXCLUDED.pin_hash, users.pin_hash);
          '''),
          parameters: {
            'id': id,
            'name': map['name'] ?? '',
            'email': map['email'] ?? '',
            'phone': map['phone'],
            'role': roleVal,
            'is_active': map['is_active'] ?? 1,
            'last_login_at': map['last_login_at'],
            'assigned_camp_ids': map['assigned_camp_ids'],
            'tenant_id': map['tenant_id'] ?? 'tenant_default',
            'tenant_name': map['tenant_name'] ?? 'Nepal Health Outreach Network',
            'password_hash': map['password_hash'],
            'pin_hash': map['pin_hash'],
          },
        );
      } catch (_) {}
    }

    request.response.statusCode = HttpStatus.created;
    request.response.write(jsonEncode(map));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'user_upsert', 'user_id': id, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleDeleteUser(HttpRequest request) async {
    final userId = request.uri.queryParameters['id'] ?? '';
    if (userId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': 'Missing user id parameter'}));
      await request.response.close();
      return;
    }

    _memUsers.remove(userId);
    _memDeletedEntities[userId] = 'user';

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('DELETE FROM users WHERE id = @id;'),
          parameters: {'id': userId},
        );
        await _connection!.execute(
          Sql.named("INSERT INTO deleted_entities (id, entity_type, deleted_at) VALUES (@id, 'user', NOW()) ON CONFLICT (id) DO NOTHING;"),
          parameters: {'id': userId},
        );
      } catch (_) {}
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({'success': true, 'deleted_user_id': userId}));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'user_delete', 'user_id': userId, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleDeleteLookup(HttpRequest request) async {
    final id = request.uri.queryParameters['id'] ?? '';
    if (id.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': 'Missing lookup id parameter'}));
      await request.response.close();
      return;
    }

    _memLookups.remove(id);
    _memDeletedEntities[id] = 'lookup';

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('DELETE FROM lookup_items WHERE id = @id;'),
          parameters: {'id': id},
        );
        await _connection!.execute(
          Sql.named("INSERT INTO deleted_entities (id, entity_type, deleted_at) VALUES (@id, 'lookup', NOW()) ON CONFLICT (id) DO NOTHING;"),
          parameters: {'id': id},
        );
      } catch (e) {
        print('Error deleting lookup item $id: $e');
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({'success': true, 'deleted_lookup_id': id}));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'lookup_delete', 'lookup_id': id, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleGetDevices(HttpRequest request) async {
    final tenantId = request.uri.queryParameters['tenant_id'];
    final hasTenant = tenantId != null && tenantId.isNotEmpty && tenantId != 'global';
    final list = <Map<String, dynamic>>[];
    if (_isPgConnected && _connection != null) {
      try {
        String sql = 'SELECT device_id, device_name, model, hardware_fingerprint, status, '
            'registered_by_user_id, registered_by_name, otp_hash, otp_expires_at, '
            'registered_at, approved_at, approved_by_user_id, pin_hash, tenant_id '
            'FROM devices ';
        final params = <String, dynamic>{};
        if (hasTenant) {
          sql += "WHERE (tenant_id = @tenant_id OR tenant_id = 'tenant_default' OR tenant_id = 'global') ";
          params['tenant_id'] = tenantId;
        }
        sql += 'ORDER BY registered_at DESC;';

        final rows = await _connection!.execute(
          Sql.named(sql),
          parameters: params,
        );
        for (final row in rows) {
          list.add({
            'device_id': row[0],
            'device_name': row[1],
            'model': row[2],
            'hardware_fingerprint': row[3],
            'status': row[4],
            'registered_by_user_id': row[5],
            'registered_by_name': row[6],
            'otp_hash': row[7],
            'otp_expires_at': row[8]?.toString(),
            'registered_at': row[9]?.toString(),
            'approved_at': row[10]?.toString(),
            'approved_by_user_id': row[11],
            'pin_hash': row[12],
            'tenant_id': row[13],
          });
        }
      } catch (e) {
        print('Error querying devices from PostgreSQL: $e');
      }
    }
    // Merge any memory devices if not already present
    final memList = hasTenant ? _memDevices.values.where((d) => d['tenant_id'] == tenantId || d['tenant_id'] == 'tenant_default' || d['tenant_id'] == 'global') : _memDevices.values;
    for (final memDev in memList) {
      if (!list.any((d) => d['device_id'] == memDev['device_id'])) {
        list.add(memDev);
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(list));
    await request.response.close();
  }

  Future<void> _handleCheckDevice(HttpRequest request) async {
    final fp = request.uri.queryParameters['fingerprint'];
    if (fp == null || fp.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': 'Missing fingerprint query parameter'}));
      await request.response.close();
      return;
    }

    Map<String, dynamic>? found;
    if (_isPgConnected && _connection != null) {
      try {
        final rows = await _connection!.execute(
          Sql.named(
            'SELECT device_id, device_name, model, hardware_fingerprint, status, '
            'registered_by_user_id, registered_by_name, otp_hash, otp_expires_at, '
            'registered_at, approved_at, approved_by_user_id, pin_hash, tenant_id '
            'FROM devices WHERE hardware_fingerprint = @fp LIMIT 1;'
          ),
          parameters: {'fp': fp},
        );
        if (rows.isNotEmpty) {
          final row = rows.first;
          found = {
            'device_id': row[0],
            'device_name': row[1],
            'model': row[2],
            'hardware_fingerprint': row[3],
            'status': row[4],
            'registered_by_user_id': row[5],
            'registered_by_name': row[6],
            'otp_hash': row[7],
            'otp_expires_at': row[8]?.toString(),
            'registered_at': row[9]?.toString(),
            'approved_at': row[10]?.toString(),
            'approved_by_user_id': row[11],
            'pin_hash': row[12],
            'tenant_id': row[13],
          };
        }
      } catch (e) {
        print('Error checking device in Postgres: $e');
      }
    }

    found ??= _memDevices.values.firstWhere(
      (d) => d['hardware_fingerprint'] == fp,
      orElse: () => {},
    );

    if (found.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'error': 'Device not found', 'fingerprint': fp}));
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode(found));
    }
    await request.response.close();
  }

  Future<void> _handlePostDevice(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final map = jsonDecode(body) as Map<String, dynamic>;
    final deviceId = map['device_id']?.toString() ?? 'dev-${DateTime.now().millisecondsSinceEpoch}';
    map['device_id'] = deviceId;
    _memDevices[deviceId] = map;

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('''
            INSERT INTO devices (
              device_id, device_name, model, hardware_fingerprint, status,
              registered_by_user_id, registered_by_name, otp_hash, otp_expires_at,
              registered_at, approved_at, approved_by_user_id, pin_hash, tenant_id
            ) VALUES (
              @device_id, @device_name, @model, @hardware_fingerprint, @status,
              @registered_by_user_id, @registered_by_name, @otp_hash, @otp_expires_at,
              @registered_at, @approved_at, @approved_by_user_id, @pin_hash, @tenant_id
            )
            ON CONFLICT (device_id) DO UPDATE SET
              device_name = EXCLUDED.device_name,
              model = EXCLUDED.model,
              hardware_fingerprint = EXCLUDED.hardware_fingerprint,
              status = EXCLUDED.status,
              registered_by_user_id = EXCLUDED.registered_by_user_id,
              registered_by_name = EXCLUDED.registered_by_name,
              otp_hash = EXCLUDED.otp_hash,
              otp_expires_at = EXCLUDED.otp_expires_at,
              approved_at = EXCLUDED.approved_at,
              approved_by_user_id = EXCLUDED.approved_by_user_id,
              pin_hash = EXCLUDED.pin_hash;
          '''),
          parameters: {
            'device_id': deviceId,
            'device_name': map['device_name'] ?? 'Field Tablet',
            'model': map['model'] ?? 'Android Tablet',
            'hardware_fingerprint': map['hardware_fingerprint'] ?? '',
            'status': map['status'] ?? 'PENDING_APPROVAL',
            'registered_by_user_id': map['registered_by_user_id'],
            'registered_by_name': map['registered_by_name'],
            'otp_hash': map['otp_hash'],
            'otp_expires_at': map['otp_expires_at'],
            'registered_at': map['registered_at'] ?? DateTime.now().toIso8601String(),
            'approved_at': map['approved_at'],
            'approved_by_user_id': map['approved_by_user_id'],
            'pin_hash': map['pin_hash'],
            'tenant_id': map['tenant_id'] ?? 'tenant_default',
          },
        );
      } catch (e) {
        print('Error inserting/updating device in Postgres: $e');
      }
    }

    print('✓ Central Server registered/updated device: $deviceId (${map['device_name']}, status: ${map['status']})');
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(map));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'device_upsert', 'device_id': deviceId, 'status': map['status'], 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleApproveDevice(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final map = jsonDecode(body) as Map<String, dynamic>;
    final deviceId = map['device_id']?.toString() ?? '';
    final adminUserId = map['approved_by_user_id']?.toString() ?? 'admin';
    final nowIso = DateTime.now().toIso8601String();

    if (_memDevices.containsKey(deviceId)) {
      _memDevices[deviceId]!['status'] = 'APPROVED';
      _memDevices[deviceId]!['approved_at'] = nowIso;
      _memDevices[deviceId]!['approved_by_user_id'] = adminUserId;
    }

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('''
            UPDATE devices
            SET status = 'APPROVED', approved_at = NOW(), approved_by_user_id = @admin_id
            WHERE device_id = @id;
          '''),
          parameters: {
            'id': deviceId,
            'admin_id': adminUserId,
          },
        );
      } catch (e) {
        print('Error approving device in Postgres: $e');
      }
    }

    print('✓ Central Server approved device $deviceId by admin $adminUserId');
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({'success': true, 'device_id': deviceId, 'status': 'APPROVED'}));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'device_approved', 'device_id': deviceId, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _handleRevokeDevice(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final map = jsonDecode(body) as Map<String, dynamic>;
    final deviceId = map['device_id']?.toString() ?? '';

    if (_memDevices.containsKey(deviceId)) {
      _memDevices[deviceId]!['status'] = 'REVOKED';
    }

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('''
            UPDATE devices
            SET status = 'REVOKED'
            WHERE device_id = @id;
          '''),
          parameters: {'id': deviceId},
        );
      } catch (e) {
        print('Error revoking device in Postgres: $e');
      }
    }

    print('✓ Central Server revoked device $deviceId');
    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({'success': true, 'device_id': deviceId, 'status': 'REVOKED'}));
    await request.response.close();
    _broadcastSseEvent('sync_update', {'action': 'device_revoked', 'device_id': deviceId, 'timestamp': DateTime.now().toIso8601String()});
  }

  // ============================================================
  //  SSE (Server-Sent Events) Real-Time Push Infrastructure
  // ============================================================

  /// Handle a new SSE client connection. Keeps the response open.
  Future<void> _handleSseEvents(HttpRequest request) async {
    final deviceId = request.uri.queryParameters['deviceId'] ?? 'unknown';
    print('→ SSE client connected: deviceId=$deviceId');

    request.response.headers.set('Content-Type', 'text/event-stream; charset=utf-8');
    request.response.headers.set('Cache-Control', 'no-cache, no-transform');
    request.response.headers.set('Connection', 'keep-alive');
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Headers', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');

    // Send initial heartbeat
    request.response.write('event: connected\ndata: {"status":"connected","server_time":"${DateTime.now().toIso8601String()}"}\n\n');

    final client = _SseClient(deviceId: deviceId, response: request.response);
    _sseClients.add(client);

    // Keep connection alive with periodic heartbeats
    final heartbeat = Stream.periodic(const Duration(seconds: 15), (count) => count);
    final heartbeatSub = heartbeat.listen((_) {
      try {
        request.response.write('event: heartbeat\ndata: {"time":"${DateTime.now().toIso8601String()}"}\n\n');
      } catch (_) {
        // Client disconnected
      }
    });

    // Wait for client disconnect
    request.response.done.then((_) {
      _sseClients.remove(client);
      heartbeatSub.cancel();
      print('← SSE client disconnected: deviceId=$deviceId (${_sseClients.length} remaining)');
    }).catchError((_) {
      _sseClients.remove(client);
      heartbeatSub.cancel();
    });
  }

  /// Broadcast an SSE event to all connected clients, optionally excluding the sender
  void _broadcastSseEvent(String eventType, Map<String, dynamic> data, {String? excludeDeviceId}) {
    final payload = 'event: $eventType\ndata: ${jsonEncode(data)}\n\n';
    final deadClients = <_SseClient>[];

    for (final client in _sseClients) {
      if (excludeDeviceId != null && client.deviceId == excludeDeviceId) continue;
      try {
        client.response.write(payload);
      } catch (_) {
        deadClients.add(client);
      }
    }

    // Clean up dead connections
    for (final dead in deadClients) {
      _sseClients.remove(dead);
    }

    if (_sseClients.isNotEmpty || deadClients.isNotEmpty) {
      print('📡 SSE broadcast: $eventType → ${_sseClients.length} clients (${deadClients.length} cleaned)');
    }
  }
}

/// Represents a connected SSE client
class _SseClient {
  final String deviceId;
  final HttpResponse response;

  _SseClient({required this.deviceId, required this.response});
}
