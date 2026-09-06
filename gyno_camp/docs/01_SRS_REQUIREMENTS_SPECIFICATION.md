# Software Requirements Specification (SRS)
## Gynocamp Patient Registration & Health Camp Management System

**Document Version:** 1.0.0  
**Target Systems:** Android Mobile Application (Data Takers) + Web Admin Panel (Super Admin & Data Analyst)  
**Primary Context:** Women's Gynecological Health Camps in rural and semi-urban Nepal  

---

## 1. Executive Overview
Gynocamp conducts periodic specialized gynaecological and pelvic organ prolapse (POP) health camps for women across remote areas of Nepal. In these remote terrains, field staff operate in environments with intermittent or non-existent electrical grid power and cellular connectivity.

This system provides a reliable, secure, bilingual (Nepali/English) healthcare data solution operating on an **Offline-First Architecture**. Field data captured on registered mobile tablets is encrypted and stored locally in SQLite, then automatically synchronized to the cloud central database once connectivity is restored.

---

## 2. User Roles & Permission Matrix (RBAC)

The system enforces strict Role-Based Access Control (RBAC) across three distinct user roles:

| Capability / Feature | Super Admin (Admin Panel) | Data Taker (Mobile Field App) | Data Analyst (Reporting) |
| :--- | :---: | :---: | :---: |
| **Camp Creation & Calendar Scheduling** | Full Access | No Access | Read-Only |
| **Open / Close Camp for Entry** | Full Access | No Access | No Access |
| **Device Approval & Revocation** | Full Access | No Access | No Access |
| **Form & Medicine List Customization** | Full Access | No Access | No Access |
| **User & Staff Account Management** | Full Access | No Access | No Access |
| **Cross-Camp Data Access** | All Camps | Assigned Camp Only | All Synced Camps |
| **Patient Registration & Auto Patient ID** | Full Access | Full Access | No Access |
| **Clinical 2-Page Yellow Form Entry** | Full Access | Full Access | No Access |
| **Scan & Auto-Fill (OCR/OMR)** | Full Access | Full Access | No Access |
| **Offline Storage & Sync Engine** | Automated | Automated | Automated |
| **One-Tap Summary PDF / Excel Reports** | Full Access | Camp Summary Only | Full Export Engine |
| **Tamper-Evident User Activity Log** | Full Audit Trail | Self-Activity Only | Read-Only Access |

---

## 3. Detailed Functional Requirements

### FR-1: Patient Registration & Auto Patient ID
- **FR-1.1:** The system shall automatically generate an immutable, unique Patient ID at the point of registration without manual staff numbering.
- **FR-1.2:** The format shall follow `GC-[CampCode]-[Year]-[SequentialNumber]` (e.g., `GC-KTM01-2026-00042`).
- **FR-1.3:** The app shall render a printable/scannable barcode and QR code matching the Patient ID for follow-up slips.

### FR-2: Scan & Auto-Fill (OCR / OMR)
- **FR-2.1:** Staff may photograph the 2-page completed paper "Yellow Form" directly through the app camera.
- **FR-2.2:** The app shall perform automatic document corner detection, perspective de-skewing, and contrast normalization.
- **FR-2.3:** Optical Mark Recognition (OMR) shall detect checked checkboxes and bubble marks with >98% accuracy.
- **FR-2.4:** On-device OCR (Google ML Kit) shall extract handwritten numeric fields (dates, blood pressure, pulse, SpO2, glucose, delivery counts).
- **FR-2.5:** A mandatory split-screen verification screen shall display the photographed crop alongside digital inputs for staff review and correction before committing to database.

### FR-3: Manual Clinical Entry Fallback
- **FR-3.1:** Field staff can manually input any patient record or clinical station at any time.
- **FR-3.2:** Entry workflow strictly mirrors the 2-page physical Yellow Form divided into logical stations:
  1. Intake & Demographics
  2. Anamnesis (Medical/Obstetric History)
  3. Physical Examination & POP Staging
  4. Lab Tests & Vital Signs
  5. Diagnoses & Conclusion
  6. Treatment, Prescriptions & Outtake

