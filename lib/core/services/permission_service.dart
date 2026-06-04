import 'package:permission_handler/permission_handler.dart' as ph;

/// Status de permissão para uso na UI.
enum AppPermissionStatus {
  /// Permissao concedida.
  granted,

  /// Permissao negada (pode ser solicitada novamente).
  denied,

  /// Permissao negada permanentemente (requer configuracoes do sistema).
  permanentlyDenied,

  /// Permissao restrita pelo sistema (iOS parental controls, MDM).
  /// Nao pode ser alterada pelo usuario.
  restricted,
}

/// Servico para gerenciar permissoes do app.
///
/// Encapsula verificacao, solicitacao e redirecionamento para configuracoes
/// do sistema. Usa o pacote `permission_handler` internamente.
class PermissionService {
  const PermissionService._();

  /// Verifica o status atual da permissao de camera.
  static Future<AppPermissionStatus> checkCamera() async {
    return _toStatus(await ph.Permission.camera.status);
  }

  /// Solicita permissao de camera.
  ///
  /// Retorna o status apos a solicitacao.
  static Future<AppPermissionStatus> requestCamera() async {
    final status = await ph.Permission.camera.request();
    return _toStatus(status);
  }

  /// Verifica o status atual da permissao de localizacao.
  static Future<AppPermissionStatus> checkLocation() async {
    return _toStatus(await ph.Permission.locationWhenInUse.status);
  }

  /// Solicita permissao de localizacao.
  ///
  /// Retorna o status apos a solicitacao.
  static Future<AppPermissionStatus> requestLocation() async {
    final status = await ph.Permission.locationWhenInUse.request();
    return _toStatus(status);
  }

  /// Abre as configuracoes do app no sistema.
  ///
  /// Use quando a permissao foi negada permanentemente e o usuario
  /// precisa habilita-la manualmente.
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
