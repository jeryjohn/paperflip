import 'package:flip_book/flip_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VolumeKeyManager.instance.resetForTesting();
    VolumeKeyManager.debugPlatformOverride = TargetPlatform.android;
  });

  tearDown(VolumeKeyManager.instance.resetForTesting);


  group('VolumeKeyManager', () {
    test('disabled by default: no clients and not listening', () {
      expect(VolumeKeyManager.instance.clientCount, 0);
      expect(VolumeKeyManager.instance.activeClient, isNull);
      expect(VolumeKeyManager.instance.isListening, isFalse);
    });

    test('registers and unregisters clients', () {
      final client = _MockVolumeKeyClient();
      VolumeKeyManager.instance.registerClient(client);

      expect(VolumeKeyManager.instance.clientCount, 1);
      expect(VolumeKeyManager.instance.activeClient, client);

      VolumeKeyManager.instance.unregisterClient(client);
      expect(VolumeKeyManager.instance.clientCount, 0);
      expect(VolumeKeyManager.instance.activeClient, isNull);
      expect(VolumeKeyManager.instance.isListening, isFalse);
    });

    test('multi-reader stack routing: topmost client receives events', () {
      final reader1 = _MockVolumeKeyClient();
      final reader2 = _MockVolumeKeyClient();

      VolumeKeyManager.instance.registerClient(reader1);
      VolumeKeyManager.instance.registerClient(reader2);

      expect(VolumeKeyManager.instance.activeClient, reader2);

      VolumeKeyManager.instance.handleEventForTesting('up');
      expect(reader2.upCount, 1);
      expect(reader1.upCount, 0);

      VolumeKeyManager.instance.handleEventForTesting('down');
      expect(reader2.downCount, 1);
      expect(reader1.downCount, 0);

      // Reader 2 closes / unregisters
      VolumeKeyManager.instance.unregisterClient(reader2);
      expect(VolumeKeyManager.instance.activeClient, reader1);

      VolumeKeyManager.instance.handleEventForTesting('up');
      expect(reader1.upCount, 1);
      expect(reader2.upCount, 1);
    });

    test('re-registering an existing client moves it to the top of the stack', () {
      final reader1 = _MockVolumeKeyClient();
      final reader2 = _MockVolumeKeyClient();

      VolumeKeyManager.instance.registerClient(reader1);
      VolumeKeyManager.instance.registerClient(reader2);
      expect(VolumeKeyManager.instance.activeClient, reader2);

      VolumeKeyManager.instance.registerClient(reader1);
      expect(VolumeKeyManager.instance.activeClient, reader1);

      VolumeKeyManager.instance.handleEventForTesting('up');
      expect(reader1.upCount, 1);
      expect(reader2.upCount, 0);
    });

    test('cross-platform: does not listen on non-Android platforms', () {
      VolumeKeyManager.debugPlatformOverride = TargetPlatform.iOS;
      final client = _MockVolumeKeyClient();

      VolumeKeyManager.instance.registerClient(client);
      expect(VolumeKeyManager.instance.clientCount, 1);
      expect(VolumeKeyManager.instance.isListening, isFalse);
    });

  });

  group('MeshFlipBook Volume Keys', () {
    testWidgets('disabled by default: does not register with VolumeKeyManager',
        (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            pageCount: 5,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );

      expect(VolumeKeyManager.instance.clientCount, 0);
      expect(VolumeKeyManager.instance.isListening, isFalse);
    });

    testWidgets('enabled: registers with VolumeKeyManager and unregisters on dispose',
        (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            pageCount: 5,
            useVolumeKeys: true,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );

      expect(VolumeKeyManager.instance.clientCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(VolumeKeyManager.instance.clientCount, 0);
      expect(VolumeKeyManager.instance.isListening, isFalse);
    });

    testWidgets('dynamic toggle: updates registration', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            pageCount: 5,
            useVolumeKeys: false,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );
      expect(VolumeKeyManager.instance.clientCount, 0);

      // Toggle to true
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            pageCount: 5,
            useVolumeKeys: true,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );
      expect(VolumeKeyManager.instance.clientCount, 1);

      // Toggle back to false
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            pageCount: 5,
            useVolumeKeys: false,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );
      expect(VolumeKeyManager.instance.clientCount, 0);
    });

    testWidgets('Volume Up flips to next page and Volume Down flips to previous page',
        (tester) async {
      final controller = FlipBookController();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            controller: controller,
            pageCount: 5,
            useVolumeKeys: true,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.currentPage, 0);

      // Press Volume Up -> Next page
      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);

      // Press Volume Down -> Previous page
      VolumeKeyManager.instance.handleEventForTesting('down');
      await tester.pumpAndSettle();
      expect(controller.currentPage, 0);
    });

    testWidgets('boundary safety: Volume Down at page 0 and Volume Up at last page',
        (tester) async {
      final controller = FlipBookController();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MeshFlipBook(
            controller: controller,
            pageCount: 3,
            initialPage: 0,
            useVolumeKeys: true,
            pageBuilder: (context, index, constraints) => Text('Page $index'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // At page 0: Volume Down should be a no-op
      VolumeKeyManager.instance.handleEventForTesting('down');
      await tester.pumpAndSettle();
      expect(controller.currentPage, 0);

      // Advance to page 2 (last page)
      await controller.goToPage(2, animate: false);
      await tester.pumpAndSettle();
      expect(controller.currentPage, 2);

      // At page 2: Volume Up should be a no-op
      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pumpAndSettle();
      expect(controller.currentPage, 2);
    });
  });

  group('FlipBook Facade constructors pass useVolumeKeys', () {
    testWidgets('FlipBook.custom enables volume keys', (tester) async {
      final controller = FlipBookController();
      await tester.pumpWidget(
        MaterialApp(
          home: FlipBook.custom(
            controller: controller,
            pageCount: 4,
            useVolumeKeys: true,
            pageBuilder: (context, index, constraints) => Text('P$index'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(VolumeKeyManager.instance.clientCount, 1);

      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pumpAndSettle();
      expect(controller.currentPage, 1);
    });
  });

  group('FlipBookReader Volume Keys routing', () {
    testWidgets('disabled by default in FlipBookReader', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlipBookReader(
            forceLightweightViewer: true,
          ),
        ),
      );

      expect(VolumeKeyManager.instance.clientCount, 0);
      expect(VolumeKeyManager.instance.isListening, isFalse);
    });

    testWidgets('enabled in FlipBookReader routes to controller in flip mode',
        (tester) async {
      final controller = FlipBookController();

      await tester.pumpWidget(
        MaterialApp(
          home: FlipBookReader(
            controller: controller,
            useVolumeKeys: true,
            forceLightweightViewer: false,
          ),
        ),
      );
      await tester.pump();

      expect(VolumeKeyManager.instance.clientCount, 1);

      // Simulate Volume Up via VolumeKeyManager
      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pump();

      // Volume Down
      VolumeKeyManager.instance.handleEventForTesting('down');
      await tester.pump();
    });

    testWidgets('Navigator push and pop manages VolumeKeyManager stack deterministically',
        (tester) async {
      final ctrl1 = FlipBookController();
      final ctrl2 = FlipBookController();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: MeshFlipBook(
                      controller: ctrl1,
                      pageCount: 3,
                      useVolumeKeys: true,
                      pageBuilder: (context, index, constraints) =>
                          Text('Reader1-P$index'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            body: MeshFlipBook(
                              controller: ctrl2,
                              pageCount: 3,
                              useVolumeKeys: true,
                              pageBuilder: (context, index, constraints) =>
                                  Text('Reader2-P$index'),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Push Reader 2'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(VolumeKeyManager.instance.clientCount, 1);
      expect(ctrl1.currentPage, 0);

      // Volume up advances Reader 1
      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pumpAndSettle();
      expect(ctrl1.currentPage, 1);

      // Push Reader 2
      await tester.tap(find.text('Push Reader 2'));
      await tester.pumpAndSettle();

      expect(VolumeKeyManager.instance.clientCount, 2);
      expect(ctrl2.currentPage, 0);

      // Volume up now advances Reader 2 (topmost active reader), Reader 1 stays at page 1
      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pumpAndSettle();
      expect(ctrl2.currentPage, 1);
      expect(ctrl1.currentPage, 1);

      // Pop Reader 2
      final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
      navigatorState.pop();
      await tester.pumpAndSettle();

      expect(VolumeKeyManager.instance.clientCount, 1);

      // Volume up now advances Reader 1 again
      VolumeKeyManager.instance.handleEventForTesting('up');
      await tester.pumpAndSettle();
      expect(ctrl1.currentPage, 2);
    });
  });

  group('Platform EventChannel integration', () {
    test('EventChannel sends up and down messages to active reader', () async {
      final client = _MockVolumeKeyClient();
      VolumeKeyManager.instance.registerClient(client);

      // Native code sends 'up' over the platform channel
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'io.github.jeryjohn.paperflip/volume_keys',
        const StandardMethodCodec().encodeSuccessEnvelope('up'),
        (ByteData? data) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.upCount, 1);

      // Native code sends 'down' over the platform channel
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'io.github.jeryjohn.paperflip/volume_keys',
        const StandardMethodCodec().encodeSuccessEnvelope('down'),
        (ByteData? data) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.downCount, 1);
    });


    test('EventChannel channel subscription lifecycle (listen / cancel)', () async {
      final methodCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('io.github.jeryjohn.paperflip/volume_keys'),
        (MethodCall call) async {
          methodCalls.add(call.method);
          return null;
        },
      );

      final client1 = _MockVolumeKeyClient();
      final client2 = _MockVolumeKeyClient();

      expect(methodCalls, isEmpty);

      // Register client 1: triggers listen
      VolumeKeyManager.instance.registerClient(client1);
      expect(methodCalls, ['listen']);

      // Register client 2: stream already open, does not call listen again
      VolumeKeyManager.instance.registerClient(client2);
      expect(methodCalls, ['listen']);

      // Unregister client 2: client 1 still active, does not cancel
      VolumeKeyManager.instance.unregisterClient(client2);
      expect(methodCalls, ['listen']);

      // Unregister client 1: no clients remain, triggers cancel
      VolumeKeyManager.instance.unregisterClient(client1);
      expect(methodCalls, ['listen', 'cancel']);
    });
  });

}

class _MockVolumeKeyClient implements VolumeKeyClient {
  int upCount = 0;
  int downCount = 0;

  @override
  void onVolumeUp() {
    upCount++;
  }

  @override
  void onVolumeDown() {
    downCount++;
  }
}
