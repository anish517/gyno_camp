import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';
import '../constants/clinical_constants.dart';
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
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.databaseName);

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
      "ALTER TABLE ${DatabaseTables.tableCamps} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_bir_hospital'",
      "ALTER TABLE ${DatabaseTables.tableCamps} ADD COLUMN organization_name TEXT DEFAULT 'Bir Hospital Gyno Outreach'",
      "ALTER TABLE ${DatabaseTables.tablePatients} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_bir_hospital'",
      "ALTER TABLE ${DatabaseTables.tableClinicalVisits} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_bir_hospital'",
      "ALTER TABLE ${DatabaseTables.tableAuditLogs} ADD COLUMN tenant_id TEXT DEFAULT 'tenant_bir_hospital'",
    ];
    for (final sql in migrations) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Safe to ignore if column already exists
      }
    }
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
    // 1. Seed initial users for all 3 roles
    final now = DateTime.now().toIso8601String();
    await db.insert(
      DatabaseTables.tableUsers,
      {
        'id': 'usr-superadmin-01',
        'name': 'Dr. Aruna Shrestha',
        'email': 'admin@gynocamp.org',
        'phone': '9851000001',
        'role': AppConstants.roleSuperAdmin,
        'is_active': 1,
        'last_login_at': now,
        'assigned_camp_ids': 'camp-ktm-01,camp-dhn-02',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.insert(
      DatabaseTables.tableUsers,
      {
        'id': 'usr-datataker-01',
        'name': 'Sita Sharma (Field Nurse)',
        'email': 'sita@gynocamp.org',
        'phone': '9841234567',
        'role': AppConstants.roleDataTaker,
        'is_active': 1,
        'last_login_at': now,
        'assigned_camp_ids': 'camp-ktm-01',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.insert(
      DatabaseTables.tableUsers,
      {
        'id': 'usr-dataanalyst-01',
        'name': 'Bikash Adhikari',
        'email': 'analyst@gynocamp.org',
        'phone': '9860123456',
        'role': AppConstants.roleDataAnalyst,
        'is_active': 1,
        'last_login_at': now,
        'assigned_camp_ids': '',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // 2. Seed active sample camp
    await db.insert(
      DatabaseTables.tableCamps,
      {
        'id': 'camp-ktm-01',
        'camp_code': 'KTM01',
        'name': 'Kathmandu Community Gyno Health Camp',
        'district': 'Kathmandu',
        'municipality': 'Budhanilkantha Municipality',
        'ward': '03',
        'venue': 'Primary Health Care Center',
        'start_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'end_date': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'status': AppConstants.campStatusOpen,
        'assigned_staff_ids': 'usr-datataker-01,usr-superadmin-01',
        'total_patients_registered': 0,
        'tenant_id': 'tenant_bir_hospital',
        'organization_name': 'Bir Hospital Gyno Outreach',
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // 3. Seed default diagnoses from Yellow Form
    int sortIdx = 0;
    for (final diag in ClinicalConstants.defaultDiagnoses) {
      sortIdx++;
      await db.insert(
        DatabaseTables.tableLookupItems,
        {
          'id': 'diag-$sortIdx',
          'category': 'diagnosis',
          'code': diag.toLowerCase().replaceAll(' ', '_'),
          'label_en': diag,
          'label_ne': _getNepaliDiagnosisName(diag),
          'is_active': 1,
          'sort_order': sortIdx,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // 4. Seed default medicines from Yellow Form
    sortIdx = 0;
    for (final med in ClinicalConstants.defaultMedications) {
      sortIdx++;
      await db.insert(
        DatabaseTables.tableLookupItems,
        {
          'id': 'med-$sortIdx',
          'category': 'medicine',
          'code': med.toLowerCase().replaceAll(' ', '_'),
          'label_en': med,
          'label_ne': med,
          'is_active': 1,
          'sort_order': sortIdx,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
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
}
