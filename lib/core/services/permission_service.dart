import 'package:permission_handler/permission_handler.dart' as ph;

/// Permission status for use in the UI.
enum AppPermissionStatus {
  /// Permission granted.
  granted,

  /// Permission denied (can be requested again).
  denied,

  /// Permission permanently denied (requires system settings).
  permanentlyDenied,

  /// Permission restricted by the system (iOS parental controls, MDM).
  /// Cannot be changed by the user.
  restricted,
}

/// Service for managing app permissions.
///
/// Encapsulates checking, requesting, and redirecting to system
/// settings. Uses the `permission_handler` package internally.
class PermissionService {
  const PermissionService._();

  /// Checks the current camera permission status.
  static Future<AppPermissionStatus> checkCamera() async {
    return _toStatus(await ph.Permission.camera.status);
  }

  /// Requests camera permission.
  ///
  /// Returns the status after the request.
  static Future<AppPermissionStatus> requestCamera() async {
    final status = await ph.Permission.camera.request();
    return _toStatus(status);
  }

  /// Checks the current location permission status.
  static Future<AppPermissionStatus> checkLocation() async {
    return _toStatus(await ph.Permission.locationWhenInUse.status);
  }

  /// Requests location permission.
  ///
  /// Returns the status after the request.
  static Future<AppPermissionStatus> requestLocation() async {
    final status = await ph.Permission.locationWhenInUse.request();
    return _toStatus(status);
  }

  /// Opens the app settings in the system.
  ///
  /// Use when the permission was permanently denied and the user
  /// needs to enable it manually.
  static Future<bool> openSettings() async {
    return await ph.openAppSettings();
  }

  static AppPermissionStatus _toStatus(ph.PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return AppPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied) {
      return AppPermissionStatus.permanentlyDenied;
    }
    if (status.isRestricted) {
      return AppPermissionStatus.restricted;
    }
    return AppPermissionStatus.denied;
  }
}
