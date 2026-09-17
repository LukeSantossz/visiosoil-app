import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';
import 'package:visiosoil_app/models/site_key.dart';

/// Which key part a grid carries. Stored in the artifact so a grid cannot be
/// read as the other one by accident.
abstract final class GridKind {
  static const int clayActivity = 1;
  static const int biome = 2;
}

/// A lattice of one byte per cell over a bounding box, read by index.
///
/// The format is deliberately trivial: lookup is an array index from latitude
/// and longitude — constant time, no parsing after load, no dependency
/// (`docs/architecture/research-agent.md` §5.2). Each grid records its
/// resolution and its source map, so refining either is a data change rather
/// than a code change.
///
/// Layout, big-endian:
///
/// | Offset | Size  | Field |
/// |--------|-------|-------|
/// | 0      | 4     | magic `VSG1` |
/// | 4      | 1     | format version, currently 1 |
/// | 5      | 1     | [GridKind] |
/// | 6      | 2     | cell size in milli-degrees |
/// | 8      | 4     | south edge of row 0, milli-degrees |
/// | 12     | 4     | west edge of column 0, milli-degrees |
/// | 16     | 2     | rows |
/// | 18     | 2     | columns |
/// | 20     | 1     | source id length |
/// | 21     | n     | source id, UTF-8 |
/// | 21+n   | r × c | payload, row-major from row 0 (south) |
///
/// A payload byte of 0 means unresolved. Any other value is a one-based index
/// into the enumeration the grid's kind names; a value the enumeration does not
/// have also reads as unresolved, so a grid written by a newer build degrades
/// instead of throwing on a device.
class PackedGrid {
  const PackedGrid._({
    required this.kind,
    required this.cellMilliDegrees,
    required this.originLatMilliDegrees,
    required this.originLonMilliDegrees,
    required this.rows,
    required this.cols,
    required this.sourceId,
    required this._payload,
  });

  static const int _formatVersion = 1;
  static const int _headerLength = 21;

  final int kind;
  final int cellMilliDegrees;
  final int originLatMilliDegrees;
  final int originLonMilliDegrees;
  final int rows;
  final int cols;

  /// Which source map the values came from.
  final String sourceId;

  final Uint8List _payload;

  /// Reads [bytes], refusing anything it cannot read **by name**.
  ///
  /// A grid is a build product, so a malformed one is a build defect and saying
  /// which part is malformed is what makes it fixable. Guessing at a header the
  /// reader does not recognise would put wrong guidance on a screen.
  factory PackedGrid.parse(Uint8List bytes) {
    if (bytes.length < _headerLength) {
      throw const FormatException('packed grid is shorter than its header');
    }
    final data = ByteData.sublistView(bytes);
    if (bytes[0] != 0x56 || bytes[1] != 0x53 || bytes[2] != 0x47 ||
        bytes[3] != 0x31) {
      throw const FormatException('packed grid has the wrong magic; '
          'expected VSG1');
    }
    final version = data.getUint8(4);
    if (version != _formatVersion) {
      throw FormatException(
        'packed grid format version $version is not supported; '
        'this build reads version $_formatVersion',
      );
    }
    final sourceLength = data.getUint8(20);
    final payloadStart = _headerLength + sourceLength;
    final rows = data.getUint16(16);
    final cols = data.getUint16(18);
    final expected = rows * cols;
    if (bytes.length - payloadStart != expected) {
      throw FormatException(
        'packed grid payload is ${bytes.length - payloadStart} bytes, '
        'but its header declares $rows x $cols = $expected',
      );
    }
    return PackedGrid._(
      kind: data.getUint8(5),
      cellMilliDegrees: data.getUint16(6),
      originLatMilliDegrees: data.getInt32(8),
      originLonMilliDegrees: data.getInt32(12),
      rows: rows,
      cols: cols,
      sourceId: utf8.decode(bytes.sublist(_headerLength, payloadStart)),
      payload: Uint8List.sublistView(bytes, payloadStart),
    );
  }

  /// The raw cell value at a coordinate, or 0 when it falls outside the lattice.
  int valueAt({required double latitude, required double longitude}) {
    final row =
        ((latitude * 1000 - originLatMilliDegrees) / cellMilliDegrees).floor();
    final col =
        ((longitude * 1000 - originLonMilliDegrees) / cellMilliDegrees).floor();
    if (row < 0 || row >= rows || col < 0 || col >= cols) return 0;
    return _payload[row * cols + col];
  }
}

