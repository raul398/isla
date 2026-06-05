import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isla/capture/frame_batcher.dart';
import 'package:isla/models/frame.dart';

void main() {
  group('FrameBatcher', () {
    late FrameBatcher batcher;

    setUp(() {
      batcher = FrameBatcher(batchSize: 3);
    });

    tearDown(() {
      // Some tests already dispose — guard with try/catch.
      try {
        batcher.dispose();
      } catch (_) {}
    });

    ProcessedFrame _frame(int id) => ProcessedFrame(
          bytes: Uint8List.fromList([id]),
          resolution: const Size(640, 480),
          timestamp: DateTime.now(),
        );

    // -------------------------------------------------------------------------
    // Happy path — buffer fills and emits
    // -------------------------------------------------------------------------
    test('emits a batch of 3 when buffer reaches batchSize (spec: camera-capture happy)', () async {
      final batches = <List<ProcessedFrame>>[];
      batcher.batchStream.listen(batches.add);

      batcher.addFrame(_frame(1));
      batcher.addFrame(_frame(2));
      batcher.addFrame(_frame(3)); // → emitted

      await Future<void>.delayed(Duration.zero);

      expect(batches.length, 1);
      expect(batches[0].length, 3);
      expect(batches[0][0].bytes[0], 1);
      expect(batches[0][2].bytes[0], 3);
    });

    // -------------------------------------------------------------------------
    // Multiple batches — each batch is emitted independently
    // -------------------------------------------------------------------------
    test('emits multiple batches as frames arrive (spec: camera-capture edge)',
        () async {
      final batches = <List<ProcessedFrame>>[];
      batcher.batchStream.listen(batches.add);

      // batchSize = 3 → each group of 3 frames becomes a separate batch.
      batcher.addFrame(_frame(1));
      batcher.addFrame(_frame(2));
      batcher.addFrame(_frame(3)); // batch 1 emitted (1, 2, 3)
      batcher.addFrame(_frame(4));
      batcher.addFrame(_frame(5));
      batcher.addFrame(_frame(6)); // batch 2 emitted (4, 5, 6)

      await Future<void>.delayed(Duration.zero);

      expect(batches.length, 2);
      expect(batches[0].length, 3);
      expect(batches[1].length, 3);

      // Each batch contains exactly the frames that filled it.
      expect(batches[0][0].bytes[0], 1);
      expect(batches[0][2].bytes[0], 3);
      expect(batches[1][0].bytes[0], 4);
      expect(batches[1][2].bytes[0], 6);
    });

    // -------------------------------------------------------------------------
    // Config — custom batchSize works
    // -------------------------------------------------------------------------
    test('custom batchSize emits batches of the configured size', () async {
      final custom = FrameBatcher(batchSize: 5);
      final batches = <List<ProcessedFrame>>[];
      custom.batchStream.listen(batches.add);

      for (int i = 1; i <= 5; i++) {
        custom.addFrame(_frame(i));
      }

      await Future<void>.delayed(Duration.zero);

      expect(batches.length, 1);
      expect(batches[0].length, 5);

      custom.dispose();
    });

    // -------------------------------------------------------------------------
    // Empty — dispose without data does not crash
    // -------------------------------------------------------------------------
    test('dispose without data does not crash', () {
      batcher = FrameBatcher(); // fresh batcher, no frames added
      expect(() => batcher.dispose(), returnsNormally);
    });

    // -------------------------------------------------------------------------
    // Edge — batchSize = 1 emits every frame
    // -------------------------------------------------------------------------
    test('batchSize of 1 emits every frame as its own batch', () async {
      final single = FrameBatcher(batchSize: 1);
      final batches = <List<ProcessedFrame>>[];
      single.batchStream.listen(batches.add);

      single.addFrame(_frame(1));
      single.addFrame(_frame(2));

      await Future<void>.delayed(Duration.zero);

      expect(batches.length, 2);
      expect(batches[0][0].bytes[0], 1);
      expect(batches[1][0].bytes[0], 2);

      single.dispose();
    });
  });
}
