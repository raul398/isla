import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isla/inference/sequence_translator.dart';
import 'package:isla/models/gesture.dart';
import 'package:isla/models/translation.dart';
import 'package:isla/providers/caption_provider.dart';
import 'package:isla/providers/inference_provider.dart';

/// Simulated gesture sequence representing a real sign-language phrase
/// (word gestures in LSA subset).
///
/// Sequence: "yo quiero agua" — 3 word gestures.
final List<Gesture> _wordSequence = [
  Gesture(label: 'yo', confidence: 0.95, timestamp: DateTime.now()),
  Gesture(
      label: 'querer',
      confidence: 0.92,
      timestamp: DateTime.now().add(const Duration(milliseconds: 300))),
  Gesture(
      label: 'agua',
      confidence: 0.88,
      timestamp: DateTime.now().add(const Duration(milliseconds: 600))),
];

/// Simulated letter-by-letter spelling: "CASA".
final List<Gesture> _letterSequence = [
  Gesture(label: 'C', confidence: 0.97, timestamp: DateTime.now()),
  Gesture(
      label: 'A',
      confidence: 0.95,
      timestamp: DateTime.now().add(const Duration(milliseconds: 200))),
  Gesture(
      label: 'S',
      confidence: 0.93,
      timestamp: DateTime.now().add(const Duration(milliseconds: 400))),
  Gesture(
      label: 'A',
      confidence: 0.91,
      timestamp: DateTime.now().add(const Duration(milliseconds: 600))),
];