### FR-4: Offline Storage & Automatic Synchronization
- **FR-4.1:** All patient demographic and clinical records shall be written immediately to the local encrypted SQLite database (`gynocamp_offline.db`).
- **FR-4.2:** The app shall function 100% offline without degradation of feature set.
- **FR-4.3:** A background network listener shall monitor internet connectivity. Upon re-connection, pending upstream records shall automatically sync to the central server without requiring manual staff intervention.
- **FR-4.4:** Downstream synchronization shall refresh dynamic lookups (medicines, diagnoses, camp schedules) from the server.

### FR-5: Duplicate Data Detector
- **FR-5.1:** Upon patient registration, the system automatically cross-checks the local database cache and server records against 5 parameters:
  1. 10-digit mobile phone number (Exact match)
  2. Patient First Name & Surname (Case-insensitive & phonetic tolerance)
  3. Patient Age (± 1 year tolerance)
  4. Ward Number & Municipality
  5. Relationship Name:
     - If patient age < 20 years: Cross-checks **Father's Name**
     - If patient age ≥ 20 years: Cross-checks **Husband's Name**
- **FR-5.2:** If a potential duplicate is detected, a warning modal displays the existing patient's details and last visit history, allowing staff to link records or confirm a distinct individual.

### FR-6: Clinical Data Validation Checks
- **FR-6.1:** Real-time range validation bounds shall be enforced on numeric inputs:
  - **Blood Pressure Systolic:** Hard limits [60 – 260 mmHg]; Clinical warning [90 – 160 mmHg].
  - **Blood Pressure Diastolic:** Hard limits [40 – 160 mmHg]; Clinical warning [60 – 100 mmHg].
  - **Pulse:** Hard limits [35 – 220 bpm]; Clinical warning [55 – 110 bpm].
  - **Oxygen Saturation (SpO2):** Hard limits [50 – 100%]; Warning if < 92%.
  - **Blood Glucose:** Hard limits [30 – 600 mg/dL]; Warning if < 70 or > 200 mg/dL.
- **FR-6.2:** Impossible numeric inputs (e.g. Systolic 12 mmHg or SpO2 120%) trigger immediate input rejection.

### FR-7: Secure Device Access & Activation Lifecycle
- **FR-7.1:** The app shall only operate on hardware devices whitelisted by the organization.
- **FR-7.2:** New devices require a 2-step activation security process:
  1. Field staff requests activation via OTP verification code.
  2. Super Admin receives hardware fingerprint in Web Admin Panel and explicitly grants approval.
- **FR-7.3:** Revoked or pending devices are barred from logging in or viewing cached patient records.

### FR-8: Device App Lock (PIN / Biometrics)
- **FR-8.1:** In addition to user login, an on-device App Lock (4–6 digit PIN or Biometric Fingerprint/Face Unlock) protects the session.
- **FR-8.2:** If a tablet is left unattended or backgrounded for more than 5 minutes, the app automatically locks.

### FR-9: Camp Lifecycle & Scheduling View
- **FR-9.1:** Super Admins can manage camps across states: `Draft` → `Scheduled` → `Open (Active Data Entry)` → `Closed` → `Archived`.
- **FR-9.2:** An interactive calendar view visually plots upcoming camps, venue locations, and staff assignments.

### FR-10: Dynamic Form & Medicine Customization
- **FR-10.1:** Super Admins can add, edit, reorder, or deactivate diagnosis options, medication lists, and referral hospitals in the Admin Panel without releasing a new APK or mobile build.

### FR-11: English / Nepali Bilingual Interface
- **FR-11.1:** Complete UI localization supporting both English and Nepali (Unicode).
- **FR-11.2:** Dual-calendar support converting seamlessly between Bikram Sambat (BS) and Gregorian (AD) formats.

### FR-12: Instant Reporting
- **FR-12.1:** One-tap export of Camp Summary Reports in PDF and Excel formats.
- **FR-12.2:** Reports aggregate demographic distribution, POP prevalence by stage, diagnosed pathologies, dispensed medicines, and surgical referral counts.

### FR-13: User Activity Audit Log
- **FR-13.1:** An immutable, tamper-evident audit log records every login, entry, edit, and sync operation with user ID, name, action, timestamp, device ID, and cryptographic SHA-256 hash.
