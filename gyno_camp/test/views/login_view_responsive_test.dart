import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/views/auth/login_view.dart';

class _FakeAuthRepo implements IAuthRepository {
  UserModel? _currentUser;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  void setCurrentUser(UserModel? user) => _currentUser = user;

  @override
  Future<UserModel?> getUserByEmail(String email) async => null;

  @override
  Future<UserModel?> getUserById(String id) async => null;

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async => [];

  @override
  Future<UserModel> createUser({required UserModel user, required String adminUserId, required String deviceId}) async => user;

  @override
  Future<UserModel> updateUser({required UserModel user, required String adminUserId, required String deviceId}) async => user;

  @override
  Future<void> deleteUser({required String userId, required String adminUserId, required String deviceId}) async {}

  @override
  Future<UserModel?> login({required String email, String? password, required String deviceId}) async {
    if (email == 'admin@gynocamp.org' && password == 'admin123') {
      _currentUser = const UserModel(
        id: 'usr-admin-01',
        name: 'Dr. Aarav Sharma',
        email: 'admin@gynocamp.org',
        phone: '9851000001',
        role: UserRole.superAdmin,
        isActive: true,
      );
      return _currentUser;
    }
    return null;
  }

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async => null;

  @override
  Future<void> logout({required String deviceId}) async {
    _currentUser = null;
  }

  @override
  Future<List<String>> getValidCampsForUser(List<String> assignedCampIds) async => assignedCampIds;
}

void main() {
  group('LoginView Responsive & Interaction Tests', () {
    testWidgets('Renders cleanly on mobile portrait viewport (375x667) without overflow', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authRepo = _FakeAuthRepo();
      final authVm = AuthViewModel(authRepo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authVm),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Elements render cleanly
      expect(find.text('Staff Sign-In'), findsOneWidget);
      expect(find.text('Auto-Detect Role'), findsOneWidget);
      expect(find.text('Sign In to GynoCamp'), findsOneWidget);

      // Verify no quick fill testing credentials leak into UI
      expect(find.text('Admin (Dr. Aarav)'), findsNothing);
      expect(find.text('Quick Profiles (Testing):'), findsNothing);

      // Enter staff credentials manually
      await tester.enterText(find.byType(TextField).at(0), 'nurse@gynocamp.org');
      await tester.enterText(find.byType(TextField).at(1), 'securePass123');
      await tester.pump();

      expect(find.text('nurse@gynocamp.org'), findsOneWidget);
      expect(find.text('securePass123'), findsOneWidget);
    });

    testWidgets('Renders dual-pane layout on desktop viewport (1440x900) without overflow', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authRepo = _FakeAuthRepo();
      final authVm = AuthViewModel(authRepo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authVm),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Left pane features are visible
      expect(find.text('100% Offline-First Field Operation'), findsOneWidget);
      expect(find.text('Role-Based Access Control (RBAC)'), findsOneWidget);
      expect(find.text('AES-256 Ledger & MoHP Compliance'), findsOneWidget);

      // Right pane sign-in card is visible
      expect(find.text('Staff Sign-In'), findsOneWidget);
      expect(find.text('Sign In to GynoCamp'), findsOneWidget);

      // Password visibility toggle works
      final toggleButton = find.byIcon(Icons.visibility_off_outlined);
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('Validates empty fields with floating SnackBar and clears error on input', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authRepo = _FakeAuthRepo();
      final authVm = AuthViewModel(authRepo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => authVm),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(ElevatedButton, 'Sign In to GynoCamp');
      await tester.ensureVisible(submitBtn);

      // Tap Sign In with empty fields -> shows email snackbar
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Please enter your staff email, username, or mobile number.'), findsOneWidget);

      // Enter email
      final emailInput = find.byType(TextField).at(0);
      await tester.enterText(emailInput, 'test@example.com');
      await tester.pump();

      // Tap Sign In with empty password -> shows password snackbar
      await tester.tap(submitBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Please enter your password or station PIN.'), findsOneWidget);
    });
  });
}
