import 'dart:convert';
import 'dart:typed_data';

/// Builds bytes in the packed-grid format `GridSiteResolver` reads, so tests
/// state the grid they mean instead of carrying an opaque blob.
///
/// This is also the **format contract Lane B must emit**: the fixture grids
/// under `test/fixtures/corpus/grids/` are produced by this builder and pinned
/// by `grid_site_resolver_test.dart`, so a build pipeline that writes a
/// different layout fails here rather than on a device.
class PackedGridBuilder {
  PackedGridBuilder({
    required this.kind,
    required this.cellMilliDegrees,
    required this.originLatMilliDegrees,
    required this.originLonMilliDegrees,
    required this.rows,
    required this.cols,
    required this.sourceId,
    required this.cells,
  }) : assert(cells.length == rows * cols, 'cells must be rows * cols');

  /// 1 for the clay-activity grid, 2 for the biome grid.
  final int kind;
  final int cellMilliDegrees;

  /// South edge of row 0 and west edge of column 0, in milli-degrees.
  final int originLatMilliDegrees;
  final int originLonMilliDegrees;

  final int rows;
  final int cols;

  /// Which source map the values came from, carried so refinement is a data
  /// change rather than a code change.
  final String sourceId;

  /// Row-major from row 0 (south). 0 means unresolved.
  final List<int> cells;

  Uint8List build() {
    final source = utf8.encode(sourceId);
    final header = ByteData(21 + source.length);
    header.setUint8(0, 0x56); // V
    header.setUint8(1, 0x53); // S
    header.setUint8(2, 0x47); // G
    header.setUint8(3, 0x31); // 1
    header.setUint8(4, 1); // format version
    header.setUint8(5, kind);
    header.setUint16(6, cellMilliDegrees);
    header.setInt32(8, originLatMilliDegrees);
    header.setInt32(12, originLonMilliDegrees);
    header.setUint16(16, rows);
    header.setUint16(18, cols);
    header.setUint8(20, source.length);
    for (var i = 0; i < source.length; i++) {
      header.setUint8(21 + i, source[i]);
    }

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...cells,
    ]);
  }
}
