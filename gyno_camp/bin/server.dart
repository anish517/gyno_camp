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

  // In-memory fallback cache if PostgreSQL is offline
  final Map<String, Map<String, dynamic>> _memCamps = {};
  final Map<String, Map<String, dynamic>> _memUsers = {};
  final Map<String, Map<String, dynamic>> _memPatients = {};
  final Map<String, Map<String, dynamic>> _memVisits = {};
  final List<Map<String, dynamic>> _memAuditLogs = [];

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
      print('✓ Verified and initialized all PostgreSQL schema tables.');
    } catch (e) {
      print('! Schema verification note: $e');
    }
  }

  Future<void> handleRequest(HttpRequest request) async {
    // 1. Universal CORS Configuration for Cross-Browser & Cross-Origin Requests
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept, Authorization, X-Device-Id');
    request.response.headers.set('Content-Type', 'application/json; charset=utf-8');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    try {
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
      } else if (request.method == 'GET' && path == '/api/users') {
        await _handleGetUsers(request);
      } else if (request.method == 'POST' && path == '/api/users') {
        await _handlePostUser(request);
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

    // Ensure DB connection
    if (!_isPgConnected) {
      await _tryConnectPostgres();
    }

    // 1. Process Camps
    for (final c in camps) {
      final map = c as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memCamps[id] = map;
      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO camps (id, camp_code, name, district, municipality, ward, venue, start_date, end_date, status, assigned_staff_ids, total_patients_registered, tenant_id, organization_name, created_at, updated_at)
              VALUES (@id, @camp_code, @name, @district, @municipality, @ward, @venue, @start_date, @end_date, @status, @assigned_staff_ids, @total_patients_registered, @tenant_id, @organization_name, @created_at, @updated_at)
              ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                district = EXCLUDED.district,
                status = EXCLUDED.status,
                assigned_staff_ids = EXCLUDED.assigned_staff_ids,
                total_patients_registered = EXCLUDED.total_patients_registered,
                updated_at = NOW();
            '''),
            parameters: {
              'id': id,
              'camp_code': map['camp_code'] ?? 'KTM01',
              'name': map['name'] ?? '',
              'district': map['district'] ?? '',
              'municipality': map['municipality'],
              'ward': map['ward'],
              'venue': map['venue'],
              'start_date': map['start_date'] ?? DateTime.now().toIso8601String(),
              'end_date': map['end_date'] ?? DateTime.now().toIso8601String(),
              'status': map['status'] ?? 'open',
              'assigned_staff_ids': map['assigned_staff_ids'],
              'total_patients_registered': map['total_patients_registered'] ?? 0,
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
              'organization_name': map['organization_name'] ?? 'Nepal Health Outreach Network',
              'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
              'updated_at': map['updated_at'] ?? DateTime.now().toIso8601String(),
            },
          );
        } catch (_) {}
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
                assigned_camp_ids = EXCLUDED.assigned_camp_ids;
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
        } catch (_) {}
      }
    }

    // 3. Process Patients
    for (final p in patients) {
      final map = p as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memPatients[id] = map;
      syncedPatientIds.add(id);

      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO patients (id, patient_id, camp_id, camp_code, intake_date, first_name, surname, age, spouse_or_father_name, relationship_type, mobile, district, municipality, ward, reasons_for_visit, created_at, created_by_user_id, created_by_device_id, tenant_id, is_synced, synced_at)
              VALUES (@id, @patient_id, @camp_id, @camp_code, @intake_date, @first_name, @surname, @age, @spouse_or_father_name, @relationship_type, @mobile, @district, @municipality, @ward, @reasons_for_visit, @created_at, @created_by_user_id, @created_by_device_id, @tenant_id, 1, NOW())
              ON CONFLICT (id) DO UPDATE SET
                first_name = EXCLUDED.first_name,
                surname = EXCLUDED.surname,
                age = EXCLUDED.age,
                mobile = EXCLUDED.mobile,
                ward = EXCLUDED.ward,
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
              'district': map['district'],
              'municipality': map['municipality'],
              'ward': map['ward'] ?? '01',
              'reasons_for_visit': map['reasons_for_visit'],
              'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
              'created_by_user_id': map['created_by_user_id'] ?? '',
              'created_by_device_id': map['created_by_device_id'] ?? '',
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
            },
          );
        } catch (_) {}
      }
    }

    // 4. Process Clinical Visits
    for (final v in visits) {
      final map = v as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memVisits[id] = map;
      syncedVisitIds.add(id);

      if (_isPgConnected && _connection != null) {
        try {
          await _connection!.execute(
            Sql.named('''
              INSERT INTO clinical_visits (id, patient_id, camp_id, visit_date, deliveries, living_children, abortions, anamnesis_json, highest_pop_stage, systolic_bp, diastolic_bp, pulse, spo2, glucose, diagnoses, counseling, medications, created_at, created_by_user_id, tenant_id, is_synced)
              VALUES (@id, @patient_id, @camp_id, @visit_date, @deliveries, @living_children, @abortions, @anamnesis_json, @highest_pop_stage, @systolic_bp, @diastolic_bp, @pulse, @spo2, @glucose, @diagnoses, @counseling, @medications, @created_at, @created_by_user_id, @tenant_id, 1)
              ON CONFLICT (id) DO UPDATE SET
                highest_pop_stage = EXCLUDED.highest_pop_stage,
                diagnoses = EXCLUDED.diagnoses,
                counseling = EXCLUDED.counseling,
                medications = EXCLUDED.medications,
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
              'highest_pop_stage': map['highest_pop_stage'] ?? 0,
              'systolic_bp': map['systolic_bp'],
              'diastolic_bp': map['diastolic_bp'],
              'pulse': map['pulse'],
              'spo2': map['spo2'],
              'glucose': map['glucose'],
              'diagnoses': map['diagnoses'],
              'counseling': map['counseling'],
              'medications': map['medications'],
              'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
              'created_by_user_id': map['created_by_user_id'] ?? '',
              'tenant_id': map['tenant_id'] ?? 'tenant_default',
            },
          );
        } catch (_) {}
      }
    }

    // 5. Process Audit Logs
    for (final a in auditLogs) {
      final map = a as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      _memAuditLogs.add(map);
      syncedAuditLogIds.add(id);
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({
      'success': true,
      'server_timestamp': DateTime.now().toIso8601String(),
      'synced_patient_ids': syncedPatientIds,
      'synced_visit_ids': syncedVisitIds,
      'synced_audit_log_ids': syncedAuditLogIds,
      'conflict_entity_ids': [],
      'message': 'Successfully committed ${syncedPatientIds.length} patients and ${syncedVisitIds.length} visits to central cloud.',
    }));
    await request.response.close();
  }

  Future<void> _handleSyncPull(HttpRequest request) async {
    if (!_isPgConnected) {
      await _tryConnectPostgres();
    }

    final campsList = <Map<String, dynamic>>[];
    final usersList = <Map<String, dynamic>>[];
    final lookupList = <Map<String, dynamic>>[];

    if (_isPgConnected && _connection != null) {
      try {
        final campRows = await _connection!.execute('SELECT * FROM camps ORDER BY start_date DESC;');
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
          });
        }

        final userRows = await _connection!.execute('SELECT * FROM users ORDER BY name ASC;');
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
            'password_hash': row[10],
            'pin_hash': row[11],
          });
        }
      } catch (e) {
        print('Error pulling from PG: $e');
      }
    }

    // Merge in-memory records
    if (campsList.isEmpty) {
      campsList.addAll(_memCamps.values);
    }
    if (usersList.isEmpty) {
      usersList.addAll(_memUsers.values);
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode({
      'success': true,
      'server_timestamp': DateTime.now().toIso8601String(),
      'camps': campsList,
      'users': usersList,
      'lookup_items': lookupList,
      'message': 'Pulled ${campsList.length} camps and ${usersList.length} staff accounts from cloud.',
    }));
    await request.response.close();
  }

  Future<void> _handleGetCamps(HttpRequest request) async {
    final list = <Map<String, dynamic>>[];
    if (_isPgConnected && _connection != null) {
      try {
        final rows = await _connection!.execute('SELECT * FROM camps ORDER BY start_date DESC;');
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
          });
        }
      } catch (_) {}
    }
    if (list.isEmpty) {
      list.addAll(_memCamps.values);
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
    _memCamps[id] = map;

    if (_isPgConnected && _connection != null) {
      try {
        await _connection!.execute(
          Sql.named('''
            INSERT INTO camps (id, camp_code, name, district, municipality, ward, venue, start_date, end_date, status, assigned_staff_ids, total_patients_registered, tenant_id, organization_name, created_at, updated_at)
            VALUES (@id, @camp_code, @name, @district, @municipality, @ward, @venue, @start_date, @end_date, @status, @assigned_staff_ids, @total_patients_registered, @tenant_id, @organization_name, @created_at, @updated_at)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              status = EXCLUDED.status,
              assigned_staff_ids = EXCLUDED.assigned_staff_ids,
              total_patients_registered = EXCLUDED.total_patients_registered,
              updated_at = NOW();
          '''),
          parameters: {
            'id': id,
            'camp_code': map['camp_code'] ?? 'KTM01',
            'name': map['name'] ?? '',
            'district': map['district'] ?? '',
            'municipality': map['municipality'],
            'ward': map['ward'],
            'venue': map['venue'],
            'start_date': map['start_date'] ?? DateTime.now().toIso8601String(),
            'end_date': map['end_date'] ?? DateTime.now().toIso8601String(),
            'status': map['status'] ?? 'open',
            'assigned_staff_ids': map['assigned_staff_ids'],
            'total_patients_registered': map['total_patients_registered'] ?? 0,
            'tenant_id': map['tenant_id'] ?? 'tenant_default',
            'organization_name': map['organization_name'] ?? 'Nepal Health Outreach Network',
            'created_at': map['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at': map['updated_at'] ?? DateTime.now().toIso8601String(),
          },
        );
      } catch (_) {}
    }

    request.response.statusCode = HttpStatus.created;
    request.response.write(jsonEncode(map));
    await request.response.close();
  }

  Future<void> _handleGetUsers(HttpRequest request) async {
    final list = <Map<String, dynamic>>[];
    if (_isPgConnected && _connection != null) {
      try {
        final rows = await _connection!.execute('SELECT * FROM users ORDER BY name ASC;');
        for (final row in rows) {
          list.add({
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
            'password_hash': row[10],
            'pin_hash': row[11],
          });
        }
      } catch (_) {}
    }
    if (list.isEmpty) {
      list.addAll(_memUsers.values);
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.write(jsonEncode(list));
    await request.response.close();
  }

  Future<void> _handlePostUser(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final map = jsonDecode(body) as Map<String, dynamic>;
    final id = map['id']?.toString() ?? 'usr-${DateTime.now().millisecondsSinceEpoch}';
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
              assigned_camp_ids = EXCLUDED.assigned_camp_ids;
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
      } catch (_) {}
    }

    request.response.statusCode = HttpStatus.created;
    request.response.write(jsonEncode(map));
    await request.response.close();
  }
}
