import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/app/app_providers.dart';
import 'package:fahrzeugakte/features/meters/presentation/care_activity_field.dart';

void main() {
  testWidgets('Done leaves an empty activity empty', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          careActivitySuggestionsProvider.overrideWith(
            (ref) => Stream.value(['Wartung', 'Reparatur']),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CareActivityField(controller: controller, onChanged: (_) {}),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('care-activity')));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving the form while suggestions load does not update a disposed field',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final loaded = Completer<List<String>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            careActivitySuggestionsProvider.overrideWith(
              (ref) => loaded.future.asStream(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CareActivityField(
                controller: controller,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Blüte',
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      loaded.complete(['Erste Blüte']);
      await tester.pumpAndSettle();
      expect(controller.text, 'Blüte');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard Done preserves a custom label instead of accepting the first suggestion',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            careActivitySuggestionsProvider.overrideWith(
              (ref) => Stream.value(['Erste Blüte']),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CareActivityField(
                controller: controller,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Blüte',
      );
      await tester.pumpAndSettle();
      expect(find.text('Erste Blüte'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.text, 'Blüte');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'suggestions loaded after typing appear without changing the input',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final loaded = Completer<List<String>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            careActivitySuggestionsProvider.overrideWith(
              (ref) => loaded.future.asStream(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CareActivityField(
                controller: controller,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'blü',
      );
      await tester.pump();
      loaded.complete(['Wartung', 'Erste Blüte']);
      await tester.pumpAndSettle();
      expect(find.text('Erste Blüte'), findsOneWidget);
      expect(find.text('Wartung'), findsNothing);
      expect(controller.text, 'blü');
      await tester.tap(find.text('Erste Blüte'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Erste Blüte');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed suggestions do not block free input or standard suggestions',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            careActivitySuggestionsProvider.overrideWith(
              (ref) => Stream.error(StateError('Unavailable')),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CareActivityField(
                controller: controller,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'War',
      );
      await tester.pumpAndSettle();
      expect(find.text('Wartung'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('care-activity')),
        'Eigener Vorgang',
      );
      await tester.pumpAndSettle();
      expect(controller.text, 'Eigener Vorgang');
      expect(tester.takeException(), isNull);
    },
  );
}
