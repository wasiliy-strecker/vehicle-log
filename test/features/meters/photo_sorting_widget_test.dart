import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';
import 'package:fahrzeugakte/features/meters/presentation/reading_photo_gallery.dart';

import 'multiple_photos_test.dart' show testPhoto;

void main() {
  testWidgets(
    'drag moves across rows and backwards, cancellation preserves order',
    (tester) async {
      final model = _Model(6);
      await _mount(tester, model, height: 1100);
      await _drag(tester, 'a', 'd');
      expect(model.ids, ['b', 'c', 'd', 'a', 'e', 'f']);
      await _drag(tester, 'f', 'b');
      expect(model.ids, ['f', 'b', 'c', 'd', 'a', 'e']);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('photo-drag-f'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(const Offset(-40, 250));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(model.ids, ['f', 'b', 'c', 'd', 'a', 'e']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'menu boundaries, busy state and large type retain accessible ordering',
    (tester) async {
      final model = _Model(3);
      await _mount(tester, model, height: 1100, textScale: 2);
      await tester.tap(find.byTooltip('Foto 1 bearbeiten'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, 'Nach vorne'),
            )
            .enabled,
        false,
      );
      await tester.tap(find.text('Nach hinten'));
      await tester.pumpAndSettle();
      expect(model.ids, ['b', 'a', 'c']);
      await tester.tap(find.byTooltip('Foto 3 bearbeiten'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, 'Nach hinten'),
            )
            .enabled,
        false,
      );
      await tester.tap(find.text('Nach vorne'));
      await tester.pumpAndSettle();
      expect(model.ids, ['b', 'c', 'a']);
      model.busy = true;
      model.notifyListeners();
      await tester.pumpAndSettle();
      await _drag(tester, 'b', 'a');
      expect(model.ids, ['b', 'c', 'a']);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('photo-menu-b')),
            )
            .enabled,
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag scrolls the surrounding form and cleans up when cancelled',
    (tester) async {
      final model = _Model(16);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _mount(tester, model, height: 600, scroll: scroll);
      final original = model.ids.toList();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('photo-drag-a'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(const Offset(180, 590));
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, greaterThan(200));
      await gesture.moveTo(const Offset(-40, 300));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(model.ids, original);
      final stoppedAt = scroll.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, stoppedAt);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _drag(WidgetTester tester, String from, String to) async {
  final source = find.byKey(ValueKey('photo-drag-$from'));
  final target = find.byKey(ValueKey('photo-drag-$to'));
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 150));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  _Model model, {
  required double height,
  double textScale = 1,
  ScrollController? scroll,
}) async {
  await tester.binding.setSurfaceSize(Size(360, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(model.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            ListenableBuilder(
              listenable: model,
              builder: (_, _) => ReadingPhotoGallery(
                photos: model.photos,
                enabled: !model.busy,
                onReorder: (ids) {
                  final byId = {for (final p in model.photos) p.id: p};
                  model.photos = ids.map((id) => byId[id]!).toList();
                  model.notifyListeners();
                },
              ),
            ),
            const SizedBox(height: 200),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Model extends ChangeNotifier {
  _Model(int count)
    : photos = List.generate(
        count,
        (i) => testPhoto(String.fromCharCode(97 + i)),
      );
  List<ReadingPhotoVersion> photos;
  bool busy = false;
  Iterable<String> get ids => photos.map((p) => p.id);
}