/// Resolves a [SiteKey] from two packed grids and the address the app already
/// reverse-geocodes.
///
/// Grids answer for clay activity and biome; the federative unit comes from the
/// address, because the app derives it already and a third grid would encode
/// borders that a geocoder knows better.
class GridSiteResolver implements SiteResolver {
  /// Both grids are optional because they ship later than this resolver does:
  /// they are a build product of the corpus pipeline, and the federative unit
  /// resolves from the address without them. A null grid resolves its key part
  /// to null, which §5.2 defines as valid and not fatal.
  const GridSiteResolver({
    PackedGrid? clayActivityGrid,
    PackedGrid? biomeGrid,
  })  : _clay = clayActivityGrid,
        _biome = biomeGrid;

  final PackedGrid? _clay;
  final PackedGrid? _biome;

  @override
  Future<SiteKey> resolve({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final unit = unitFromAddress(address);
    if (latitude == null || longitude == null) {
      return unit == null ? const SiteKey.unresolved() : SiteKey(unit: unit);
    }
    return SiteKey(
      clayActivity: _atIndex(
        ClayActivity.values,
        _clay?.valueAt(latitude: latitude, longitude: longitude) ?? 0,
      ),
      biome: _atIndex(
        Biome.values,
        _biome?.valueAt(latitude: latitude, longitude: longitude) ?? 0,
      ),
      unit: unit,
    );
  }

  /// One-based [value] into [members], or null for 0 and for anything the
  /// enumeration does not have.
  static T? _atIndex<T>(List<T> members, int value) =>
      value >= 1 && value <= members.length ? members[value - 1] : null;

  /// The ISO 3166-2:BR code named by [address], or null.
  ///
  /// The address the app stores is `street, locality, administrativeArea`
  /// (`LocationService.formatPlacemarkAddress`), and the geocoder writes the
  /// administrative area as either the state's name or its two-letter code. Both
  /// are accepted; accents and case are not significant, because which form a
  /// platform returns is not something this app controls.
  @visibleForTesting
  static String? unitFromAddress(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final last = address.split(',').last;
    final normalized = _normalize(last);
    if (normalized.isEmpty) return null;
    final byName = _unitByNormalizedName[normalized];
    if (byName != null) return byName;
    final asCode = 'BR-${normalized.toUpperCase()}';
    return federativeUnitCodes.contains(asCode) ? asCode : null;
  }

  /// Every federative unit the corpus's institutional layer is keyed by.
  static Iterable<String> get federativeUnitCodes =>
      _unitByNormalizedName.values;

  /// Lower-case, unaccented and space-collapsed, so `SAO PAULO`, `São Paulo`
  /// and `sao  paulo` are one key.
  static String _normalize(String value) {
    final lowered = value.trim().toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      buffer.write(_unaccented[String.fromCharCode(rune)] ??
          String.fromCharCode(rune));
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Map<String, String> _unaccented = {
        'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
        'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
        'í': 'i', 'î': 'i', 'ì': 'i', 'ï': 'i',
        'ó': 'o', 'ô': 'o', 'õ': 'o', 'ò': 'o', 'ö': 'o',
        'ú': 'u', 'û': 'u', 'ù': 'u', 'ü': 'u',
        'ç': 'c', 'ñ': 'n',
      };

  /// The 27 federative units, keyed by their normalized names. Insertion order
  /// is alphabetical by code so a reader can check the list against ISO
  /// 3166-2:BR without sorting it first.
  static const Map<String, String> _unitByNormalizedName = {
    'acre': 'BR-AC',
    'alagoas': 'BR-AL',
    'amazonas': 'BR-AM',
    'amapa': 'BR-AP',
    'bahia': 'BR-BA',
    'ceara': 'BR-CE',
    'distrito federal': 'BR-DF',
    'espirito santo': 'BR-ES',
    'goias': 'BR-GO',
    'maranhao': 'BR-MA',
    'minas gerais': 'BR-MG',
    'mato grosso do sul': 'BR-MS',
    'mato grosso': 'BR-MT',
    'para': 'BR-PA',
    'paraiba': 'BR-PB',
    'pernambuco': 'BR-PE',
    'piaui': 'BR-PI',
    'parana': 'BR-PR',
    'rio de janeiro': 'BR-RJ',
    'rio grande do norte': 'BR-RN',
    'rondonia': 'BR-RO',
    'roraima': 'BR-RR',
    'rio grande do sul': 'BR-RS',
    'santa catarina': 'BR-SC',
    'sergipe': 'BR-SE',
    'sao paulo': 'BR-SP',
    'tocantins': 'BR-TO',
  };
}
