import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Test double for [SoilRecordRepository]. The capture-screen tests only
/// exercise `create`; the other methods return trivial values.
class FakeSoilRecordRepository implements SoilRecordRepository {
  /// When true, [create] throws to simulate a repository write failure.
  bool throwOnCreate = false;

  /// Every [create] invocation, in call order — including attempts that then
  /// throw (the record is recorded before the throw).
  final List<SoilRecord> createCalls = <SoilRecord>[];

  @override
  Future<SoilRecord> create(SoilRecord record) async {
    createCalls.add(record);
    if (throwOnCreate) {
      throw Exception('forced create failure');
    }
    return record.copyWith(id: createCalls.length);
  }

  @override
  Future<SoilRecord?> getById(int id) async => null;

  @override
  Stream<List<SoilRecord>> watchAll() => Stream.value(const <SoilRecord>[]);

  @override
  Future<List<SoilRecord>> getAll() async => const <SoilRecord>[];

  @override
  Future<SoilRecord?> getLatest() async => null;

  @override
  Future<int> count() async => createCalls.length;

  @override
  Future<void> deleteById(int id) async {}

  @override
  Future<void> deleteByIds(List<int> ids) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Stream<List<SoilRecord>> watchFiltered({
    String? textureClass,
    String? searchTerm,
  }) =>
      Stream.value(const <SoilRecord>[]);

  @override
  Future<List<String>> getDistinctTextureClasses() async => const <String>[];
}
