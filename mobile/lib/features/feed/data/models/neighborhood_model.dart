class NeighborhoodModel {
  const NeighborhoodModel({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
  });

  final int id;
  final String name;
  final String level;
  final int? parentId;

  bool get isCity => level == 'city';
  bool get isDistrict => level == 'district';
  bool get isDong => level == 'dong';

  factory NeighborhoodModel.fromJson(Map<String, dynamic> json) =>
      NeighborhoodModel(
        id: json['id'] as int,
        name: json['name'] as String,
        level: json['level'] as String,
        parentId: json['parent_id'] as int?,
      );
}
