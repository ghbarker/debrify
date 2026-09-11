import 'dart:async';

import 'package:debrify/widgets/scroll_deferred_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Provider extends ImageProvider<Object> {
  _Provider({this.keyFuture});
  final Future<Object>? keyFuture;
  int loads = 0;
  final image = Completer<ImageInfo>();
  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      keyFuture ?? SynchronousFuture<Object>(this);
  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(image.future);
  }
}

class _Scrolling extends ValueNotifier<bool> {
  _Scrolling(super.value);
  bool get observed => hasListeners;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = PaintingBinding.instance.imageCache;
  setUp(() {
    cache.clear();
    cache.clearLiveImages();
  });
  tearDown(() {
    cache.clear();
    cache.clearLiveImages();
  });

  Widget view(_Scrolling scroll, ImageProvider image) => Directionality(
    textDirection: TextDirection.ltr,
    child: ScrollDeferredImage(
      scrolling: scroll,
      image: image,
      placeholder: const Text('waiting'),
      child: Image(image: image),
    ),
  );

  testWidgets(
    'cold loads wait for vertical idle and never disappear on restart',
    (tester) async {
      final scroll = _Scrolling(true);
      final image = _Provider();
      await tester.pumpWidget(view(scroll, image));
      expect(image.loads, 0);
      expect(find.text('waiting'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(image.loads, 0);
      scroll.value = false;
      await tester.pump();
      expect(image.loads, 1);
      expect(find.byType(Image), findsOneWidget);
      scroll.value = true;
      await tester.pump();
      expect(find.text('waiting'), findsNothing);
      expect(image.loads, 1);
      await tester.pumpWidget(const SizedBox());
      expect(scroll.observed, isFalse);
      scroll.dispose();
    },
  );

  testWidgets('decoded warm image is visible on the first moving frame', (
    tester,
  ) async {
    final scroll = _Scrolling(false);
    final source = _Provider();
      final pixels = (await tester.runAsync(
        () => createTestImage(width: 16, height: 9, cache: false),
      ))!;
    source.image.complete(ImageInfo(image: pixels));
    await tester.pumpWidget(view(scroll, source));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(cache.statusForKey(source).keepAlive, isTrue);
    scroll.value = true;
    await tester.pumpWidget(view(scroll, source));
    expect(find.text('waiting'), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(source.loads, 1);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets(
    'existing resized pending stream attaches during movement without new load',
    (tester) async {
      final scroll = _Scrolling(true);
      final source = _Provider();
      final provider = ResizeImage(source, width: 320);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(source.image.future),
      );
      await tester.pumpWidget(view(scroll, provider));
      expect(find.text('waiting'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(source.loads, 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets(
    'new identity defers; stale async warm key cannot release replacement',
    (tester) async {
      final scroll = _Scrolling(true);
      final oldKey = Completer<Object>();
      final old = _Provider(keyFuture: oldKey.future);
      final replacement = _Provider();
      cache.putIfAbsent(
        old,
        () => OneFrameImageStreamCompleter(old.image.future),
      );
      await tester.pumpWidget(view(scroll, old));
      await tester.pumpWidget(view(scroll, replacement));
      oldKey.complete(old);
      await tester.pump();
      expect(replacement.loads, 0);
      expect(find.text('waiting'), findsOneWidget);
      scroll.value = false;
      await tester.pump();
      expect(replacement.loads, 1);
      scroll.value = true;
      final third = _Provider();
      await tester.pumpWidget(view(scroll, third));
      expect(third.loads, 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets('owner replacement and disposal detach listeners and late keys', (
    tester,
  ) async {
    final first = _Scrolling(true), next = _Scrolling(true);
    final key = Completer<Object>();
    final image = _Provider(keyFuture: key.future);
    await tester.pumpWidget(view(first, image));
    await tester.pumpWidget(view(next, image));
    expect(first.observed, isFalse);
    expect(next.observed, isTrue);
    first.value = false;
    await tester.pump();
    expect(find.text('waiting'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    key.complete(image);
    next.value = false;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(next.observed, isFalse);
    first.dispose();
    next.dispose();
  });
}
