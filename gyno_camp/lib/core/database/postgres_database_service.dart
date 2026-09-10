import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import '../services/session_service.dart';
import 'database_service.dart';
import 'database_tables.dart';

class PostgresSyncResult {
  final bool success;
  final int syncedPatients;
  final int syncedVisits;
  final int syncedCamps;
  final int syncedUsers;
  final String? errorMessage;
  final Duration? duration;

  const PostgresSyncResult({
    required this.success,
    this.syncedPatients = 0,
    this.syncedVisits = 0,
    this.syncedCamps = 0,
    this.syncedUsers = 0,
    this.errorMessage,
    this.duration,
  });

  int get totalRecords => syncedPatients + syncedVisits + syncedCamps + syncedUsers;
}

class PostgresDatabaseService {
  static final PostgresDatabaseService _instance = PostgresDatabaseService._internal();
  factory PostgresDatabaseService() => _instance;
  PostgresDatabaseService._internal();

  Connection? _connection;

  bool get isConnected => _connection != null && _connection!.isOpen;

  Endpoint _buildEndpoint(PostgresConfig config) {
    return Endpoint(
      host: config.host.trim(),
      port: config.port,
      database: config.database.trim(),
      username: config.username.trim(),
      password: config.password,
    );
  }

  ConnectionSettings _buildSettings(PostgresConfig config) {
    return ConnectionSettings(
      sslMode: config.useSsl ? SslMode.require : SslMode.disable,
      connectTimeout: const Duration(seconds: 8),
      queryTimeout: const Duration(seconds: 20),
    );
  }

  /// Establishes or reuses connection
  Future<Connection> getConnection({PostgresConfig? config}) async {
    if (_connection != null && _connection!.isOpen) {
      return _connection!;
    }

    final effectiveConfig = config ?? SessionService.current?.getPostgresConfig() ?? const PostgresConfig();
    _connection = await Connection.open(
      _buildEndpoint(effectiveConfig),
      settings: _buildSettings(effectiveConfig),
    );
    return _connection!;
  }

  /// Closes active connection
  Future<void> close() async {
    if (_connection != null && _connection!.isOpen) {
      await _connection!.close();
      _connection = null;
    }
  }

  /// Tests connectivity and latency
  Future<int> testConnection(PostgresConfig config) async {
    final sw = Stopwatch()..start();
    Connection? testConn;
    try {
      testConn = await Connection.open(
        _buildEndpoint(config),
        settings: _buildSettings(config),
      );
      await testConn.execute('SELECT 1;');
      sw.stop();
      return sw.elapsedMilliseconds;
    } finally {
      if (testConn != null && testConn.isOpen) {
        await testConn.close();
      }
    }
  }

