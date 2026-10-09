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

  /// Delete calls in order, so screen-level tests can assert the delete
  /// operation actually ran with the expected argument.
  final List<int> deleteByIdCalls = <int>[];
  final List<List<int>> deleteByIdsCalls = <List<int>>[];
  int deleteAllCalls = 0;

  @override
  Future<void> deleteById(int id) async => deleteByIdCalls.add(id);

  @override
  Future<void> deleteByIds(List<int> ids) async => deleteByIdsCalls.add(ids);

  @override
  Future<void> deleteAll() async => deleteAllCalls++;

  /// Every [updateLabels] call in order, as the screen passed it.
  final List<({int id, String? fieldName, String? sampleLabel})>
      updateLabelsCalls =
      <({int id, String? fieldName, String? sampleLabel})>[];

  /// When true, [updateLabels] throws after recording the call.
  bool throwOnUpdateLabels = false;

  @override
  Future<void> updateLabels(
    int id, {
    String? fieldName,
    String? sampleLabel,
  }) async {
    updateLabelsCalls
        .add((id: id, fieldName: fieldName, sampleLabel: sampleLabel));
    if (throwOnUpdateLabels) {
      throw Exception('forced updateLabels failure');
    }
  }

  @override
  Stream<List<SoilRecord>> watchFiltered({
    String? textureClass,
    String? searchTerm,
  }) =>
      Stream.value(const <SoilRecord>[]);
}
