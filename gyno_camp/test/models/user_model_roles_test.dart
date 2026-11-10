import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/user_model.dart';

Map<String, dynamic> _row(String role, {String id = 'usr-1', String name = 'Bishwa Poudyal', String email = 'b@example.org'}) => {
      'id': id,
      'name': name,
      'email': email,
      'phone': '',
      'role': role,
      'is_active': 1,
    };

void main() {
  group('UserModel multi-role accounts', () {
    test('a single-role record loads and saves exactly as before', () {
      final u = UserModel.fromMap(_row('DATA_TAKER'));
      expect(u.role, UserRole.dataTaker);
      expect(u.roles, {UserRole.dataTaker});
      expect(u.hasMultipleRoles, isFalse);
      expect(u.toMap()['role'], 'DATA_TAKER');
    });

    test('a role list loads all roles; the broadest one is the default workspace', () {
      final u = UserModel.fromMap(_row('DATA_ANALYST,DATA_TAKER,STAFF'));
      expect(u.roles, {UserRole.staff, UserRole.dataTaker, UserRole.dataAnalyst});
      expect(u.role, UserRole.staff);
      expect(u.hasMultipleRoles, isTrue);
      expect(u.rolesLabel, 'Staff Coordinator, Data Taker, Data Analyst');
      // Stored in a stable order, whatever order it was read in.
      expect(u.toMap()['role'], 'STAFF,DATA_TAKER,DATA_ANALYST');
    });

    test('switching workspace keeps every role, and saving keeps them too', () {
      final u = UserModel.fromMap(_row('STAFF,DATA_TAKER,DATA_ANALYST')).copyWith(role: UserRole.dataTaker);
      expect(u.role, UserRole.dataTaker);
      expect(u.isDataTaker, isTrue);
      expect(u.isStaff, isFalse); // permissions follow the active workspace
      expect(u.canEnterClinicalData, isTrue);
      expect(u.canManageCamps, isFalse);
      expect(u.roles, {UserRole.staff, UserRole.dataTaker, UserRole.dataAnalyst});
      expect(u.toMap()['role'], 'STAFF,DATA_TAKER,DATA_ANALYST');
    });

    test('setting a role the account does not hold is a plain role change', () {
      final u = UserModel.fromMap(_row('DATA_TAKER')).copyWith(role: UserRole.dataAnalyst);
      expect(u.roles, {UserRole.dataAnalyst});
      expect(u.toMap()['role'], 'DATA_ANALYST');
    });

    test('changing grantedRoles keeps the active role only while it is still granted', () {
      final u = UserModel.fromMap(_row('STAFF,DATA_TAKER')).copyWith(role: UserRole.dataTaker);
      final kept = u.copyWith(grantedRoles: {UserRole.dataTaker, UserRole.dataAnalyst});
      expect(kept.role, UserRole.dataTaker);
      final dropped = u.copyWith(grantedRoles: {UserRole.staff, UserRole.dataAnalyst});
      expect(dropped.role, UserRole.staff);
      expect(dropped.roles, {UserRole.staff, UserRole.dataAnalyst});
    });

    test('the root Super Admin is always Super Admin only', () {
      final u = UserModel.fromMap(_row('STAFF,DATA_TAKER', id: 'usr-superadmin-01'));
      expect(u.role, UserRole.superAdmin);
      expect(u.roles, {UserRole.superAdmin});
    });

    test('unknown entries in a list fall back like a single unknown role did', () {
      expect(UserRole.parseList(''), {UserRole.dataTaker});
      expect(UserRole.parseList('STAFF, nurse'), {UserRole.staff, UserRole.dataTaker});
    });
  });
}
