import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../services/session_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';

/// Authoritative single source of truth for the organization/tenant name
/// across Super Admin, Data Taker, Data Analyst, and Clinical printouts.
final effectiveOrganizationProvider = Provider<String>((ref) {
  final authState = ref.watch(authStateProvider);
  final campState = ref.watch(campStateProvider);

  // 1. Check explicitly saved SaaS organization name from SessionService
  final savedOrg = SessionService.current?.getOrganizationName();
  if (savedOrg != null &&
      savedOrg.trim().isNotEmpty &&
      !AppConstants.isLegacyDefaultOrganization(savedOrg)) {
    return savedOrg.trim();
  }

  // 2. Check active camp organization name (if customized by camp creation)
  final campOrg = campState.activeCamp?.organizationName;
  if (campOrg != null &&
      campOrg.trim().isNotEmpty &&
      !AppConstants.isLegacyDefaultOrganization(campOrg)) {
    return campOrg.trim();
  }

  // 3. Check logged-in user tenant name
  final userTenant = authState.currentUser?.tenantName;
  if (userTenant != null &&
      userTenant.trim().isNotEmpty &&
      !AppConstants.isLegacyDefaultOrganization(userTenant)) {
    return userTenant.trim();
  }

  // 4. Fallback: if savedOrg was explicitly set even if matching legacy, prefer it
  if (savedOrg != null && savedOrg.trim().isNotEmpty) {
    return savedOrg.trim();
  }

  // 5. Final fallback to user tenant, camp org, or default organization constant
  if (userTenant != null && userTenant.trim().isNotEmpty) {
    return userTenant.trim();
  }
  if (campOrg != null && campOrg.trim().isNotEmpty) {
    return campOrg.trim();
  }

  return AppConstants.defaultOrganizationName;
});
