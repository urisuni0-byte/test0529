class ProductDetailModel {
  const ProductDetailModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.category,
    required this.imageUrls,
    required this.createdAt,
    required this.likeCount,
    required this.status,
    this.description,
    this.sellerNickname,
  });

  final String id;
  final String sellerId;
  final String title;
  final int price;
  final String category;
  final List<String> imageUrls;
  final DateTime createdAt;
  final int likeCount;
  final String status;
  final String? description;
  final String? sellerNickname;

  bool get isSold => status == 'SOLD';
  bool get isReserved => status == 'RESERVED';

  ProductDetailModel copyWithLikeCount(int newLikeCount) => ProductDetailModel(
        id: id,
        sellerId: sellerId,
        title: title,
        price: price,
        category: category,
        imageUrls: imageUrls,
        createdAt: createdAt,
        likeCount: newLikeCount,
        status: status,
        description: description,
        sellerNickname: sellerNickname,
      );

  factory ProductDetailModel.fromJson(Map<String, dynamic> json) =>
      ProductDetailModel(
        id: json['id'] as String,
        sellerId: json['seller_id'] as String,
        title: json['title'] as String,
        price: json['price'] as int,
        category: json['category'] as String,
        imageUrls: (json['image_urls'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
        likeCount: json['like_count'] as int,
        status: json['status'] as String,
        description: json['description'] as String?,
        sellerNickname: json['seller_nickname'] as String?,
      );
}
