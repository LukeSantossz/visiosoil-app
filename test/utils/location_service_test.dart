import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/utils/location_service.dart';

void main() {
  Position fakePosition() => Position(
        latitude: -12.0,
        longitude: -55.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  group('LocationService.formatPlacemarkAddress', () {
    test('joins present fields with a comma', () {
      final placemark = Placemark(
        street: 'Rua das Flores',
        locality: 'Sorriso',
        administrativeArea: 'MT',
      );
      expect(
        LocationService.formatPlacemarkAddress(placemark),
        'Rua das Flores, Sorriso, MT',
      );
    });

    test('omits null and empty fields', () {
      final placemark = Placemark(
        street: 'Rua das Flores',
        locality: null,
        administrativeArea: '',
      );
      expect(
        LocationService.formatPlacemarkAddress(placemark),
        'Rua das Flores',
      );
    });

    test('returns empty when all fields are absent', () {
      final placemark = Placemark(
        street: null,
        locality: '',
        administrativeArea: null,
      );
      expect(LocationService.formatPlacemarkAddress(placemark), '');
    });
  });

  group('LocationService.getAddressFromPosition', () {
    test('returns the fallback when the geocoder returns an empty list',
        () async {
      final address = await LocationService.getAddressFromPosition(
        fakePosition(),
        geocoder: (_, __) async => <Placemark>[],
      );
      expect(address, AppStrings.addressUnavailable);
    });

    test('returns the fallback when the geocoder throws', () async {
      final address = await LocationService.getAddressFromPosition(
        fakePosition(),
        geocoder: (_, __) async => throw Exception('geocoding failed'),
      );
      expect(address, AppStrings.addressUnavailable);
    });

    test('returns the fallback when the placemark has no usable fields',
        () async {
      final address = await LocationService.getAddressFromPosition(
        fakePosition(),
        geocoder: (_, __) async => [Placemark()],
      );
      expect(address, AppStrings.addressUnavailable);
    });

    test('returns the formatted address for a valid placemark', () async {
      final address = await LocationService.getAddressFromPosition(
        fakePosition(),
        geocoder: (_, __) async => [
          Placemark(
            street: 'Rua das Flores',
            locality: 'Sorriso',
            administrativeArea: 'MT',
          ),
        ],
      );
      expect(address, 'Rua das Flores, Sorriso, MT');
    });
  });
}
