import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';

class LocationService {
  static Future<Position> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Serviço de localização desabilitado.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permissão de localização negada');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Permissão de localização negada permanentemente');
    }

    return await Geolocator.getCurrentPosition();
  }

  static Future<String> getAddressFromPosition(Position position) async {
    List<Placemark> placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (placemarks.isEmpty) return AppStrings.addressUnavailable;
    Placemark placemark = placemarks[0];
    return '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
  }
}