void main() {
  group('Pipeline Integration', () {
    // =========================================================================
    // 1. SequenceTranslator → Translation
    // =========================================================================
    group('SequenceTranslator → Translation', () {
      late SequenceTranslator translator;

      setUp(() {
        translator = SequenceTranslator(
          windowDuration: const Duration(seconds: 2),
        );
      });

      tearDown(() {
        translator.dispose();
      });

      test('word sequence produces expected partial text', () {
        for (final gesture in _wordSequence) {
          translator.processGesture(gesture);
        }

        // Capture output after the full word sequence.
        final output = translator.flush();

        // The SequenceTranslator uses a rule-based decoder:
        // non-letter gestures → space-separated.
        expect(output.confirmedText, contains('yo'),
            reason: 'first word in sequence');
        expect(output.confirmedText, contains('agua'),
            reason: 'last word in sequence');
        expect(output.isFinal, isTrue,
            reason: 'flush marks the window as complete');
      });

      test('letter sequence produces uppercase joined word', () {
        for (final gesture in _letterSequence) {
          translator.processGesture(gesture);
        }

        final output = translator.flush();

        // Letter-only sequence → uppercase joined, so "CASA".
        expect(output.confirmedText, 'CASA',
            reason: 'letters join as uppercase word');
        expect(output.isFinal, isTrue);
      });

      test('window expiry flushes and starts new window via stream', () async {
        // processGesture() always returns isFinal=false.
        // isFinal=true translations are emitted on the output stream.
        final onStream = <Translation>[];
        translator.output.listen(onStream.add);

        final g1 = Gesture(
            label: 'hola',
            confidence: 0.95,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0));
        final g2 = Gesture(
            label: 'gracias',
            confidence: 0.92,
            timestamp: DateTime.fromMillisecondsSinceEpoch(2500)); // gap > 2s

        // First gesture — no flush.
        final t1 = translator.processGesture(g1);
        expect(t1.isFinal, isFalse);
        expect(t1.partialText, 'hola');

        // Second gesture triggers flush of previous window (gap > window).
        translator.processGesture(g2);

        // Stream: [0] partial:'hola' → [1] isFinal:true confirmed:'hola' → [2] partial:'gracias'
        await Future<void>.delayed(Duration.zero);
        expect(onStream.length, 3);
        expect(onStream[1].isFinal, isTrue,
            reason: 'window expired via gap detection');
        expect(onStream[1].confirmedText, 'hola',
            reason: 'first window confirmed');
      });

      test('confirmed text accumulates after gap-triggered flush', () {
        // Verify via explicit flush that confirmed text is preserved.
        final g1 = Gesture(
            label: 'hola',
            confidence: 0.95,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0));
        final g2 = Gesture(
            label: 'gracias',
            confidence: 0.92,
            timestamp: DateTime.fromMillisecondsSinceEpoch(2500));

        translator.processGesture(g1);
        translator.processGesture(g2);

        final flushed = translator.flush();
        expect(flushed.confirmedText, 'hola gracias',
            reason: 'both windows accumulate in confirmed');
      });

      test('processes 3+ gestures into a coherent phrase', () {
        // "yo quiero agua" → should produce "yo quiero agua".
        for (final gesture in _wordSequence) {
          translator.processGesture(gesture);
        }

        // Verify streaming partial text at each step.
        // (The full phrase space-separated.)
        final flushed = translator.flush();
        expect(flushed.confirmedText, 'yo querer agua',
            reason: 'word-gestures space-separated');
      });
    });

    // =========================================================================
    // 2. Translation → CaptionProvider → CaptionState
    // =========================================================================
    group('Translation → CaptionProvider', () {
      late StreamController<Translation> inferenceCtrl;
      late ProviderContainer container;

      ProviderContainer _buildContainer() {
        inferenceCtrl = StreamController<Translation>.broadcast();
        return ProviderContainer(
          overrides: [
            inferenceStreamProvider.overrideWith(
              (ref) => inferenceCtrl.stream,
            ),
          ],
        );
      }

      setUp(() {
        container = _buildContainer();
        // Pre-warm the inference provider so CaptionProvider can subscribe.
        container.read(inferenceStreamProvider);
        // Pre-create CaptionProvider so its ref.listen is registered before
        // any test emits events. Without this, events emitted on the broadcast
        // stream before the provider is read are lost forever.
        container.read(captionProvider);
      });

      tearDown(() async {
        await inferenceCtrl.close();
        container.dispose();
      });

      /// Feed a Translation and wait for Riverpod async propagation.
      Future<void> feed(Translation t) async {
        inferenceCtrl.add(t);
        await Future<void>.delayed(Duration.zero);
      }

      TranslationState readState() =>
          container.read(captionProvider).asData!.value;

      test('5 consistent frames confirm a gesture in the UI', () async {
        for (int i = 0; i < 5; i++) {
          await feed(Translation(
            partialText: 'hola',
            confirmedText: '',
            isFinal: false,
          ));
        }

        final state = readState();
        expect(state.confirmedText, 'hola',
            reason: 'confirmed after 5 consistent frames');
        expect(state.partialText, '',
            reason: 'partial cleared after confirmation');
      });

      test('isFinal forces immediate confirmation', () async {
        await feed(Translation(
          partialText: 'gracias',
          confirmedText: '',
          isFinal: true,
        ));

        final state = readState();
        expect(state.confirmedText, 'gracias',
            reason: 'isFinal promotes instantly');
        expect(state.isFinal, isTrue);
      });

      test('idle timeout clears after 5s without input', () async {
        // Confirm a gesture first — each emit needs async propagation.
        for (int i = 0; i < 5; i++) {
          await feed(Translation(
            partialText: 'hola',
            confirmedText: '',
            isFinal: false,
          ));
        }

        expect(readState().confirmedText, 'hola',
            reason: 'confirmed before idle');

        // Wait past the 5-second timeout.
        await Future<void>.delayed(const Duration(seconds: 6));

        expect(readState().isEmpty, isTrue,
            reason: 'cleared after idle timeout');
      });
    });

    // =========================================================================
    // 3. End-to-end: Gesture sequence → Caption state
    // =========================================================================
    group('Full data flow: Gesture → Caption', () {
      late SequenceTranslator translator;
      late StreamController<Translation> inferenceCtrl;
      late ProviderContainer container;

      setUp(() {
        translator = SequenceTranslator(
          windowDuration: const Duration(seconds: 2),
        );
        inferenceCtrl = StreamController<Translation>.broadcast();
        container = ProviderContainer(
          overrides: [
            inferenceStreamProvider.overrideWith(
              (ref) => inferenceCtrl.stream,
            ),
          ],
        );
        // Pre-warm the inference provider so CaptionProvider can subscribe.
        container.read(inferenceStreamProvider);
        // Pre-create CaptionProvider so its ref.listen is registered before
        // any test emits events.
        container.read(captionProvider);
      });

      tearDown(() async {
        translator.dispose();
        await inferenceCtrl.close();
        container.dispose();
      });

      /// Feed a Translation into CaptionProvider and wait for propagation.
      Future<void> feed(Translation t) async {
        inferenceCtrl.add(t);
        await Future<void>.delayed(Duration.zero);
      }

      test('gesture "hola" → translator → CaptionProvider → confirmed text',
          () async {
        // Phase 1: Feed a single gesture into the translator.
        final t = translator.processGesture(
          Gesture(
              label: 'hola',
              confidence: 0.95,
              timestamp: DateTime.fromMillisecondsSinceEpoch(0)),
        );

        // Phase 2: Feed the translator's partialText into CaptionProvider
        // 5 times (simulating 5 consistent frames in the real pipeline).
        // Note: CaptionProvider only uses t.partialText and t.isFinal for
        // its confirmation logic — confirmedText from Translation is ignored.
        for (int i = 0; i < 5; i++) {
          await feed(Translation(
            partialText: t.partialText,
            confirmedText: '',
            isFinal: t.isFinal,
          ));
        }

        final state = container.read(captionProvider).asData!.value;
        expect(state.confirmedText, 'hola',
            reason: 'gesture "hola" confirmed by caption provider');
        expect(state.isEmpty, isFalse,
            reason: 'non-empty UI state');
      });

      test('sequence "yo quiero agua" → translator → CaptionProvider', () async {
        // Feed all word gestures into translator within window.
        for (final gesture in _wordSequence) {
          translator.processGesture(gesture);
        }

        // Flush to get the final phrase confirmed.
        final flushed = translator.flush();
        expect(flushed.confirmedText, 'yo querer agua',
            reason: 'translator produces the full phrase');

        // Now simulate the pipeline: CaptionProvider receives the progressive
        // partial texts from the translator. In a real run the translator
        // emits after each gesture. We replicate the 5-frame confirmation for
        // the final partial text.
        final partial = flushed.partialText; // '' after flush
        // For a realistic end-to-end test, use the processGesture outputs:
        final t1 = _wordSequence[0]; // epoch 0
        final t2 = _wordSequence[1]; // epoch 300
        final t3 = _wordSequence[2]; // epoch 600

        // The translator's output for these three gestures:
        final Translation p1, p2, p3;
        {
          final seq = SequenceTranslator(
              windowDuration: const Duration(seconds: 2));
          p1 = seq.processGesture(t1); // partial: 'yo'
          p2 = seq.processGesture(t2); // partial: 'yo querer'
          p3 = seq.processGesture(t3); // partial: 'yo querer agua'
          seq.dispose();
        }

        // Feed progressive partials (simulating real streaming pipeline).
        // First gesture partial appears in grey.
        await feed(Translation(partialText: p1.partialText, confirmedText: '', isFinal: false));
        await feed(Translation(partialText: p2.partialText, confirmedText: '', isFinal: false));

        // Feed the final partial 5 times to confirm it.
        for (int i = 0; i < 5; i++) {
          await feed(Translation(partialText: p3.partialText, confirmedText: '', isFinal: false));
        }

        final state = container.read(captionProvider).asData!.value;
        expect(state.confirmedText, 'yo querer agua',
            reason: 'full phrase confirmed in caption');
        expect(state.partialText, '',
            reason: 'partial cleared after confirmation');
      });

      test('end-to-end latency is under 500ms per frame', () async {
        // This test measures the throughput of the pure-Dart data path
        // (SequenceTranslator → Translation routing), excluding TFLite
        // inference latency which is bounded by the model spec (<50ms + <33ms).

        final stopwatch = Stopwatch()..start();

        // Simulate processing a batch of 10 gestures through the
        // translator (excluding real TFLite inference).
        final results = <Translation>[];
        for (int i = 0; i < 10; i++) {
          final gesture = Gesture(
            label: 'hola',
            confidence: 0.95,
            timestamp: DateTime.now(),
          );
          results.add(translator.processGesture(gesture));
        }

        stopwatch.stop();

        // Pure Dart processing for 10 gestures should be well under 500ms.
        expect(stopwatch.elapsedMilliseconds, lessThan(500),
            reason: 'gesture processing < 500 ms');
        expect(results.length, 10,
            reason: 'all 10 gestures produced a translation');
      });
    });
  });
}
