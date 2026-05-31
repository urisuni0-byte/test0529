import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../features/auth/domain/auth_notifier.dart';
import '../data/models/neighborhood_model.dart';
import '../data/neighborhood_repository.dart';

class NeighborhoodPickerState {
  const NeighborhoodPickerState({
    required this.all,
    this.selectedCity,
    this.selectedDistrict,
    this.selectedDong,
    this.isSaving = false,
    this.saveError,
  });

  final List<NeighborhoodModel> all;
  final NeighborhoodModel? selectedCity;
  final NeighborhoodModel? selectedDistrict;
  final NeighborhoodModel? selectedDong;
  final bool isSaving;

  /// Non-null when the last saveNeighborhood() call failed.
  /// Using a dedicated field (not AsyncError) keeps picker selections intact.
  final AppError? saveError;

  List<NeighborhoodModel> get cities =>
      all.where((n) => n.isCity).toList();

  List<NeighborhoodModel> get districts => selectedCity == null
      ? []
      : all
          .where((n) => n.isDistrict && n.parentId == selectedCity!.id)
          .toList();

  List<NeighborhoodModel> get dongs => selectedDistrict == null
      ? []
      : all
          .where((n) => n.isDong && n.parentId == selectedDistrict!.id)
          .toList();

  bool get canSave => selectedDong != null && !isSaving;

  NeighborhoodPickerState copyWith({
    List<NeighborhoodModel>? all,
    NeighborhoodModel? selectedCity,
    NeighborhoodModel? selectedDistrict,
    NeighborhoodModel? selectedDong,
    bool? isSaving,
    bool clearDistrict = false,
    bool clearDong = false,
    /// Pass [clearSaveError]=true to clear the save error. Pass [saveError] to set one.
    /// Omit both to preserve the current value.
    AppError? saveError,
    bool clearSaveError = false,
  }) {
    return NeighborhoodPickerState(
      all: all ?? this.all,
      selectedCity: selectedCity ?? this.selectedCity,
      selectedDistrict:
          clearDistrict ? null : (selectedDistrict ?? this.selectedDistrict),
      selectedDong: clearDong ? null : (selectedDong ?? this.selectedDong),
      isSaving: isSaving ?? this.isSaving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
    );
  }
}

class NeighborhoodNotifier extends AsyncNotifier<NeighborhoodPickerState> {
  @override
  Future<NeighborhoodPickerState> build() async {
    final all =
        await ref.read(neighborhoodRepositoryProvider).getNeighborhoods();
    final initial = NeighborhoodPickerState(all: all);
    if (initial.cities.length == 1) {
      return initial.copyWith(selectedCity: initial.cities.first);
    }
    return initial;
  }

  void selectCity(NeighborhoodModel city) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        selectedCity: city,
        clearDistrict: true,
        clearDong: true,
        clearSaveError: true,
      ),
    );
  }

  void selectDistrict(NeighborhoodModel district) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(selectedDistrict: district, clearDong: true),
    );
  }

  void selectDong(NeighborhoodModel dong) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(selectedDong: dong));
  }

  Future<void> saveNeighborhood() async {
    final current = state.valueOrNull;
    if (current?.selectedDong == null) return;

    final dong = current!.selectedDong!;
    state = AsyncData(current.copyWith(isSaving: true, clearSaveError: true));

    try {
      await ref
          .read(neighborhoodRepositoryProvider)
          .saveNeighborhood(dong.id);

      // Optimistic in-memory update — avoids a getMe() round-trip and prevents
      // a transient network error from signing the user out (Story 1.4 review #4).
      final authUser = ref.read(authNotifierProvider).valueOrNull?.user;
      if (authUser != null) {
        ref
            .read(authNotifierProvider.notifier)
            .updateUser(authUser.copyWith(neighborhoodId: dong.id));
      }
      // isSaving reset is intentionally omitted — router navigates away on success.
    } on AppError catch (e) {
      final curr = state.valueOrNull;
      if (curr != null) {
        state = AsyncData(curr.copyWith(isSaving: false, saveError: e));
      }
    } catch (e) {
      final curr = state.valueOrNull;
      if (curr != null) {
        state = AsyncData(
          curr.copyWith(
            isSaving: false,
            saveError: AppError(
              message: e.toString(),
              code: AppErrorCode.unknown,
            ),
          ),
        );
      }
    }
  }
}

final neighborhoodNotifierProvider =
    AsyncNotifierProvider<NeighborhoodNotifier, NeighborhoodPickerState>(
  NeighborhoodNotifier.new,
);
