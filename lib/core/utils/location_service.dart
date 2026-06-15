import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';

/// Signature for the reverse-geocoding lookup. Injected so tests can supply
/// placemarks or simulate failures without the platform geocoding plugin.
typedef PlacemarkResolver = Future<List<Placemark>> Function(
  double latitude,
  double longitude,
);

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

  /// Reverse-geocodes [position] into a human-readable address.
  ///
  /// Geocoding is best-effort: the coordinates are the source of truth, so any
  /// lookup failure or empty result degrades to [AppStrings.addressUnavailable]
  /// instead of propagating, letting the caller keep the coordinates.
  static Future<String> getAddressFromPosition(
    Position position, {
    PlacemarkResolver? geocoder,
  }) async {
    final resolve = geocoder ?? placemarkFromCoordinates;

    List<Placemark> placemarks;
    try {
      placemarks = await resolve(position.latitude, position.longitude);
    } catch (_) {
      // Geocoding is an external I/O boundary; a broad catch is intentional so
      // a network or platform failure degrades to the fallback address.
      return AppStrings.addressUnavailable;
    }

    if (placemarks.isEmpty) return AppStrings.addressUnavailable;

    final address = formatPlacemarkAddress(placemarks.first);
    return address.isEmpty ? AppStrings.addressUnavailable : address;
  }

  /// Joins the meaningful parts of [placemark] into a single address line,
  /// skipping null or blank fields so absent data never leaks as "null".
  @visibleForTesting
  static String formatPlacemarkAddress(Placemark placemark) {
    return [placemark.street, placemark.locality, placemark.administrativeArea]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(', ');
  }
}
