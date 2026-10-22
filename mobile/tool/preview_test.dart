// Developer-only screenshot using explicitly synthetic fixtures.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:unistay_mobile/data.dart';
import 'package:unistay_mobile/main.dart';
import '../test/helpers.dart';

void main() {
  testWidgets('render synthetic mobile catalog for visual inspection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final fontPath =
          Platform.environment['PREVIEW_FONT'] ??
          'C:/Windows/Fonts/segoeui.ttf';
      final textFont = FontLoader('Roboto')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await textFont.load();
      final flutterRoot =
          Platform.environment['FLUTTER_ROOT'] ??
          File(
            Platform.resolvedExecutable,
          ).parent.parent.parent.parent.parent.parent.path;
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await icons.load();
    });
    final state = AppState(
      api: ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => response(page([listing(1)]))),
      ),
      store: MemoryStore(),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: UniStayApp(state: state),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('.local').create(recursive: true);
      await File(
        '.local/catalog-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
