import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';

void main() {
  group('UserModel & UserRole Tests', () {
    test('UserRole.fromString correctly parses roles', () {
      expect(UserRole.fromString('SUPER_ADMIN'), UserRole.superAdmin);
      expect(UserRole.fromString('superadmin'), UserRole.superAdmin);
      expect(UserRole.fromString('DATA_TAKER'), UserRole.dataTaker);
      expect(UserRole.fromString('datataker'), UserRole.dataTaker);
      expect(UserRole.fromString('DATA_ANALYST'), UserRole.dataAnalyst);
      expect(UserRole.fromString('unknown'), UserRole.dataTaker); // Fallback
    });

    test('UserRole.toDbString produces canonical database strings', () {
      expect(UserRole.superAdmin.toDbString(), AppConstants.roleSuperAdmin);
      expect(UserRole.dataTaker.toDbString(), AppConstants.roleDataTaker);
      expect(UserRole.dataAnalyst.toDbString(), AppConstants.roleDataAnalyst);
    });

    test('UserModel role permissions match RBAC specifications', () {
      const superAdmin = UserModel(
        id: 'usr-1',
        name: 'Admin',
        email: 'admin@gynocamp.org',
        phone: '9800000000',
        role: UserRole.superAdmin,
      );

      expect(superAdmin.isSuperAdmin, isTrue);
      expect(superAdmin.canManageCamps, isTrue);
      expect(superAdmin.canApproveDevices, isTrue);
      expect(superAdmin.canCustomizeDropdowns, isTrue);
      expect(superAdmin.canEnterClinicalData, isTrue);
      expect(superAdmin.canExportReports, isTrue);

      const dataTaker = UserModel(
        id: 'usr-2',
        name: 'Nurse Sita',
        email: 'sita@gynocamp.org',
        phone: '9811111111',
        role: UserRole.dataTaker,
      );

      expect(dataTaker.isDataTaker, isTrue);
      expect(dataTaker.canEnterClinicalData, isTrue);
      expect(dataTaker.canManageCamps, isFalse);
      expect(dataTaker.canApproveDevices, isFalse);
      expect(dataTaker.canExportReports, isFalse);

      const dataAnalyst = UserModel(
        id: 'usr-3',
        name: 'Analyst Bikash',
        email: 'analyst@gynocamp.org',
        phone: '9822222222',
        role: UserRole.dataAnalyst,
      );

      expect(dataAnalyst.isDataAnalyst, isTrue);
      expect(dataAnalyst.canExportReports, isTrue);
      expect(dataAnalyst.canManageCamps, isFalse);
      expect(dataAnalyst.canEnterClinicalData, isFalse);
    });

    test('UserModel serialization and deserialization works symmetrically', () {
      final now = DateTime(2026, 9, 6, 12, 0);
      final original = UserModel(
        id: 'usr-test-1',
        name: 'Gita Thapa',
        email: 'gita@gynocamp.org',
        phone: '9841000000',
        role: UserRole.dataTaker,
        isActive: true,
        lastLoginAt: now,
        assignedCampIds: const ['camp-1', 'camp-2'],
      );

      final map = original.toMap();
      final reconstructed = UserModel.fromMap(map);

      expect(reconstructed.id, original.id);
      expect(reconstructed.name, original.name);
      expect(reconstructed.email, original.email);
      expect(reconstructed.role, original.role);
      expect(reconstructed.isActive, isTrue);
      expect(reconstructed.assignedCampIds, ['camp-1', 'camp-2']);
      expect(reconstructed.lastLoginAt, now);
    });
  });
}
