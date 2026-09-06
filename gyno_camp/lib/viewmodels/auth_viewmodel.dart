import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

class AuthState {
  final UserModel? currentUser;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.currentUser,
    this.isLoading = false,
    this.errorMessage,
  });

  bool get isAuthenticated => currentUser != null;
  UserRole? get currentRole => currentUser?.role;

  AuthState copyWith({
    UserModel? currentUser,
    bool? isLoading,
    String? errorMessage,
    bool clearUser = false,
  }) {
    return AuthState(
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthViewModel extends StateNotifier<AuthState> {
  final IAuthRepository _authRepository;

  AuthViewModel(this._authRepository) : super(const AuthState()) {
    _init();
  }

  void _init() {
    if (_authRepository.currentUser != null) {
      state = state.copyWith(currentUser: _authRepository.currentUser);
    }
  }

  Future<bool> login({required String email, required String deviceId}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _authRepository.login(email: email, deviceId: deviceId);
      if (user != null) {
        state = state.copyWith(currentUser: user, isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'User account not found or deactivated.',
        );
        return false;
      }
    } catch (e) {
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
      if (user != null) {
        state = state.copyWith(currentUser: user, isLoading: false);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No active profile found for role: ${role.displayNameEn}',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Role switch failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> logout({required String deviceId}) async {
    state = state.copyWith(isLoading: true);
    await _authRepository.logout(deviceId: deviceId);
    state = state.copyWith(clearUser: true, isLoading: false);
  }
}

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthViewModel(repository);
});
