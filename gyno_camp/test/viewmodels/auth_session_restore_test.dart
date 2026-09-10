import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gyno_camp/core/services/session_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';

class MockAuthRepository implements IAuthRepository {
  UserModel? _currentUser;
  final List<UserModel> _users = [
    const UserModel(
      id: 'usr-nurse-101',
      name: 'Nurse Kamala',
      email: 'kamala@gynocamp.org',
      phone: '9841234567',
      role: UserRole.dataTaker,
      isActive: true,
    ),
  ];

  @override
  UserModel? get currentUser => _currentUser;

  @override
  void setCurrentUser(UserModel? user) {
    _currentUser = user;
  }

  @override
  Future<UserModel?> getUserById(String id) async {
    return _users.where((u) => u.id == id).firstOrNull;
  }

  @override
  Future<UserModel?> getUserByEmail(String email) async {
    return _users.where((u) => u.email == email).firstOrNull;
  }

  @override
  Future<UserModel?> login({required String email, String? password, required String deviceId}) async {
    final user = await getUserByEmail(email);
    if (user != null) {
      _currentUser = user;
    }
    return user;
  }

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async {
    final user = _users.where((u) => u.role == role).firstOrNull;
    if (user != null) {
      _currentUser = user;
    }
    return user;
  }

  @override
  Future<void> logout({required String deviceId}) async {
    _currentUser = null;
  }

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async => _users;

  @override
  Future<UserModel> createUser({required UserModel user, required String adminUserId, required String deviceId}) async => user;

  @override
  Future<UserModel> updateUser({required UserModel user, required String adminUserId, required String deviceId}) async => user;
}

class MockCampRepository implements ICampRepository {
  final List<CampModel> _camps = [
    CampModel(
      id: 'camp-101',
      campCode: 'KTM101',
      name: 'Kathmandu Free Health Camp',
      district: 'Kathmandu',
      municipality: 'Kathmandu Metropolitan City',
      ward: '01',
      venue: 'Health Post',
      startDate: DateTime.now(),
      endDate: DateTime.now().add(const Duration(days: 3)),
      status: CampStatus.open,
      createdAt: DateTime.now(),
    ),
    CampModel(
      id: 'camp-202',
      campCode: 'PKR202',
      name: 'Pokhara Rural Outreach',
      district: 'Kaski',
      municipality: 'Pokhara Lekhnath',
      ward: '05',
      venue: 'Community Hall',
      startDate: DateTime.now(),
      endDate: DateTime.now().add(const Duration(days: 3)),
      status: CampStatus.draft,
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Future<List<CampModel>> getAllCamps() async => _camps;

  @override
  Future<CampModel?> getActiveCamp() async => null; // No camp explicitly marked 'active' in DB

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async => camp;

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async => camp;

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<CampModel?> getCampById(String id) async => _camps.where((c) => c.id == id).firstOrNull;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SessionService.getInstance(prefs);
  });

  group('Session Restoration Tests', () {
    test('AuthViewModel automatically restores persisted session on startup', () async {
      final session = SessionService.current!;
      await session.saveUserSession(
        userId: 'usr-nurse-101',
        email: 'kamala@gynocamp.org',
        role: 'DATA_TAKER',
      );

      final repo = MockAuthRepository();
      final vm = AuthViewModel(repo);

      // Await session restore
      await vm.restoreSession();

      expect(vm.state.isAuthenticated, isTrue);
      expect(vm.state.currentUser?.name, 'Nurse Kamala');
      expect(repo.currentUser?.id, 'usr-nurse-101');
    });

    test('AuthViewModel login saves session and logout clears session', () async {
      final session = SessionService.current!;
      final repo = MockAuthRepository();
      final vm = AuthViewModel(repo);

      expect(session.hasActiveSession(), isFalse);

      final success = await vm.login(
        email: 'kamala@gynocamp.org',
        deviceId: 'dev-001',
      );

      expect(success, isTrue);
      expect(session.hasActiveSession(), isTrue);
      expect(session.getSavedUserId(), 'usr-nurse-101');

      await vm.logout(deviceId: 'dev-001');
      expect(session.hasActiveSession(), isFalse);
      expect(vm.state.isAuthenticated, isFalse);
    });

    test('CampViewModel restores saved active camp ID across restarts', () async {
      final session = SessionService.current!;
      await session.saveActiveCampId('camp-101');

      final campRepo = MockCampRepository();
      final campVm = CampViewModel(campRepo);

      // Await initial load
      await campVm.loadCamps();

      expect(campVm.state.activeCamp, isNotNull);
      expect(campVm.state.activeCamp?.id, 'camp-101');
      expect(campVm.state.activeCamp?.name, 'Kathmandu Free Health Camp');
    });
  });
}
