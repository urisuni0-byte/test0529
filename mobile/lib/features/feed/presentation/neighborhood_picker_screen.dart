import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/neighborhood_model.dart';
import '../domain/neighborhood_notifier.dart';

class NeighborhoodPickerScreen extends ConsumerWidget {
  const NeighborhoodPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(neighborhoodNotifierProvider);

    // Show save errors as SnackBar while keeping the picker body visible.
    // Initial-load errors are shown via asyncState.when(error:) below.
    ref.listen(neighborhoodNotifierProvider, (prev, next) {
      final prevError = prev?.valueOrNull?.saveError;
      final nextError = next.valueOrNull?.saveError;
      if (nextError != null && nextError != prevError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextError.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('동네 설정'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('동네 목록을 불러올 수 없습니다.\n$e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(neighborhoodNotifierProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (state) => _PickerBody(state: state),
      ),
    );
  }
}

class _PickerBody extends ConsumerWidget {
  const _PickerBody({required this.state});

  final NeighborhoodPickerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(neighborhoodNotifierProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '거래할 동네를 선택해 주세요',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),

          _DropdownField<NeighborhoodModel>(
            label: '시',
            value: state.selectedCity,
            items: state.cities,
            itemLabel: (n) => n.name,
            onChanged: (n) => notifier.selectCity(n!),
          ),
          const SizedBox(height: 16),

          _DropdownField<NeighborhoodModel>(
            label: '구',
            value: state.selectedDistrict,
            items: state.districts,
            itemLabel: (n) => n.name,
            enabled: state.selectedCity != null,
            onChanged: (n) => notifier.selectDistrict(n!),
          ),
          const SizedBox(height: 16),

          _DropdownField<NeighborhoodModel>(
            label: '동',
            value: state.selectedDong,
            items: state.dongs,
            itemLabel: (n) => n.name,
            enabled: state.selectedDistrict != null,
            onChanged: (n) => notifier.selectDong(n!),
          ),
          const Spacer(),

          ElevatedButton(
            onPressed: state.canSave
                ? () async {
                    await notifier.saveNeighborhood();
                    // Only pop if the save succeeded (no saveError set).
                    if (context.mounted &&
                        ref
                                .read(neighborhoodNotifierProvider)
                                .valueOrNull
                                ?.saveError ==
                            null) {
                      context.go('/feed');
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7043),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: state.isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('동네 설정 완료', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // ValueKey forces recreation when value changes so that the selected
    // display reflects external state resets (e.g. district → null after city change).
    return DropdownButtonFormField<T>(
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        enabled: enabled,
        fillColor: enabled ? null : Colors.grey.shade100,
        filled: !enabled,
      ),
      items: items
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel(item)),
              ))
          .toList(),
      onChanged: enabled ? onChanged : null,
      hint: Text('$label 선택'),
    );
  }
}
