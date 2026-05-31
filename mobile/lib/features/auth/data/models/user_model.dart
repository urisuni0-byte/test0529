class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    this.nickname,
    this.profileImageUrl,
    this.neighborhoodId,
  });

  final String id;
  final String email;
  final String role;
  final bool isActive;
  final String? nickname;
  final String? profileImageUrl;
  final int? neighborhoodId;

  bool get hasNickname => nickname != null && nickname!.isNotEmpty;
  bool get hasNeighborhood => neighborhoodId != null;

  UserModel copyWith({
    String? id,
    String? email,
    String? role,
    bool? isActive,
    String? nickname,
    String? profileImageUrl,
    int? neighborhoodId,
  }) =>
      UserModel(
        id: id ?? this.id,
        email: email ?? this.email,
        role: role ?? this.role,
        isActive: isActive ?? this.isActive,
        nickname: nickname ?? this.nickname,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        neighborhoodId: neighborhoodId ?? this.neighborhoodId,
      );

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        isActive: json['is_active'] as bool,
        nickname: json['nickname'] as String?,
        profileImageUrl: json['profile_image_url'] as String?,
        neighborhoodId: json['neighborhood_id'] as int?,
      );
}
