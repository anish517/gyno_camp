import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/session_service.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

class AuthState {
  final UserModel? currentUser;
  final bool isLoading;
  final bool isRestoringSession;
  final String? errorMessage;

  const AuthState({
    this.currentUser,
    this.isLoading = false,
    this.isRestoringSession = false,
    this.errorMessage,
  });

  bool get isAuthenticated => currentUser != null;
  UserRole? get currentRole => currentUser?.role;

  AuthState copyWith({
    UserModel? currentUser,
    bool? isLoading,
    bool? isRestoringSession,
    String? errorMessage,
    bool clearUser = false,
  }) {
    return AuthState(
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      isLoading: isLoading ?? this.isLoading,
      isRestoringSession: isRestoringSession ?? this.isRestoringSession,
      errorMessage: errorMessage,
    );
  }
}

class AuthViewModel extends StateNotifier<AuthState> {
  final IAuthRepository _authRepository;

  AuthViewModel(this._authRepository)
      : super(AuthState(
          isRestoringSession: SessionService.current?.hasActiveSession() ?? false,
          currentUser: _authRepository.currentUser,
        )) {
    _init();
  }

  void _init() {
    if (_authRepository.currentUser != null) {
      state = state.copyWith(currentUser: _authRepository.currentUser);
    } else {
      restoreSession();
    }
  }

  Future<void> restoreSession() async {
    final session = SessionService.current;
    if (session != null && session.hasActiveSession()) {
      state = state.copyWith(isRestoringSession: true);
      try {
        final userId = session.getSavedUserId();
        if (userId != null && userId.isNotEmpty) {
          final user = await _authRepository.getUserById(userId);
          if (user != null && user.isActive) {
            if (!user.isSuperAdmin && user.role != UserRole.superAdmin) {
              final validCamps = await _authRepository.getValidCampsForUser(user.assignedCampIds);
              if (validCamps.isEmpty) {
                await session.clearSession();
                await _authRepository.logout(deviceId: 'session-restore');
                state = state.copyWith(currentUser: null, isRestoringSession: false);
                return;
              }
            }
            final savedOrg = SessionService.current?.getOrganizationName();
            final effectiveUser = (savedOrg != null &&
                    savedOrg.trim().isNotEmpty &&
                    user.isSuperAdmin &&
                    (user.tenantName == 'Outreach Health Center' ||
                        user.tenantName == 'Nepal Health Outreach Network'))
                ? user.copyWith(tenantName: savedOrg)
                : user;
            _authRepository.setCurrentUser(effectiveUser);
            state = state.copyWith(currentUser: effectiveUser, isRestoringSession: false);
            return;
          } else {
            await session.clearSession();
          }
        }
      } catch (_) {
        // Fallback gracefully on read error
      }
      state = state.copyWith(isRestoringSession: false);
    }
  }

  Future<bool> login({
    required String email,
    String? password,
    required String deviceId,
    UserRole? requiredRole,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _authRepository.login(
        email: email,
        password: password,
        deviceId: deviceId,
      );
      if (!mounted) return false;
      if (user != null) {
        if (requiredRole != null && user.role != requiredRole) {
          // STRICT RBAC CHECK: Deny access if account role does not match selected station terminal
          await _authRepository.logout(deviceId: deviceId);
          if (!mounted) return false;
          state = state.copyWith(
            currentUser: null,
            isLoading: false,
            errorMessage:
                'Access Denied: Staff account "${user.name}" is designated as ${user.role.displayNameEn}. You cannot authenticate into the ${requiredRole.displayNameEn} terminal.',
          );
          return false;
        }
        // CAMP ASSIGNMENT GATE: Non-superAdmin staff must have at least one assigned camp that exists
        if (!user.isSuperAdmin && user.role != UserRole.superAdmin) {
          final validCamps = await _authRepository.getValidCampsForUser(user.assignedCampIds);
          if (!mounted) return false;
          if (validCamps.isEmpty) {
            await _authRepository.logout(deviceId: deviceId);
            if (!mounted) return false;
            state = state.copyWith(
              currentUser: null,
              isLoading: false,
              errorMessage:
                  'Access Denied: Your staff profile ("${user.name}") has no assigned camps. Please contact your Super Admin to assign you to an active camp before logging in.',
            );
            return false;
          }
        }
        await SessionService.current?.saveUserSession(
          userId: user.id,
          email: user.email,
          role: user.role.toDbString(),
        );
        if (!mounted) return true;
        state = state.copyWith(currentUser: user, isLoading: false);
        return true;

      } else {
        if (!mounted) return false;
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Invalid staff credentials or account deactivated. Please verify your email and password.',
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Login failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<bool> loginAsRole({required UserRole role, required String deviceId}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _authRepository.loginAsRole(role: role, deviceId: deviceId);
      if (!mounted) return false;
      if (user != null) {
        if (!user.isSuperAdmin && user.role != UserRole.superAdmin) {
          final validCamps = await _authRepository.getValidCampsForUser(user.assignedCampIds);
          if (!mounted) return false;
          if (validCamps.isEmpty) {
            await _authRepository.logout(deviceId: deviceId);
            if (!mounted) return false;
            state = state.copyWith(
              currentUser: null,
              isLoading: false,
              errorMessage:
                  'Access Denied: Staff profile "${user.name}" has no valid assigned camps. Please assign a camp in Admin before switching.',
            );
            return false;
          }
        }
        await SessionService.current?.saveUserSession(
          userId: user.id,
          email: user.email,
          role: user.role.toDbString(),
        );
        if (!mounted) return true;
        state = state.copyWith(currentUser: user, isLoading: false);
        return true;
      } else {
        if (!mounted) return false;
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No active profile found for role: ${role.displayNameEn}',
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Role switch failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<bool> updateProfile({
    required UserModel updatedUser,
    required String deviceId,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final saved = await _authRepository.updateUser(
        user: updatedUser,
        adminUserId: state.currentUser?.id ?? updatedUser.id,
        deviceId: deviceId,
      );
      if (!mounted) return true;
      state = state.copyWith(currentUser: saved, isLoading: false);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update profile: $e',
      );
      return false;
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  void updateCurrentUser(UserModel user) {
    state = state.copyWith(currentUser: user);
  }

  Future<void> logout({required String deviceId}) async {
    state = state.copyWith(isLoading: true);
    await _authRepository.logout(deviceId: deviceId);
    await SessionService.current?.clearSession();
    if (!mounted) return;
    state = state.copyWith(clearUser: true, isLoading: false);
  }
}

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepository(enableCentralSync: true);
});

final authStateProvider = StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthViewModel(repository);
});
