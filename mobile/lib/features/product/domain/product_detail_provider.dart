import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/product_detail_model.dart';
import '../data/product_detail_repository.dart';

/// 단순 조회 + ID 파라미터 → FutureProvider.autoDispose.family 패턴
final productDetailProvider =
    FutureProvider.autoDispose.family<ProductDetailModel, String>(
  (ref, productId) async {
    return ref.read(productDetailRepositoryProvider).getProduct(productId);
  },
);
