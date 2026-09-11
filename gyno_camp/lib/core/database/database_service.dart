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
    final migrations = [
      "ALTER TABLE ${DatabaseTables.tableUsers} ADD COLUMN password_hash TEXT",
      "ALTER TABLE ${DatabaseTables.tableUsers} ADD COLUMN pin_hash TEXT",
      "ALTER TABLE ${DatabaseTables.tableCamps} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_default'",
      "ALTER TABLE ${DatabaseTables.tableCamps} ADD COLUMN organization_name TEXT DEFAULT 'Outreach Health Center'",
      "ALTER TABLE ${DatabaseTables.tablePatients} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_default'",
      "ALTER TABLE ${DatabaseTables.tableClinicalVisits} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_default'",
      "ALTER TABLE ${DatabaseTables.tableAuditLogs} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_default'",
    ];
    for (final sql in migrations) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Safe to ignore if column already exists
      }
    }

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
          "UPDATE ${DatabaseTables.tableUsers} SET password_hash = ?, pin_hash = ?, is_active = 1 WHERE (LOWER(email) = 'admin@gynocamp.org' OR id = 'usr-superadmin-01') AND (password_hash IS NULL OR password_hash = '' OR pin_hash IS NULL OR pin_hash = '')",
          [adminPassHash, adminPinHash],
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
        'code': med.toLowerCase().replaceAll(' ', '_'),
        'label_en': med,
        'label_ne': med,
        'is_active': 1,
        'sort_order': sortIdx,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
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
}
