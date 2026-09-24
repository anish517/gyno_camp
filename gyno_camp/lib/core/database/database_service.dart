import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../constants/clinical_constants.dart';
import '../security/security_service.dart';
import 'database_tables.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  /// Allows setting an external database (e.g. sqflite_common_ffi in-memory DB for unit testing)
  void setDatabaseForTesting(Database db) {
    _db = db;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (kIsWeb) {
      path = AppConstants.databaseName;
    } else if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final supportDir = await getApplicationSupportDirectory();
      await Directory(supportDir.path).create(recursive: true);
      path = p.join(supportDir.path, AppConstants.databaseName);
    } else {
      final dbPath = await getDatabasesPath();
      path = p.join(dbPath, AppConstants.databaseName);
    }

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: (db, version) async {
        await _createDb(db);
        await _seedInitialData(db);
      },
      onOpen: (db) async {
        await _ensureAllColumnsExist(db);
      },
    );
  }

  Future<void> _ensureAllColumnsExist(Database db) async {
    final columnsByTable = <String, List<Map<String, String>>>{
      DatabaseTables.tableUsers: [
        {'name': 'password_hash', 'def': 'password_hash TEXT'},
        {'name': 'pin_hash', 'def': 'pin_hash TEXT'},
      ],
      DatabaseTables.tableCamps: [
        {'name': 'tenant_id', 'def': "tenant_id TEXT DEFAULT 'tenant_default'"},
        {'name': 'organization_name', 'def': "organization_name TEXT DEFAULT 'Outreach Health Center'"},
        {'name': 'province', 'def': "province TEXT DEFAULT 'Bagmati'"},
        {'name': 'doctor_name', 'def': "doctor_name TEXT DEFAULT ''"},
        {'name': 'doctor_names', 'def': "doctor_names TEXT DEFAULT ''"},
      ],
      DatabaseTables.tablePatients: [
        {'name': 'tenant_id', 'def': "tenant_id TEXT DEFAULT 'tenant_default'"},
        {'name': 'province', 'def': "province TEXT DEFAULT 'Bagmati'"},
      ],
      DatabaseTables.tableClinicalVisits: [
        {'name': 'tenant_id', 'def': "tenant_id TEXT DEFAULT 'tenant_default'"},
        {'name': 'is_follow_up', 'def': 'is_follow_up INTEGER DEFAULT 0'},
        {'name': 'follow_up_notes', 'def': 'follow_up_notes TEXT'},
        {'name': 'surgery_done', 'def': 'surgery_done INTEGER DEFAULT 0'},
        {'name': 'surgery_type', 'def': 'surgery_type TEXT'},
        {'name': 'attending_doctor_names', 'def': "attending_doctor_names TEXT DEFAULT ''"},
        {'name': 'primary_doctor_name', 'def': "primary_doctor_name TEXT DEFAULT ''"},
      ],
      DatabaseTables.tableAuditLogs: [
        {'name': 'tenant_id', 'def': "tenant_id TEXT DEFAULT 'tenant_default'"},
        {'name': 'previous_hash', 'def': 'previous_hash TEXT'},
      ],
      DatabaseTables.tableLookupItems: [
        {'name': 'tenant_id', 'def': "tenant_id TEXT DEFAULT 'tenant_default'"},
        {'name': 'is_deleted', 'def': 'is_deleted INTEGER DEFAULT 0'},
        {'name': 'sub_category', 'def': 'sub_category TEXT'},
        {'name': 'camp_id', 'def': 'camp_id TEXT'},
        {'name': 'excluded_camp_ids', 'def': 'excluded_camp_ids TEXT'},
        {'name': 'is_synced', 'def': 'is_synced INTEGER DEFAULT 0'},
        {'name': 'updated_at', 'def': 'updated_at TEXT'},
      ],
    };

    for (final entry in columnsByTable.entries) {
      final table = entry.key;
      try {
        final tableInfo = await db.rawQuery("PRAGMA table_info($table)");
        final existingColumns = tableInfo
            .map((row) => (row['name'] as String?)?.toLowerCase())
            .whereType<String>()
            .toSet();

        for (final col in entry.value) {
          final colName = col['name']!.toLowerCase();
          if (!existingColumns.contains(colName)) {
            await db.execute("ALTER TABLE $table ADD COLUMN ${col['def']}");
          }
        }
      } catch (_) {
        // Safe to ignore if table does not exist or column could not be added
      }
    }

    // Ensure metadata table exists
    try {
      await db.execute(DatabaseTables.createTableMetadata);
    } catch (_) {}

    // Sanitize any legacy stray codes like single-letter "k" or placeholders
    try {
      final legacyItems = await db.rawQuery(
        "SELECT id, label_en, code FROM ${DatabaseTables.tableLookupItems} WHERE LENGTH(TRIM(code)) <= 1 OR LOWER(code) = 'k'",
      );
      for (final item in legacyItems) {
        final id = item['id'] as String;
        final label = (item['label_en'] as String? ?? '').trim();
        final cleanSlug = label.isNotEmpty
            ? label.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').replaceAll(RegExp(r'_+'), '_')
            : 'item_$id';
        await db.rawUpdate(
          "UPDATE ${DatabaseTables.tableLookupItems} SET code = ? WHERE id = ?",
          [cleanSlug, id],
        );
      }
    } catch (_) {}

    // Enforce single active camp invariant: ensure at most 1 camp is OPEN in local SQLite
    try {
      final openCamps = await db.rawQuery(
        "SELECT id FROM ${DatabaseTables.tableCamps} WHERE status = 'OPEN' ORDER BY start_date DESC",
      );
      if (openCamps.length > 1) {
        for (int i = 1; i < openCamps.length; i++) {
          final staleId = openCamps[i]['id'] as String;
          await db.rawUpdate(
            "UPDATE ${DatabaseTables.tableCamps} SET status = 'CLOSED' WHERE id = ?",
            [staleId],
          );
        }
      }
    } catch (_) {}

    // Migrate legacy hardcoded doctor name to generic SaaS Admin identity
    try {
      await db.rawUpdate(
        "UPDATE ${DatabaseTables.tableUsers} SET name = 'System Administrator (Super Admin)', tenant_name = 'Nepal Health Outreach Network' WHERE id = 'usr-superadmin-01' AND name = 'Dr. Aarav Sharma (Lead Gynecologist)'",
      );
    } catch (_) {}

    // Guarantee bootstrap Super Admin has valid credentials in SQLite
    try {
      final adminPassHash = SecurityService.hashSha256('admin123');
      final adminPinHash = SecurityService.hashPin('1234');

      final adminCheck = await db.query(
        DatabaseTables.tableUsers,
        where: 'LOWER(email) = ? OR id = ?',
        whereArgs: ['admin@gynocamp.org', 'usr-superadmin-01'],
        limit: 1,
      );

      if (adminCheck.isEmpty) {
        final now = DateTime.now().toIso8601String();
        await db.insert(
          DatabaseTables.tableUsers,
          {
            'id': 'usr-superadmin-01',
            'name': 'System Administrator (Super Admin)',
            'email': 'admin@gynocamp.org',
            'phone': '9851000001',
            'role': AppConstants.roleSuperAdmin,
            'is_active': 1,
            'last_login_at': now,
            'assigned_camp_ids': '',
            'tenant_id': 'tenant_default',
            'tenant_name': 'Nepal Health Outreach Network',
            'password_hash': adminPassHash,
            'pin_hash': adminPinHash,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        await db.rawUpdate(
          "UPDATE ${DatabaseTables.tableUsers} SET role = ?, is_active = 1 WHERE (LOWER(email) = 'admin@gynocamp.org' OR id = 'usr-superadmin-01')",
          [AppConstants.roleSuperAdmin],
        );
        await db.rawUpdate(
          "UPDATE ${DatabaseTables.tableUsers} SET password_hash = ?, pin_hash = ? WHERE (LOWER(email) = 'admin@gynocamp.org' OR id = 'usr-superadmin-01') AND (password_hash IS NULL OR password_hash = '' OR pin_hash IS NULL OR pin_hash = '')",
          [adminPassHash, adminPinHash],
        );
      }
    } catch (_) {}

    // Backfill sub_category for diagnoses and medicines
    try {
      for (final entry in ClinicalConstants.diagnosisCategoryMap.entries) {
        await db.rawUpdate(
          "UPDATE ${DatabaseTables.tableLookupItems} SET sub_category = ? WHERE category = 'diagnosis' AND LOWER(label_en) = LOWER(?) AND (sub_category IS NULL OR sub_category = '')",
          [entry.value, entry.key],
        );
      }
      for (final entry in ClinicalConstants.medicationCategoryMap.entries) {
        await db.rawUpdate(
          "UPDATE ${DatabaseTables.tableLookupItems} SET sub_category = ? WHERE category = 'medicine' AND LOWER(label_en) = LOWER(?) AND (sub_category IS NULL OR sub_category = '')",
          [entry.value, entry.key],
        );
      }
    } catch (_) {}
  }


  Future<void> _createDb(Database db) async {
    await db.execute(DatabaseTables.createTableUsers);
    await db.execute(DatabaseTables.createTableDevices);
    await db.execute(DatabaseTables.createTableCamps);
    await db.execute(DatabaseTables.createTablePatients);
    await db.execute(DatabaseTables.createTableClinicalVisits);
    await db.execute(DatabaseTables.createTableAuditLogs);
    await db.execute(DatabaseTables.createTableLookupItems);
    await db.execute(DatabaseTables.createTableMetadata);

    for (final indexQuery in DatabaseTables.createIndexes) {
      await db.execute(indexQuery);
    }
  }

  /// Manually trigger tables creation and seeding on an injected test database
  Future<void> initializeTestDb(Database db) async {
    _db = db;
    await _createDb(db);
    await _seedInitialData(db);
    await _ensureAllColumnsExist(db);
  }

  Future<void> _seedInitialData(Database db) async {
    // 1. Seed initial users for all 3 roles (SaaS multi-tenant defaults)
    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseTables.tableUsers, {
      'id': 'usr-superadmin-01',
      'name': 'System Administrator (Super Admin)',
      'email': 'admin@gynocamp.org',
      'phone': '9851000001',
      'role': AppConstants.roleSuperAdmin,
      'is_active': 1,
      'last_login_at': now,
      'assigned_camp_ids': 'camp-ktm-01,camp-dhn-02',
      'tenant_id': 'tenant_default',
      'tenant_name': 'Nepal Health Outreach Network',
      'password_hash': SecurityService.hashSha256('admin123'),
      'pin_hash': SecurityService.hashPin('1234'),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert(DatabaseTables.tableUsers, {
      'id': 'usr-datataker-01',
      'name': 'Sita Sharma (Field Nurse)',
      'email': 'sita@gynocamp.org',
      'phone': '9841234567',
      'role': AppConstants.roleDataTaker,
      'is_active': 1,
      'last_login_at': now,
      'assigned_camp_ids': 'camp-ktm-01',
      'tenant_id': 'tenant_default',
      'tenant_name': 'Community Health Outreach',
      'password_hash': SecurityService.hashSha256('nurse123'),
      'pin_hash': SecurityService.hashPin('1234'),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert(DatabaseTables.tableUsers, {
      'id': 'usr-dataanalyst-01',
      'name': 'Bikash Adhikari',
      'email': 'analyst@gynocamp.org',
      'phone': '9860123456',
      'role': AppConstants.roleDataAnalyst,
      'is_active': 1,
      'last_login_at': now,
      'assigned_camp_ids': '',
      'tenant_id': 'tenant_default',
      'tenant_name': 'Community Health Outreach',
      'password_hash': SecurityService.hashSha256('analyst123'),
      'pin_hash': SecurityService.hashPin('1234'),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // 2. Seed active sample camp
    await db.insert(DatabaseTables.tableCamps, {
      'id': 'camp-ktm-01',
      'camp_code': 'KTM01',
      'name': 'Outreach Gyno Health Camp',
      'province': 'Bagmati',
      'district': 'Kathmandu',
      'municipality': 'Budhanilkantha Municipality',
      'ward': '03',
      'venue': 'Primary Health Care Center',
      'start_date': DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      'end_date': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
      'status': AppConstants.campStatusOpen,
      'assigned_staff_ids': 'usr-datataker-01,usr-superadmin-01',
      'total_patients_registered': 0,
      'tenant_id': 'tenant_default',
      'organization_name': 'Community Health Outreach Mission',
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // 3. Seed default diagnoses from Yellow Form
    int sortIdx = 0;
    for (final diag in ClinicalConstants.defaultDiagnoses) {
      sortIdx++;
      await db.insert(DatabaseTables.tableLookupItems, {
        'id': 'diag-$sortIdx',
        'category': 'diagnosis',
        'sub_category': ClinicalConstants.diagnosisCategoryMap[diag] ?? 'General / Other',
        'code': diag.toLowerCase().replaceAll(' ', '_'),
        'label_en': diag,
        'label_ne': _getNepaliDiagnosisName(diag),
        'is_active': 1,
        'sort_order': sortIdx,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 4. Seed default medicines from Yellow Form
    sortIdx = 0;
    for (final med in ClinicalConstants.defaultMedications) {
      sortIdx++;
      await db.insert(DatabaseTables.tableLookupItems, {
        'id': 'med-$sortIdx',
        'category': 'medicine',
        'sub_category': ClinicalConstants.medicationCategoryMap[med] ?? 'Other / Custom',
        'code': med.toLowerCase().replaceAll(' ', '_'),
        'label_en': med,
        'label_ne': med,
        'is_active': 1,
        'sort_order': sortIdx,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 5. Seed default referral hospitals (Surgical Referral Centers)
    sortIdx = 0;
    for (final hosp in ClinicalConstants.referralHospitals) {
      sortIdx++;
      await db.insert(DatabaseTables.tableLookupItems, {
        'id': 'hosp-$sortIdx',
        'category': 'referral_hospital',
        'code': hosp.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_'),
        'label_en': hosp,
        'label_ne': hosp,
        'is_active': 1,
        'sort_order': sortIdx,
        'tenant_id': 'tenant_default',
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Mark default lookups as seeded for tenant_default
    await db.insert(DatabaseTables.tableMetadata, {
      'key': 'lookup_defaults_seeded_tenant_default',
      'value': 'true',
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 6. Seed primary administrative workstation
    await db.insert(DatabaseTables.tableDevices, {
      'device_id': 'dev-admin-workstation',
      'device_name': 'Central Command Workstation (Admin)',
      'model': 'Medical Outreach Terminal',
      'hardware_fingerprint': SecurityService.generateDeviceFingerprint(brand: 'Admin', model: 'Console', serial: 'ADMIN-001'),
      'status': AppConstants.deviceStatusApproved,
      'registered_by_user_id': 'usr-superadmin-01',
      'registered_by_name': 'System Administrator (Super Admin)',
      'registered_at': now,
      'approved_by_user_id': 'usr-superadmin-01',
      'approved_at': now,
      'tenant_id': 'tenant_default',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

  }

  static String _getNepaliDiagnosisName(String en) {
    switch (en.toLowerCase()) {
      case 'bacterial vaginosis':
        return 'ब्याक्टेरियल संक्रमण';
      case 'candid infection':
        return 'कन्डिडा (ढुसी) संक्रमण';
      case 'trichomonas':
        return 'ट्राइकोमोनियासिस';
      case 'pid':
        return 'तल्लो पेटको सुजन (PID)';
      case 'cervicitis':
        return 'पाठेघरको मुखको सुजन';
      case 'stress incontinence':
        return 'खोक्दा/हाँस्दा पिसाब चुहिने समस्या';
      case 'urge incontinence':
        return 'पिसाब थाम्न नसक्ने समस्या';
      case 'weak pelvic floor muscle':
        return 'पेल्भिक मांसपेशी कमजोर';
      case 'pregnancy':
        return 'गर्भावस्था';
      default:
        return en;
    }
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Map<String, dynamic>> exportDatabaseSnapshot() async {
    final db = await database;
    final camps = await db.query(DatabaseTables.tableCamps);
    final users = await db.query(DatabaseTables.tableUsers);
    final devices = await db.query(DatabaseTables.tableDevices);
    final patients = await db.query(DatabaseTables.tablePatients);
    final clinicalVisits = await db.query(DatabaseTables.tableClinicalVisits);
    final lookups = await db.query(DatabaseTables.tableLookupItems);
    final auditLogs = await db.query(DatabaseTables.tableAuditLogs);

    return {
      'exported_at': DateTime.now().toIso8601String(),
      'version': AppConstants.databaseVersion,
      'app': AppConstants.appName,
      'tables': {
        DatabaseTables.tableCamps: camps,
        DatabaseTables.tableUsers: users.map((u) {
          final copy = Map<String, dynamic>.from(u);
          copy.remove('password_hash');
          copy.remove('pin_hash');
          return copy;
        }).toList(),
        DatabaseTables.tableDevices: devices,
        DatabaseTables.tablePatients: patients,
        DatabaseTables.tableClinicalVisits: clinicalVisits,
        DatabaseTables.tableLookupItems: lookups,
        DatabaseTables.tableAuditLogs: auditLogs,
      },
    };
  }

  /// Restores SQLite database from a previously exported snapshot.
  /// Runs inside an atomic transaction to ensure zero partial corruption.
  Future<Map<String, int>> restoreDatabaseSnapshot(Map<String, dynamic> snapshot) async {
    if (!snapshot.containsKey('tables') || snapshot['tables'] is! Map) {
      throw const FormatException('Invalid backup snapshot format: missing "tables" object');
    }

    final tables = snapshot['tables'] as Map<String, dynamic>;
    final db = await database;
    final Map<String, int> restoredCounts = {};

    await db.transaction((txn) async {
      for (final entry in tables.entries) {
        final tableName = entry.key;
        final rows = entry.value;

        if (rows is List) {
          int count = 0;
          for (final row in rows) {
            if (row is Map) {
              final rowMap = Map<String, dynamic>.from(row);
              await txn.insert(
                tableName,
                rowMap,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              count++;
            }
          }
          restoredCounts[tableName] = count;
        }
      }
    });

    return restoredCounts;
  }
}
