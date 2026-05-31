import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../feed/domain/feed_notifier.dart';
import '../data/models/product_detail_model.dart';
import '../data/product_management_repository.dart';
import '../domain/product_detail_provider.dart';

const _kStatusItems = <DropdownMenuItem<String>>[
  DropdownMenuItem(value: 'SALE', child: Text('판매중')),
  DropdownMenuItem(value: 'RESERVED', child: Text('예약중')),
  DropdownMenuItem(value: 'SOLD', child: Text('판매완료')),
];

class ProductEditScreen extends ConsumerStatefulWidget {
  const ProductEditScreen({super.key, required this.product});

  final ProductDetailModel product;

  @override
  ConsumerState<ProductEditScreen> createState() =>
      _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late String _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.product.title);
    _priceCtrl =
        TextEditingController(text: widget.product.price.toString());
    _descCtrl =
        TextEditingController(text: widget.product.description ?? '');
    _selectedStatus = widget.product.status;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!mounted) return;

    final price = int.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 가격을 입력해 주세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final desc = _descCtrl.text.trim();
      await ref.read(productManagementRepositoryProvider).updateProduct(
        widget.product.id,
        {
          'title': _titleCtrl.text.trim(),
          'price': price,
          'description': desc.isEmpty ? null : desc,
          'status': _selectedStatus,
        },
      );
      // 상세·피드 양쪽 갱신
      ref.invalidate(productDetailProvider(widget.product.id));
      ref.invalidate(feedNotifierProvider);
      if (!mounted) return;
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 수정'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF7043),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: '제목 *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _selectedStatus, // controlled dropdown — requires value
                    decoration: const InputDecoration(
                      labelText: '판매 상태',
                      border: OutlineInputBorder(),
                    ),
                    items: _kStatusItems,
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedStatus = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '가격 (원) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
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
            ),
      bottomNavigationBar: _isSaving
          ? null
          : BottomAppBar(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7043),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('저장하기'),
                ),
              ),
            ),
    );
  }
}
