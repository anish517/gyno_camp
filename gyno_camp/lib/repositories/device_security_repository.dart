import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/security/security_service.dart';
import '../models/device_model.dart';
import 'audit_repository.dart';

abstract class IDeviceSecurityRepository {
  Future<DeviceModel?> getDeviceByFingerprint(String fingerprint);
  Future<DeviceModel?> getDeviceById(String deviceId);
  Future<List<DeviceModel>> getAllDevices();
  Future<List<DeviceModel>> getPendingDevices();
  Future<({DeviceModel device, String plainOtp})> requestDeviceRegistration({
    required String deviceName,
    required String model,
    required String hardwareFingerprint,
    required String staffUserId,
    required String staffName,
  });
  Future<bool> verifyOtp({required String deviceId, required String enteredOtp});
  Future<bool> approveDevice({required String deviceId, required String adminUserId});
  Future<bool> revokeDevice({required String deviceId, required String adminUserId});
  Future<bool> setAppLockPin({required String deviceId, required String pin});
  Future<bool> verifyAppLockPin({required String deviceId, required String enteredPin});
}

class DeviceSecurityRepository implements IDeviceSecurityRepository {
  final DatabaseService _databaseService;
  final AuditRepository _auditRepository;
  final Uuid _uuid = const Uuid();

  DeviceSecurityRepository({
    DatabaseService? databaseService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<DeviceModel?> getDeviceByFingerprint(String fingerprint) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableDevices,
      where: 'hardware_fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DeviceModel.fromMap(maps.first);
  }

  @override
  Future<DeviceModel?> getDeviceById(String deviceId) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableDevices,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DeviceModel.fromMap(maps.first);
  }

  @override
  Future<List<DeviceModel>> getAllDevices() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableDevices,
      orderBy: 'registered_at DESC',
    );
    return maps.map((m) => DeviceModel.fromMap(m)).toList();
  }

  @override
  Future<List<DeviceModel>> getPendingDevices() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      DatabaseTables.tableDevices,
      where: 'status = ?',
      whereArgs: [AppConstants.deviceStatusPendingApproval],
      orderBy: 'registered_at ASC',
    );
    return maps.map((m) => DeviceModel.fromMap(m)).toList();
  }

  @override
  Future<({DeviceModel device, String plainOtp})> requestDeviceRegistration({
    required String deviceName,
    required String model,
    required String hardwareFingerprint,
    required String staffUserId,
    required String staffName,
  }) async {
    final db = await _databaseService.database;
    final existing = await getDeviceByFingerprint(hardwareFingerprint);

    final plainOtp = SecurityService.generateOtp();
    final otpHash = SecurityService.hashSha256(plainOtp);
    final otpExpiry = DateTime.now().add(const Duration(minutes: 10));

    DeviceModel device;
    if (existing != null) {
      device = existing.copyWith(
        deviceName: deviceName,
        model: model,
        status: DeviceActivationStatus.pendingOtp,
        registeredByUserId: staffUserId,
        registeredByName: staffName,
        otpHash: otpHash,
        otpExpiresAt: otpExpiry,
      );
      await db.update(
        DatabaseTables.tableDevices,
        device.toMap(),
        where: 'device_id = ?',
        whereArgs: [existing.deviceId],
      );
    } else {
      final deviceId = 'dev-${_uuid.v4().substring(0, 8)}';
      device = DeviceModel(
        deviceId: deviceId,
        deviceName: deviceName,
        model: model,
        hardwareFingerprint: hardwareFingerprint,
        status: DeviceActivationStatus.pendingOtp,
        registeredByUserId: staffUserId,
        registeredByName: staffName,
        otpHash: otpHash,
        otpExpiresAt: otpExpiry,
        registeredAt: DateTime.now(),
      );
      await db.insert(
        DatabaseTables.tableDevices,
        device.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await _auditRepository.logActivity(
      userId: staffUserId,
      userName: staffName,
      userRole: AppConstants.roleDataTaker,
      action: AppConstants.auditActionDeviceRegister,
      entityType: 'Device',
      entityId: device.deviceId,
      detailsJson: '{"deviceName":"$deviceName","fingerprint":"$hardwareFingerprint"}',
      deviceId: device.deviceId,
    );

    return (device: device, plainOtp: plainOtp);
  }

  @override
  Future<bool> verifyOtp({required String deviceId, required String enteredOtp}) async {
    final device = await getDeviceById(deviceId);
    if (device == null) return false;

    if (device.otpExpiresAt == null || DateTime.now().isAfter(device.otpExpiresAt!)) {
      return false; // OTP expired
    }

    final enteredHash = SecurityService.hashSha256(enteredOtp.trim());
    if (enteredHash != device.otpHash) {
      return false; // Incorrect OTP
    }

    // Move to Pending Admin Approval
    final db = await _databaseService.database;
    final updated = device.copyWith(
      status: DeviceActivationStatus.pendingApproval,
      otpHash: null,
      otpExpiresAt: null,
    );

    await db.update(
      DatabaseTables.tableDevices,
      updated.toMap(),
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    return true;
  }

  @override
  Future<bool> approveDevice({required String deviceId, required String adminUserId}) async {
    final device = await getDeviceById(deviceId);
    if (device == null) return false;

    final db = await _databaseService.database;
    final now = DateTime.now();
    final updated = device.copyWith(
      status: DeviceActivationStatus.approved,
      approvedAt: now,
      approvedByUserId: adminUserId,
    );

    await db.update(
      DatabaseTables.tableDevices,
      updated.toMap(),
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionDeviceApprove,
      entityType: 'Device',
      entityId: deviceId,
      detailsJson: '{"approvedAt":"${now.toIso8601String()}"}',
      deviceId: deviceId,
    );

    return true;
  }

  @override
  Future<bool> revokeDevice({required String deviceId, required String adminUserId}) async {
    final device = await getDeviceById(deviceId);
    if (device == null) return false;

    final db = await _databaseService.database;
    final updated = device.copyWith(
      status: DeviceActivationStatus.revoked,
    );

    await db.update(
      DatabaseTables.tableDevices,
      updated.toMap(),
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    await _auditRepository.logActivity(
      userId: adminUserId,
      userName: 'Super Admin',
      userRole: AppConstants.roleSuperAdmin,
      action: AppConstants.auditActionDeviceRevoke,
      entityType: 'Device',
      entityId: deviceId,
      detailsJson: '{"revokedAt":"${DateTime.now().toIso8601String()}"}',
      deviceId: deviceId,
    );

    return true;
  }

  @override
  Future<bool> setAppLockPin({required String deviceId, required String pin}) async {
    if (pin.length < 4 || pin.length > 6) return false;

    final device = await getDeviceById(deviceId);
    if (device == null) return false;

    final hashedPin = SecurityService.hashPin(pin);
    final db = await _databaseService.database;

    final updated = device.copyWith(pinHash: hashedPin);
    await db.update(
      DatabaseTables.tableDevices,
      updated.toMap(),
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    return true;
  }

  @override
  Future<bool> verifyAppLockPin({required String deviceId, required String enteredPin}) async {
    final device = await getDeviceById(deviceId);
    if (device == null || device.pinHash == null) return false;

    return SecurityService.verifyPin(enteredPin, device.pinHash!);
  }
}
