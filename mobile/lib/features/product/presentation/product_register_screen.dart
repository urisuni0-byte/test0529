import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/product_register_notifier.dart';

// 매 build마다 재할당하지 않도록 const 상수로 선언 (Fix #10)
const _kCategoryItems = <DropdownMenuItem<String>>[
  DropdownMenuItem(value: '전자기기', child: Text('전자기기')),
  DropdownMenuItem(value: '의류', child: Text('의류')),
  DropdownMenuItem(value: '가구', child: Text('가구')),
  DropdownMenuItem(value: '도서', child: Text('도서')),
  DropdownMenuItem(value: '스포츠', child: Text('스포츠')),
  DropdownMenuItem(value: '뷰티', child: Text('뷰티')),
  DropdownMenuItem(value: '식품', child: Text('식품')),
  DropdownMenuItem(value: '기타', child: Text('기타')),
];

class ProductRegisterScreen extends ConsumerStatefulWidget {
  const ProductRegisterScreen({super.key});

  @override
  ConsumerState<ProductRegisterScreen> createState() =>
      _ProductRegisterScreenState();
}

class _ProductRegisterScreenState
    extends ConsumerState<ProductRegisterScreen> {
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedCategory;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_updateCanSubmit);
    _priceCtrl.addListener(_updateCanSubmit);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _updateCanSubmit() {
    final next = _titleCtrl.text.trim().isNotEmpty &&
        _priceCtrl.text.trim().isNotEmpty &&
        _selectedCategory != null;
    if (next != _canSubmit) setState(() => _canSubmit = next);
  }

  Future<void> _pickImages() async {
    // 현재 선택된 수를 기준으로 OS 갤러리 한도 설정 (Fix #2)
    final currentCount =
        ref.read(productRegisterProvider).selectedImages.length;
    final remaining = 10 - currentCount;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(limit: remaining);

    // 비동기 갭 이후 위젯 언마운트 체크 (Fix #3)
    if (!mounted) return;
    if (picked.isEmpty) return;

    // XFile을 그대로 전달 — readAsBytes()는 압축 시점에만 실행 (Fix #4)
    final exceeded =
        ref.read(productRegisterProvider.notifier).addImages(picked);
    if (exceeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 10장까지 선택 가능합니다.')),
      );
    }
  }

  Future<void> _submit() async {
    // mounted 체크 — 동기 경로이지만 방어적으로 추가 (Fix #8)
    if (!mounted) return;
    final price = int.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 가격을 입력해 주세요.')),
      );
      return;
    }
    // 설명 trim 한 번만 수행 (Fix — 더블트림 제거)
    final desc = _descCtrl.text.trim();
    await ref.read(productRegisterProvider.notifier).register(
          title: _titleCtrl.text.trim(),
          price: price,
          category: _selectedCategory!,
          description: desc.isEmpty ? null : desc,
        );
    // 화면 이동은 ref.listen에서 처리 (mounted 체크 포함)
  }

  @override
  Widget build(BuildContext context) {
    final registerState = ref.watch(productRegisterProvider);

    // 성공 → 상품 상세(또는 피드) 이동 / 에러 → 스낵바 (Fix #9)
    ref.listen(productRegisterProvider, (prev, next) {
      if (next.status == RegisterStatus.success && context.mounted) {
        final productId = next.createdProductId;
        if (productId != null) {
          context.go('/product/$productId');
        } else {
          context.go('/feed');
        }
        return;
      }
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 등록'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: registerState.isBusy
          ? _ProgressBody(state: registerState)
          : _FormBody(
              titleCtrl: _titleCtrl,
              priceCtrl: _priceCtrl,
              descCtrl: _descCtrl,
              selectedCategory: _selectedCategory,
              onCategoryChanged: (v) {
                setState(() => _selectedCategory = v);
                _updateCanSubmit();
              },
              onPickImages: _pickImages,
              images: registerState.selectedImages,
              onRemoveImage: (i) =>
                  ref.read(productRegisterProvider.notifier).removeImage(i),
            ),
      bottomNavigationBar: registerState.isBusy
          ? null
          : BottomAppBar(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7043),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('등록하기'),
                ),
              ),
            ),
    );
  }
}

// ─── 진행 중 화면 ─────────────────────────────────────────────────────────────

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.state});

  final ProductRegisterState state;

  @override
  Widget build(BuildContext context) {
    // 압축 vs 업로드 단계를 compressedCount로 구분 (Fix #6)
    final String message;
    if (state.status == RegisterStatus.submitting) {
      message = '상품 등록 중...';
    } else if (state.compressedCount < state.selectedImages.length) {
      message =
          '이미지 압축 중 (${state.compressedCount}/${state.selectedImages.length})';
    } else {
      message = '이미지 업로드 중...';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFFFF7043)),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

// ─── 폼 바디 ──────────────────────────────────────────────────────────────────

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.titleCtrl,
    required this.priceCtrl,
    required this.descCtrl,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onPickImages,
    required this.images,
    required this.onRemoveImage,
  });

  final TextEditingController titleCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController descCtrl;
  final String? selectedCategory;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onPickImages;
  final List<XFile> images;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImagePickerRow(
            images: images,
            onPick: onPickImages,
            onRemove: onRemoveImage,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: titleCtrl,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '제목 *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: selectedCategory, // controlled dropdown — value required
            decoration: const InputDecoration(
              labelText: '카테고리 *',
              border: OutlineInputBorder(),
            ),
            items: _kCategoryItems, // Fix #10: const 리스트 재사용
            onChanged: onCategoryChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '가격 (원) *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: '설명 (선택)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─── 이미지 선택 행 ───────────────────────────────────────────────────────────

class _ImagePickerRow extends StatelessWidget {
  const _ImagePickerRow({
    required this.images,
    required this.onPick,
    required this.onRemove,
  });

  final List<XFile> images;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 사진 추가 버튼 (10장 미만일 때만 표시)
          if (images.length < 10)
            GestureDetector(
              onTap: onPick,
              child: Container(
                width: 100,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: Colors.grey,
                    ),
                    Text(
                      '${images.length}/10',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 선택된 이미지 미리보기 — FileImage로 표시 (Fix #4: 메모리에 bytes 보관 안 함)
          ...images.asMap().entries.map(
                (entry) => Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(File(entry.value.path)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => onRemove(entry.key),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black54,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
