import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../feed/domain/feed_notifier.dart';
import '../data/product_register_repository.dart';

enum RegisterStatus { idle, uploadingImages, submitting, success }

class ProductRegisterState {
  const ProductRegisterState({
    this.selectedImages = const [],
    this.status = RegisterStatus.idle,
    this.compressedCount = 0,
    this.errorMessage,
    this.createdProductId,
  });

  /// 선택된 이미지 파일 목록 — 바이트는 압축 시점에만 읽음 (메모리 절약)
  final List<XFile> selectedImages;
  final RegisterStatus status;
  /// 압축 완료된 이미지 수 (실제 네트워크 업로드 수가 아님)
  final int compressedCount;
  final String? errorMessage;
  final String? createdProductId;

  bool get isBusy =>
      status == RegisterStatus.uploadingImages ||
      status == RegisterStatus.submitting;

  ProductRegisterState copyWith({
    List<XFile>? selectedImages,
    RegisterStatus? status,
    int? compressedCount,
    String? errorMessage,
    bool clearError = false,
    String? createdProductId,
  }) =>
      ProductRegisterState(
        selectedImages: selectedImages ?? this.selectedImages,
        status: status ?? this.status,
        compressedCount: compressedCount ?? this.compressedCount,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        createdProductId: createdProductId ?? this.createdProductId,
      );
}

class ProductRegisterNotifier
    extends AutoDisposeNotifier<ProductRegisterState> {
  @override
  ProductRegisterState build() => const ProductRegisterState();

  /// 이미지 추가. 10장 초과 시 10장으로 잘라 true 반환 (호출자가 경고 스낵바 표시).
  bool addImages(List<XFile> newImages) {
    final combined = [...state.selectedImages, ...newImages];
    final exceeded = combined.length > 10;
    state = state.copyWith(
      selectedImages: combined.take(10).toList(),
      clearError: true,
    );
    return exceeded;
  }

  void removeImage(int index) {
    final updated = List<XFile>.from(state.selectedImages)..removeAt(index);
    state = state.copyWith(selectedImages: updated);
  }

  Future<void> register({
    required String title,
    required int price,
    required String category,
    String? description,
  }) async {
    final neighborhoodId =
        ref.read(authNotifierProvider).valueOrNull?.user?.neighborhoodId;
    if (neighborhoodId == null) {
      state = state.copyWith(errorMessage: '동네를 먼저 설정해 주세요.');
      return;
    }

    state = state.copyWith(
      status: RegisterStatus.uploadingImages,
      compressedCount: 0,
      clearError: true,
    );

    try {
      // 1. 이미지 읽기 + 압축 (XFile → bytes → JPEG 압축)
      final compressed = <Uint8List>[];
      for (final xf in state.selectedImages) {
        final raw = await xf.readAsBytes();
        final result = await FlutterImageCompress.compressWithList(
          raw,
          minWidth: 1080,
          minHeight: 1080,
          quality: 85,
          format: CompressFormat.jpeg,
        );
        compressed.add(result);
        state = state.copyWith(compressedCount: compressed.length);
      }

      // 2. 이미지 업로드 (압축 완료 후 일괄 전송)
      final repo = ref.read(productRegisterRepositoryProvider);
      final imageUrls = compressed.isEmpty
          ? <String>[]
          : await repo.uploadImages(compressed);

      // 3. 상품 등록
      state = state.copyWith(status: RegisterStatus.submitting);
      final productId = await repo.createProduct(
        title: title,
        price: price,
        category: category,
        description: description,
        imageUrls: imageUrls,
        neighborhoodId: neighborhoodId,
      );

      // 4. 피드 갱신 → 성공 (화면 이동 전 invalidate)
      ref.invalidate(feedNotifierProvider);
      state = state.copyWith(
        status: RegisterStatus.success,
        createdProductId: productId,
      );
    } on AppError catch (e) {
      state = state.copyWith(
        status: RegisterStatus.idle,
        compressedCount: 0,
        errorMessage: e.message,
      );
    } catch (e, st) {
      debugPrint('ProductRegisterNotifier: unexpected error: $e\n$st');
      state = state.copyWith(
        status: RegisterStatus.idle,
        compressedCount: 0,
        errorMessage: '오류가 발생했습니다.',
      );
    }
  }
}

final productRegisterProvider =
    AutoDisposeNotifierProvider<ProductRegisterNotifier, ProductRegisterState>(
  ProductRegisterNotifier.new,
);