  /// Creates all required tables and indexes in PostgreSQL
  Future<void> initializePostgresSchema({PostgresConfig? config}) async {
    final conn = await getConnection(config: config);

    // Users table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phone TEXT,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        last_login_at TEXT,
        assigned_camp_ids TEXT,
        tenant_id TEXT DEFAULT 'tenant_default',
        tenant_name TEXT DEFAULT 'Outreach Health Center',
        password_hash TEXT,
        pin_hash TEXT
      );
    ''');

    // Devices table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL,
        model TEXT,
        hardware_fingerprint TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        registered_by_user_id TEXT,
        registered_by_name TEXT,
        otp_hash TEXT,
        otp_expires_at TEXT,
        registered_at TEXT NOT NULL,
        approved_at TEXT,
        approved_by_user_id TEXT,
        pin_hash TEXT
      );
    ''');

    // Camps table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS camps (
        id TEXT PRIMARY KEY,
        camp_code TEXT NOT NULL UNIQUE,
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
        created_at TEXT NOT NULL,
        updated_at TEXT
      );
    ''');

    // Patients table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL UNIQUE,
        camp_id TEXT NOT NULL,
        camp_code TEXT NOT NULL,
        intake_date TEXT NOT NULL,
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
        created_at TEXT NOT NULL,
        updated_at TEXT,
        created_by_user_id TEXT NOT NULL,
        created_by_device_id TEXT NOT NULL,
        tenant_id TEXT DEFAULT 'tenant_bir_hospital',
        is_synced INTEGER NOT NULL DEFAULT 1,
        synced_at TEXT
      );
    ''');

    // Clinical Visits table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS clinical_visits (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        camp_id TEXT NOT NULL,
        visit_date TEXT NOT NULL,
        deliveries INTEGER,
        living_children INTEGER,
        abortions INTEGER,
        anamnesis_json TEXT,
        uterus_inside INTEGER DEFAULT 1,
        vulva_remarks TEXT,
        vagina_remarks TEXT,
        cervix_remarks TEXT,
        uterus_remarks TEXT,
        pelvic_floor_tone TEXT,
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
        created_at TEXT NOT NULL,
        updated_at TEXT,
        created_by_user_id TEXT NOT NULL,
        tenant_id TEXT DEFAULT 'tenant_bir_hospital',
        is_synced INTEGER NOT NULL DEFAULT 1
      );
    ''');

    // Audit Logs table
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        user_role TEXT NOT NULL,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        details_json TEXT NOT NULL,
        device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        log_hash TEXT NOT NULL
      );
    ''');

    // Indexes for fast lookup
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_pg_patients_camp_id ON patients(camp_id);');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_pg_patients_patient_id ON patients(patient_id);');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_pg_patients_mobile ON patients(mobile);');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_pg_visits_patient_id ON clinical_visits(patient_id);');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_pg_visits_camp_id ON clinical_visits(camp_id);');
  }

  /// Two-way sync: Syncs all local SQLite records into the PostgreSQL central database
  Future<PostgresSyncResult> syncSqliteToPostgres({
    PostgresConfig? config,
    DatabaseService? localDbService,
  }) async {
    final sw = Stopwatch()..start();
    final dbService = localDbService ?? DatabaseService();
    final localDb = await dbService.database;

    try {
      final conn = await getConnection(config: config);
      await initializePostgresSchema(config: config);

      int syncedUsersCount = 0;
      int syncedCampsCount = 0;
      int syncedPatientsCount = 0;
      int syncedVisitsCount = 0;

      // 1. Sync Users
      final localUsers = await localDb.query(DatabaseTables.tableUsers);
      for (final u in localUsers) {
        await conn.execute(
          Sql.named('''
            INSERT INTO users (id, name, email, phone, role, is_active, last_login_at, assigned_camp_ids, tenant_id, tenant_name, password_hash, pin_hash)
            VALUES (@id, @name, @email, @phone, @role, @is_active, @last_login_at, @assigned_camp_ids, @tenant_id, @tenant_name, @password_hash, @pin_hash)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              email = EXCLUDED.email,
              phone = EXCLUDED.phone,
              role = EXCLUDED.role,
              is_active = EXCLUDED.is_active,
              last_login_at = EXCLUDED.last_login_at;
          '''),
          parameters: {
            'id': u['id']?.toString() ?? '',
            'name': u['name']?.toString() ?? '',
            'email': u['email']?.toString() ?? '',
            'phone': u['phone']?.toString(),
            'role': u['role']?.toString() ?? '',
            'is_active': u['is_active'] is int ? u['is_active'] : 1,
            'last_login_at': u['last_login_at']?.toString(),
            'assigned_camp_ids': u['assigned_camp_ids']?.toString(),
            'tenant_id': u['tenant_id']?.toString(),
            'tenant_name': u['tenant_name']?.toString(),
            'password_hash': u['password_hash']?.toString(),
            'pin_hash': u['pin_hash']?.toString(),
          },
        );
        syncedUsersCount++;
      }

      // 2. Sync Camps
      final localCamps = await localDb.query(DatabaseTables.tableCamps);
      for (final c in localCamps) {
        await conn.execute(
          Sql.named('''
            INSERT INTO camps (id, camp_code, name, district, municipality, ward, venue, start_date, end_date, status, assigned_staff_ids, total_patients_registered, tenant_id, organization_name, created_at, updated_at)
            VALUES (@id, @camp_code, @name, @district, @municipality, @ward, @venue, @start_date, @end_date, @status, @assigned_staff_ids, @total_patients_registered, @tenant_id, @organization_name, @created_at, @updated_at)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              status = EXCLUDED.status,
              total_patients_registered = EXCLUDED.total_patients_registered,
              updated_at = EXCLUDED.updated_at;
          '''),
          parameters: {
            'id': c['id']?.toString() ?? '',
            'camp_code': c['camp_code']?.toString() ?? '',
            'name': c['name']?.toString() ?? '',
            'district': c['district']?.toString() ?? '',
            'municipality': c['municipality']?.toString(),
            'ward': c['ward']?.toString(),
            'venue': c['venue']?.toString(),
            'start_date': c['start_date']?.toString() ?? '',
            'end_date': c['end_date']?.toString() ?? '',
            'status': c['status']?.toString() ?? 'active',
            'assigned_staff_ids': c['assigned_staff_ids']?.toString(),
            'total_patients_registered': c['total_patients_registered'] is int ? c['total_patients_registered'] : 0,
            'tenant_id': c['tenant_id']?.toString(),
            'organization_name': c['organization_name']?.toString(),
            'created_at': c['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            'updated_at': c['updated_at']?.toString(),
          },
        );
        syncedCampsCount++;
      }

      // 3. Sync Patients
      final localPatients = await localDb.query(DatabaseTables.tablePatients);
      for (final p in localPatients) {
        await conn.execute(
          Sql.named('''
            INSERT INTO patients (
              id, patient_id, camp_id, camp_code, intake_date, first_name, surname, age,
              spouse_or_father_name, relationship_type, mobile, district, municipality, ward,
              contact_person, contact_mobile, marital_status, marital_age, reasons_for_visit,
              consent_treatment, consent_store_medical_info, created_at, updated_at,
              created_by_user_id, created_by_device_id, tenant_id, is_synced, synced_at
            ) VALUES (
              @id, @patient_id, @camp_id, @camp_code, @intake_date, @first_name, @surname, @age,
              @spouse_or_father_name, @relationship_type, @mobile, @district, @municipality, @ward,
              @contact_person, @contact_mobile, @marital_status, @marital_age, @reasons_for_visit,
              @consent_treatment, @consent_store_medical_info, @created_at, @updated_at,
              @created_by_user_id, @created_by_device_id, @tenant_id, 1, @synced_at
            )
            ON CONFLICT (id) DO UPDATE SET
              first_name = EXCLUDED.first_name,
              surname = EXCLUDED.surname,
              age = EXCLUDED.age,
              mobile = EXCLUDED.mobile,
              ward = EXCLUDED.ward,
              reasons_for_visit = EXCLUDED.reasons_for_visit,
              updated_at = EXCLUDED.updated_at,
              is_synced = 1,
              synced_at = EXCLUDED.synced_at;
          '''),
          parameters: {
            'id': p['id']?.toString() ?? '',
            'patient_id': p['patient_id']?.toString() ?? '',
            'camp_id': p['camp_id']?.toString() ?? '',
            'camp_code': p['camp_code']?.toString() ?? '',
            'intake_date': p['intake_date']?.toString() ?? '',
            'first_name': p['first_name']?.toString() ?? '',
            'surname': p['surname']?.toString() ?? '',
            'age': p['age'] is int ? p['age'] : 0,
            'spouse_or_father_name': p['spouse_or_father_name']?.toString(),
            'relationship_type': p['relationship_type']?.toString(),
            'mobile': p['mobile']?.toString() ?? '',
            'district': p['district']?.toString(),
            'municipality': p['municipality']?.toString(),
            'ward': p['ward']?.toString() ?? '',
            'contact_person': p['contact_person']?.toString(),
            'contact_mobile': p['contact_mobile']?.toString(),
            'marital_status': p['marital_status']?.toString(),
            'marital_age': p['marital_age'] is int ? p['marital_age'] : null,
            'reasons_for_visit': p['reasons_for_visit']?.toString(),
            'consent_treatment': p['consent_treatment'] is int ? p['consent_treatment'] : 1,
            'consent_store_medical_info': p['consent_store_medical_info'] is int ? p['consent_store_medical_info'] : 1,
            'created_at': p['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            'updated_at': p['updated_at']?.toString(),
            'created_by_user_id': p['created_by_user_id']?.toString() ?? '',
            'created_by_device_id': p['created_by_device_id']?.toString() ?? '',
            'tenant_id': p['tenant_id']?.toString() ?? 'tenant_bir_hospital',
            'synced_at': DateTime.now().toIso8601String(),
          },
        );

        // Mark synced in local SQLite
        await localDb.update(
          DatabaseTables.tablePatients,
          {'is_synced': 1, 'synced_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [p['id']],
        );
        syncedPatientsCount++;
      }

      // 4. Sync Clinical Visits
      final localVisits = await localDb.query(DatabaseTables.tableClinicalVisits);
      for (final v in localVisits) {
        await conn.execute(
          Sql.named('''
            INSERT INTO clinical_visits (
              id, patient_id, camp_id, visit_date, deliveries, living_children, abortions,
              anamnesis_json, uterus_inside, vulva_remarks, vagina_remarks, cervix_remarks,
              uterus_remarks, pelvic_floor_tone, pop_anterior_stage, pop_middle_stage,
              pop_posterior_stage, highest_pop_stage, urine_test, pregnancy_test,
              systolic_bp, diastolic_bp, pulse, spo2, glucose, ecg_notes, diagnoses,
              counseling, pessary_type, pessary_size, surgical_referral, medications,
              custom_medication, follow_up_needed, follow_up_destination, outtake_notes,
              created_at, updated_at, created_by_user_id, tenant_id, is_synced
            ) VALUES (
              @id, @patient_id, @camp_id, @visit_date, @deliveries, @living_children, @abortions,
              @anamnesis_json, @uterus_inside, @vulva_remarks, @vagina_remarks, @cervix_remarks,
              @uterus_remarks, @pelvic_floor_tone, @pop_anterior_stage, @pop_middle_stage,
              @pop_posterior_stage, @highest_pop_stage, @urine_test, @pregnancy_test,
              @systolic_bp, @diastolic_bp, @pulse, @spo2, @glucose, @ecg_notes, @diagnoses,
              @counseling, @pessary_type, @pessary_size, @surgical_referral, @medications,
              @custom_medication, @follow_up_needed, @follow_up_destination, @outtake_notes,
              @created_at, @updated_at, @created_by_user_id, @tenant_id, 1
            )
            ON CONFLICT (id) DO UPDATE SET
              highest_pop_stage = EXCLUDED.highest_pop_stage,
              diagnoses = EXCLUDED.diagnoses,
              counseling = EXCLUDED.counseling,
              pessary_type = EXCLUDED.pessary_type,
              medications = EXCLUDED.medications,
              updated_at = EXCLUDED.updated_at,
              is_synced = 1;
          '''),
          parameters: {
            'id': v['id']?.toString() ?? '',
            'patient_id': v['patient_id']?.toString() ?? '',
            'camp_id': v['camp_id']?.toString() ?? '',
            'visit_date': v['visit_date']?.toString() ?? '',
            'deliveries': v['deliveries'] is int ? v['deliveries'] : null,
            'living_children': v['living_children'] is int ? v['living_children'] : null,
            'abortions': v['abortions'] is int ? v['abortions'] : null,
            'anamnesis_json': v['anamnesis_json']?.toString(),
            'uterus_inside': v['uterus_inside'] is int ? v['uterus_inside'] : 1,
            'vulva_remarks': v['vulva_remarks']?.toString(),
            'vagina_remarks': v['vagina_remarks']?.toString(),
            'cervix_remarks': v['cervix_remarks']?.toString(),
            'uterus_remarks': v['uterus_remarks']?.toString(),
            'pelvic_floor_tone': v['pelvic_floor_tone']?.toString() ?? 'normal',
            'pop_anterior_stage': v['pop_anterior_stage'] is int ? v['pop_anterior_stage'] : 0,
            'pop_middle_stage': v['pop_middle_stage'] is int ? v['pop_middle_stage'] : 0,
            'pop_posterior_stage': v['pop_posterior_stage'] is int ? v['pop_posterior_stage'] : 0,
            'highest_pop_stage': v['highest_pop_stage'] is int ? v['highest_pop_stage'] : 0,
            'urine_test': v['urine_test']?.toString(),
            'pregnancy_test': v['pregnancy_test']?.toString(),
            'systolic_bp': v['systolic_bp'] is int ? v['systolic_bp'] : null,
            'diastolic_bp': v['diastolic_bp'] is int ? v['diastolic_bp'] : null,
            'pulse': v['pulse'] is int ? v['pulse'] : null,
            'spo2': v['spo2'] is int ? v['spo2'] : null,
            'glucose': v['glucose'] is int ? v['glucose'] : null,
            'ecg_notes': v['ecg_notes']?.toString(),
            'diagnoses': v['diagnoses']?.toString(),
            'counseling': v['counseling']?.toString(),
            'pessary_type': v['pessary_type']?.toString(),
            'pessary_size': v['pessary_size']?.toString(),
            'surgical_referral': v['surgical_referral']?.toString(),
            'medications': v['medications']?.toString(),
            'custom_medication': v['custom_medication']?.toString(),
            'follow_up_needed': v['follow_up_needed'] is int ? v['follow_up_needed'] : null,
            'follow_up_destination': v['follow_up_destination']?.toString(),
            'outtake_notes': v['outtake_notes']?.toString(),
            'created_at': v['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            'updated_at': v['updated_at']?.toString(),
            'created_by_user_id': v['created_by_user_id']?.toString() ?? '',
            'tenant_id': v['tenant_id']?.toString() ?? 'tenant_bir_hospital',
          },
        );

        await localDb.update(
          DatabaseTables.tableClinicalVisits,
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [v['id']],
        );
        syncedVisitsCount++;
      }

      sw.stop();
      return PostgresSyncResult(
        success: true,
        syncedUsers: syncedUsersCount,
        syncedCamps: syncedCampsCount,
        syncedPatients: syncedPatientsCount,
        syncedVisits: syncedVisitsCount,
        duration: sw.elapsed,
      );
    } catch (e, st) {
      debugPrint('Postgres sync failed: $e\n$st');
      sw.stop();
      return PostgresSyncResult(
        success: false,
        errorMessage: e.toString(),
        duration: sw.elapsed,
      );
    }
  }

  /// Direct insert/update patient to PostgreSQL
  Future<void> directSavePatient(Map<String, dynamic> p, {PostgresConfig? config}) async {
    final conn = await getConnection(config: config);
    await conn.execute(
      Sql.named('''
        INSERT INTO patients (
          id, patient_id, camp_id, camp_code, intake_date, first_name, surname, age,
          spouse_or_father_name, relationship_type, mobile, district, municipality, ward,
          contact_person, contact_mobile, marital_status, marital_age, reasons_for_visit,
          consent_treatment, consent_store_medical_info, created_at, updated_at,
          created_by_user_id, created_by_device_id, tenant_id, is_synced, synced_at
        ) VALUES (
          @id, @patient_id, @camp_id, @camp_code, @intake_date, @first_name, @surname, @age,
          @spouse_or_father_name, @relationship_type, @mobile, @district, @municipality, @ward,
          @contact_person, @contact_mobile, @marital_status, @marital_age, @reasons_for_visit,
          @consent_treatment, @consent_store_medical_info, @created_at, @updated_at,
          @created_by_user_id, @created_by_device_id, @tenant_id, 1, @synced_at
        )
        ON CONFLICT (id) DO UPDATE SET
          first_name = EXCLUDED.first_name,
          surname = EXCLUDED.surname,
          age = EXCLUDED.age,
          mobile = EXCLUDED.mobile,
          ward = EXCLUDED.ward,
          reasons_for_visit = EXCLUDED.reasons_for_visit,
          updated_at = EXCLUDED.updated_at,
          is_synced = 1,
          synced_at = EXCLUDED.synced_at;
      '''),
      parameters: {
        'id': p['id']?.toString() ?? '',
        'patient_id': p['patient_id']?.toString() ?? '',
        'camp_id': p['camp_id']?.toString() ?? '',
        'camp_code': p['camp_code']?.toString() ?? '',
        'intake_date': p['intake_date']?.toString() ?? '',
        'first_name': p['first_name']?.toString() ?? '',
        'surname': p['surname']?.toString() ?? '',
        'age': p['age'] is int ? p['age'] : 0,
        'spouse_or_father_name': p['spouse_or_father_name']?.toString(),
        'relationship_type': p['relationship_type']?.toString(),
        'mobile': p['mobile']?.toString() ?? '',
        'district': p['district']?.toString(),
        'municipality': p['municipality']?.toString(),
        'ward': p['ward']?.toString() ?? '',
        'contact_person': p['contact_person']?.toString(),
        'contact_mobile': p['contact_mobile']?.toString(),
        'marital_status': p['marital_status']?.toString(),
        'marital_age': p['marital_age'] is int ? p['marital_age'] : null,
        'reasons_for_visit': p['reasons_for_visit']?.toString(),
        'consent_treatment': p['consent_treatment'] is int ? p['consent_treatment'] : 1,
        'consent_store_medical_info': p['consent_store_medical_info'] is int ? p['consent_store_medical_info'] : 1,
        'created_at': p['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        'updated_at': p['updated_at']?.toString(),
        'created_by_user_id': p['created_by_user_id']?.toString() ?? '',
        'created_by_device_id': p['created_by_device_id']?.toString() ?? '',
        'tenant_id': p['tenant_id']?.toString() ?? 'tenant_bir_hospital',
        'synced_at': DateTime.now().toIso8601String(),
      },
    );
  }
}
