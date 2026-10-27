import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/models/class_score.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Test double for [SoilRecordRepository]. It keeps what [create] and the
/// content updates wrote, so [getById] reads a created record back the way
/// details does after capture hands over (SPEC 0219); the list reads return
/// trivial values.
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
    final created = record.copyWith(id: createCalls.length);
    stored[created.id!] = created;
    return created;
  }

  /// Every record [create] wrote, by id, as the updates have since left it.
  final Map<int, SoilRecord> stored = <int, SoilRecord>{};

  @override
  Future<SoilRecord?> getById(int id) async => stored[id];

  /// Every [updateClassification] call's id, in order — including attempts
  /// that then throw.
  final List<int> updateClassificationCalls = <int>[];

  /// When true, [updateClassification] throws instead of writing.
  bool throwOnUpdateClassification = false;

  @override
  Future<void> updateClassification(
    int id, {
    String? textureClass,
    double? confidenceScore,
    List<ClassScore>? classDistribution,
    String? modelVersion,
    String? datasetVersion,
    ClassificationFailureCause? classificationFailure,
  }) async {
    updateClassificationCalls.add(id);
    if (throwOnUpdateClassification) {
      throw Exception('forced updateClassification failure');
    }
    final record = stored[id];
    if (record == null) return;
    stored[id] = SoilRecord(
      id: record.id,
      uuid: record.uuid,
      imagePath: record.imagePath,
      latitude: record.latitude,
      longitude: record.longitude,
      address: record.address,
      timestamp: record.timestamp,
      horizontalAccuracy: record.horizontalAccuracy,
      fieldName: record.fieldName,
      sampleLabel: record.sampleLabel,
      textureClass: textureClass,
      confidenceScore: confidenceScore,
      classDistribution: classDistribution,
      modelVersion: modelVersion,
      datasetVersion: datasetVersion,
      classificationFailure: classificationFailure,
    );
  }

  /// Every [updateLocation] call's id, in order.
  final List<int> updateLocationCalls = <int>[];

  @override
  Future<void> updateLocation(
    int id, {
    required double latitude,
    required double longitude,
    double? horizontalAccuracy,
    required String address,
  }) async {
    updateLocationCalls.add(id);
    final record = stored[id];
    if (record == null) return;
    stored[id] = record.copyWith(
      latitude: latitude,
      longitude: longitude,
      horizontalAccuracy: horizontalAccuracy,
      address: address,
    );
  }

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
