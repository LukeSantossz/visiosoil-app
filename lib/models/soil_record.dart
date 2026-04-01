import 'package:hive/hive.dart';
part 'soil_record.g.dart';

@HiveType(typeId: 0)
class SoilRecord {
  @HiveField(0)
  final String imagePath;

  @HiveField(1)
  final double latitude;

  @HiveField(2)
  final double longitude;
  
  @HiveField(3)
  final String address;

  @HiveField(4)
  final String timestamp;

  SoilRecord({
    required this.imagePath,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.timestamp,
  });
}