import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/feed/data/models/neighborhood_model.dart';
import 'package:mobile/features/feed/domain/neighborhood_notifier.dart';
import 'package:mobile/features/feed/presentation/neighborhood_picker_screen.dart';

// ─── Test fixtures ──────────────────────────────────────────────────────────

const _city = NeighborhoodModel(id: 1, name: '서울특별시', level: 'city');
const _district = NeighborhoodModel(id: 2, name: '강남구', level: 'district', parentId: 1);
const _dong1 = NeighborhoodModel(id: 7, name: '역삼동', level: 'dong', parentId: 2);
const _dong2 = NeighborhoodModel(id: 8, name: '삼성동', level: 'dong', parentId: 2);

final _testNeighborhoods = [_city, _district, _dong1, _dong2];

// ─── Fake notifier ──────────────────────────────────────────────────────────

class _FakeNeighborhoodNotifier extends NeighborhoodNotifier {
  _FakeNeighborhoodNotifier({this.failOnSave = false});

  final bool failOnSave;
  bool savedCalled = false;

  @override
  Future<NeighborhoodPickerState> build() async {
    final s = NeighborhoodPickerState(all: _testNeighborhoods);
    // Auto-select city (only one)
    return s.copyWith(selectedCity: _city);
  }

  @override
  Future<void> saveNeighborhood() async {
    if (failOnSave) throw Exception('저장 실패');
    savedCalled = true;
  }
}

// ─── Helper ─────────────────────────────────────────────────────────────────

Widget _buildApp({bool failOnSave = false}) {
  return ProviderScope(
    overrides: [
      neighborhoodNotifierProvider
          .overrideWith(() => _FakeNeighborhoodNotifier(failOnSave: failOnSave)),
    ],
    child: const MaterialApp(home: NeighborhoodPickerScreen()),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('NeighborhoodPickerScreen', () {
    testWidgets('renders title and district dropdown', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('동네 설정'), findsOneWidget);
      expect(find.text('거래할 동네를 선택해 주세요'), findsOneWidget);
      // Labels for the three dropdowns
      expect(find.text('시'), findsOneWidget);
      expect(find.text('구'), findsOneWidget);
      expect(find.text('동'), findsOneWidget);
    });

    testWidgets('save button is disabled before dong selection', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '동네 설정 완료'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('selecting district enables dong dropdown', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Open 구 dropdown
      await tester.tap(find.byType(DropdownButtonFormField<NeighborhoodModel>).at(1));
      await tester.pumpAndSettle();

      expect(find.text('강남구'), findsOneWidget);
      await tester.tap(find.text('강남구').last);
      await tester.pumpAndSettle();

      // 동 dropdown should now show items
      await tester.tap(find.byType(DropdownButtonFormField<NeighborhoodModel>).at(2));
      await tester.pumpAndSettle();

      expect(find.text('역삼동'), findsOneWidget);
      expect(find.text('삼성동'), findsOneWidget);
    });
  });

  // ─── NeighborhoodPickerState unit tests ───────────────────────────────────
  group('NeighborhoodPickerState', () {
    test('cities filters correctly', () {
      final s = NeighborhoodPickerState(all: _testNeighborhoods);
      expect(s.cities, [_city]);
    });

    test('districts empty without city', () {
      final s = NeighborhoodPickerState(all: _testNeighborhoods);
      expect(s.districts, isEmpty);
    });

    test('districts filters by selected city', () {
      final s = NeighborhoodPickerState(
        all: _testNeighborhoods,
        selectedCity: _city,
      );
      expect(s.districts, [_district]);
    });

    test('dongs empty without district', () {
      final s = NeighborhoodPickerState(all: _testNeighborhoods, selectedCity: _city);
      expect(s.dongs, isEmpty);
    });

    test('dongs filters by selected district', () {
      final s = NeighborhoodPickerState(
        all: _testNeighborhoods,
        selectedCity: _city,
        selectedDistrict: _district,
      );
      expect(s.dongs, containsAll([_dong1, _dong2]));
    });

    test('canSave is false without dong', () {
      final s = NeighborhoodPickerState(
        all: _testNeighborhoods,
        selectedCity: _city,
        selectedDistrict: _district,
      );
      expect(s.canSave, isFalse);
    });

    test('canSave is true with dong selected', () {
      final s = NeighborhoodPickerState(
        all: _testNeighborhoods,
        selectedCity: _city,
        selectedDistrict: _district,
        selectedDong: _dong1,
      );
      expect(s.canSave, isTrue);
    });

    test('copyWith clearDistrict resets district and dong', () {
      final s = NeighborhoodPickerState(
        all: _testNeighborhoods,
        selectedCity: _city,
        selectedDistrict: _district,
        selectedDong: _dong1,
      );
      final updated = s.copyWith(selectedCity: _city, clearDistrict: true, clearDong: true);
      expect(updated.selectedDistrict, isNull);
      expect(updated.selectedDong, isNull);
    });
  });
}
