// formatPrice / timeAgo는 core/utils/formatting.dart로 이동.
// 기존 import 호환을 위해 re-export 유지.
export 'package:mobile/core/utils/formatting.dart';

class ProductModel {
  const ProductModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.createdAt,
    required this.likeCount,
    required this.status,
    this.thumbnailUrl,
  });

  final String id;
  final String sellerId;
  final String title;
  final int price;
  final DateTime createdAt;
  final int likeCount;
  final String status;
  final String? thumbnailUrl;

  bool get isReserved => status == 'RESERVED';

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id'] as String,
        sellerId: json['seller_id'] as String,
        title: json['title'] as String,
        price: json['price'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        likeCount: json['like_count'] as int,
        status: json['status'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
}
