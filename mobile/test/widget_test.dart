import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:unistay_mobile/data.dart';
import 'package:unistay_mobile/main.dart';
import 'package:unistay_mobile/catalog.dart';
import 'helpers.dart';

void main() {
  testWidgets('guest catalog is usable at 390px and guest cannot apply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(
      api: ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient(
          (r) async => response(
            r.url.path.endsWith('/1/') ? listing(1) : page([listing(1)]),
          ),
        ),
      ),
      store: MemoryStore(),
    );
    await tester.pumpWidget(UniStayApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Жильё найдётся.\nСоседи — тоже.'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.ensureVisible(find.text('Квартира 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Квартира 1'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Войти, чтобы подать заявку'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Подать заявку на место'), findsNothing);
    expect(tester.takeException(), null);
    await tester.tap(find.text('Войти, чтобы подать заявку'));
    await tester.pumpAndSettle();
    expect(find.text('С возвращением'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'verified student submits real-shaped request then cancels from applications',
    (tester) async {
      var submitted = false, cancelled = false;
      final state = AppState(
        api: ApiClient(
          baseUrl: 'https://example.test',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/group/')) return response([]);
            if (r.url.path.endsWith('/cancel/')) {
              cancelled = true;
              return response(application(status: 'cancelled'));
            }
            if (r.url.path.endsWith('/applications/')) {
              if (r.method == 'POST') {
                expect(jsonDecode(r.body)['listing_id'], 1);
                expect(r.headers['Authorization'], 'Bearer test');
                submitted = true;
                return response(application(), 201);
              }
              return response(
                page(
                  submitted
                      ? [
                          application(
                            status: cancelled ? 'cancelled' : 'pending',
                          ),
                        ]
                      : [],
                ),
              );
            }
            if (r.url.path.endsWith('/listings/1/')) {
              return response(listing(1));
            }
            return response(page([listing(1)]));
          }),
        )..token = 'test',
        store: MemoryStore(),
      )..user = student();
      await tester.pumpWidget(UniStayApp(state: state));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Квартира 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Квартира 1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Подать заявку на место'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Подать заявку на место'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(submitted, true);
      expect(find.text('Заявка отправлена'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Заявки'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Отменить заявку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить заявку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(cancelled, true);
      expect(find.text('Отменена'), findsWidgets);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('unverified student sees verification instead of submit', (
    tester,
  ) async {
    final state = AppState(
      api: ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => response(listing(1))),
      ),
      store: MemoryStore(),
    )..user = student(verified: false);
    await tester.pumpWidget(
      MaterialApp(
        home: ListingScreen(state: state, id: 1, onAccount: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Подтвердить email'), 400);
    expect(find.text('Подать заявку на место'), findsNothing);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('filter prevents invalid price range', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FilterScreen(initial: {})));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Цена от, ₸'),
      '90000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Цена до, ₸'),
      '50000',
    );
    await tester.ensureVisible(find.text('Показать объявления'));
    await tester.tap(find.text('Показать объявления'));
    await tester.pumpAndSettle();
    expect(
      find.text('Максимум должен быть не меньше минимума'),
      findsOneWidget,
    );
  });
}
