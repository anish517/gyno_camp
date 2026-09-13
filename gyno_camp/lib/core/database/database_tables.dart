class DatabaseTables {
  // Table names
  static const String tableUsers = 'users';
  static const String tableDevices = 'devices';
  static const String tableCamps = 'camps';
  static const String tablePatients = 'patients';
  static const String tableClinicalVisits = 'clinical_visits';
  static const String tableAuditLogs = 'audit_logs';
  static const String tableLookupItems = 'lookup_items';

  // Users Table
  static const String createTableUsers = '''
    CREATE TABLE IF NOT EXISTS $tableUsers (
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
  ''';

  // Devices Table
  static const String createTableDevices = '''
    CREATE TABLE IF NOT EXISTS $tableDevices (
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
      pin_hash TEXT,
      tenant_id TEXT DEFAULT 'tenant_default'
    );
  ''';

  // Camps Table
  static const String createTableCamps = '''
    CREATE TABLE IF NOT EXISTS $tableCamps (
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
  ''';

  // Patients Table (with duplicate detector indexing)
  static const String createTablePatients = '''
    CREATE TABLE IF NOT EXISTS $tablePatients (
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
      is_synced INTEGER NOT NULL DEFAULT 0,
      synced_at TEXT
    );
  ''';

  // Clinical Visits Table (All sections of the Yellow Form)
  static const String createTableClinicalVisits = '''
    CREATE TABLE IF NOT EXISTS $tableClinicalVisits (
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
      is_synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(patient_id) REFERENCES $tablePatients(patient_id)
    );
  ''';

  // Audit Logs Table
  static const String createTableAuditLogs = '''
    CREATE TABLE IF NOT EXISTS $tableAuditLogs (
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
      log_hash TEXT NOT NULL,
      previous_hash TEXT,
      tenant_id TEXT DEFAULT 'tenant_default'
    );
  ''';

  // Lookup Items Table
  static const String createTableLookupItems = '''
    CREATE TABLE IF NOT EXISTS $tableLookupItems (
      id TEXT PRIMARY KEY,
      category TEXT NOT NULL,
      code TEXT NOT NULL,
      label_en TEXT NOT NULL,
      label_ne TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0
    );
  ''';

  // Indexes for high performance and duplicate detection
  static const List<String> createIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_patients_mobile ON $tablePatients (mobile);',
    'CREATE INDEX IF NOT EXISTS idx_patients_name_ward ON $tablePatients (first_name, surname, ward);',
    'CREATE INDEX IF NOT EXISTS idx_patients_camp_id ON $tablePatients (camp_id);',
    'CREATE INDEX IF NOT EXISTS idx_clinical_visits_patient_id ON $tableClinicalVisits (patient_id);',
    'CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON $tableAuditLogs (user_id);',
    'CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON $tableAuditLogs (action);',
    'CREATE INDEX IF NOT EXISTS idx_lookup_category ON $tableLookupItems (category);',
  ];
}
