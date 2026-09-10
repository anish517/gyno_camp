-- ============================================================================
-- GynoCamp EMR - PostgreSQL Production Schema
-- Designed for enterprise-grade persistent data storage, multi-tenant camps,
-- high-speed indexing, and seamless two-way synchronization with offline nodes.
-- ============================================================================

-- Create schema if required
CREATE SCHEMA IF NOT EXISTS gynocamp;
SET search_path TO gynocamp, public;

-- 1. USERS & RBAC TABLE
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
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

CREATE INDEX IF NOT EXISTS idx_users_email ON users(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- 2. DEVICES TABLE
CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    device_name TEXT NOT NULL,
    model TEXT,
    hardware_fingerprint TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL,
    registered_by_user_id TEXT,
    registered_by_name TEXT,
    otp_hash TEXT,
    otp_expires_at TIMESTAMPTZ,
    registered_at TIMESTAMPTZ NOT NULL,
    approved_at TIMESTAMPTZ,
    approved_by_user_id TEXT,
    pin_hash TEXT
);

-- 3. CAMPS TABLE
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_camps_code ON camps(camp_code);
CREATE INDEX IF NOT EXISTS idx_camps_status ON camps(status);

-- 4. PATIENTS TABLE (Yellow Form Page 1)
CREATE TABLE IF NOT EXISTS patients (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL UNIQUE,
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
    tenant_id TEXT DEFAULT 'tenant_bir_hospital',
    is_synced INTEGER NOT NULL DEFAULT 1,
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_patients_camp FOREIGN KEY (camp_id) REFERENCES camps(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_patients_camp_id ON patients(camp_id);
CREATE INDEX IF NOT EXISTS idx_patients_patient_id ON patients(patient_id);
CREATE INDEX IF NOT EXISTS idx_patients_mobile ON patients(mobile);
CREATE INDEX IF NOT EXISTS idx_patients_name ON patients(LOWER(first_name), LOWER(surname));
CREATE INDEX IF NOT EXISTS idx_patients_intake_date ON patients(intake_date);

-- 5. CLINICAL VISITS TABLE (Yellow Form Page 2 & Medical Examination)
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by_user_id TEXT NOT NULL,
    tenant_id TEXT DEFAULT 'tenant_bir_hospital',
    is_synced INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT fk_visits_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_visits_patient_id ON clinical_visits(patient_id);
CREATE INDEX IF NOT EXISTS idx_visits_camp_id ON clinical_visits(camp_id);
CREATE INDEX IF NOT EXISTS idx_visits_visit_date ON clinical_visits(visit_date);
CREATE INDEX IF NOT EXISTS idx_visits_highest_pop ON clinical_visits(highest_pop_stage);

-- 6. AUDIT LOGS TABLE (Tamper-evident logging)
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
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    log_hash TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs(action);

-- 7. LOOKUP ITEMS TABLE (Controlled vocabularies & ICD-10)
CREATE TABLE IF NOT EXISTS lookup_items (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    code TEXT NOT NULL,
    label_en TEXT NOT NULL,
    label_ne TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_lookup_cat ON lookup_items(category);
