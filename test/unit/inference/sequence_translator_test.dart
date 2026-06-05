import 'package:flutter_test/flutter_test.dart';

import 'package:isla/inference/sequence_translator.dart';
import 'package:isla/models/gesture.dart';
import 'package:isla/models/translation.dart';

/// Helper to build a [Gesture] with a given label at an explicit timestamp
/// offset (milliseconds from epoch). Offsets let us test gap detection
/// without real time delays.
Gesture _g(String label, {int epochMs = 0}) => Gesture(
      label: label,
      confidence: 0.95,
      timestamp: DateTime.fromMillisecondsSinceEpoch(epochMs),
    );

void main() {
  group('SequenceTranslator', () {
    late SequenceTranslator translator;

    setUp(() {
      translator = SequenceTranslator(
        windowDuration: const Duration(seconds: 2),
      );
    });

    tearDown(() {
      translator.dispose();
    });

    // -------------------------------------------------------------------------
    // Happy path — streaming output grows with each gesture
    // -------------------------------------------------------------------------
    test('streaming output grows partialText progressively '
        '(spec: sequence-translator streaming happy)', () {
      // Gestures at 100 ms intervals → comfortably within the 2s window.
      final t1 = translator.processGesture(_g('hola', epochMs: 0));
      expect(t1.isFinal, isFalse);
      expect(t1.partialText, 'hola',
          reason: 'single gesture → isolated meaning');
      expect(t1.confirmedText, '',
          reason: 'nothing confirmed in the first window');

      final t2 = translator.processGesture(_g('gracias', epochMs: 100));
      expect(t2.isFinal, isFalse);
      expect(t2.partialText, 'hola gracias',
          reason: 'two word-gestures → space separated');

      final t3 = translator.processGesture(_g('por_favor', epochMs: 200));
      expect(t3.isFinal, isFalse);
      expect(t3.partialText, 'hola gracias por favor',
          reason: 'three word-gestures accumulate');
    });

    // -------------------------------------------------------------------------
    // Window expiry — gap > 2 s triggers flush
    // -------------------------------------------------------------------------
    test('gap > windowDuration flushes on output stream with isFinal=true '
        '(spec: sequence-translator window expiry edge)', () async {
      // processGesture() always returns isFinal=false. The isFinal=true
      // Translation is EMITTED on the output stream by _flush().
      // See: SequenceTranslator.processGesture() — return value vs. emit.
      final onStream = <Translation>[];
      translator.output.listen(onStream.add);

      // First gesture at t=0.
      translator.processGesture(_g('hola', epochMs: 0));

      // Gesture at t=2500 ms → gap = 2500 ms > 2000 ms window → flushes.
      translator.processGesture(_g('gracias', epochMs: 2500));

      // Stream order:
      //   [0] partial:'hola', isFinal:false — first gesture
      //   [1]   -> isFinal:true, confirmed:'hola'  — from _flush()
      //   [2] partial:'gracias', isFinal:false — second gesture
      await Future<void>.delayed(Duration.zero);
      expect(onStream.length, 3);

      expect(onStream[0].isFinal, isFalse);
      expect(onStream[0].partialText, 'hola');

      expect(onStream[1].isFinal, isTrue,
          reason: 'gap triggers flush → final translation on stream');
      expect(onStream[1].confirmedText, 'hola',
          reason: 'first window confirmed as "hola"');
      expect(onStream[1].partialText, '');
    });

    // -------------------------------------------------------------------------
    // Window expiry via explicit flush after gap
    // -------------------------------------------------------------------------
    test('after gap, new gesture starts a fresh window with confirmed text',
        () {
      // Same scenario as above but verify via flush() instead of stream.
      translator.processGesture(_g('hola', epochMs: 0));
      translator.processGesture(_g('gracias', epochMs: 2500));

      // The second gesture triggered a flush internally, so confirmed text
      // has been updated even if the returned Translation is not isFinal.
      final flushed = translator.flush();
      expect(flushed.confirmedText, 'hola gracias',
          reason: 'both gestures accumulated in confirmed');
    });

    // -------------------------------------------------------------------------
    // Explicit flush
    // -------------------------------------------------------------------------
    test('explicit flush promotes partial to confirmed and resets', () {
      translator.processGesture(_g('hola', epochMs: 0));
      translator.processGesture(_g('gracias', epochMs: 100));

      final flushed = translator.flush();

      expect(flushed.isFinal, isTrue);
      expect(flushed.confirmedText, 'hola gracias');
      expect(flushed.partialText, '');
    });

    // -------------------------------------------------------------------------
    // Single gesture → isolated meaning
    // -------------------------------------------------------------------------
    test('single gesture returns its isolated meaning '
        '(spec: sequence-translator edge)', () {
      final t = translator.processGesture(_g('agua', epochMs: 0));
      expect(t.partialText, 'agua');
      expect(t.isFinal, isFalse);
    });

    // -------------------------------------------------------------------------
    // Filter non-gestures
    // -------------------------------------------------------------------------
    test('unknown gestures are silently skipped', () {
      translator.processGesture(
        _g('unknown', epochMs: 0),
      );

      // The buffer should still be empty — unknown doesn't count.
      final t2 = translator.processGesture(_g('hola', epochMs: 100));
      expect(t2.partialText, 'hola',
          reason: 'hola is the first meaningful gesture');
    });

    test('model_not_ready gestures are silently skipped', () {
      translator.processGesture(
        _g('model_not_ready', epochMs: 0),
      );

      final t2 = translator.processGesture(_g('si', epochMs: 100));
      expect(t2.partialText, 'sí');
    });

    // -------------------------------------------------------------------------
    // Letter sequence → joined uppercase word
    // -------------------------------------------------------------------------
    test('letter sequence is decoded as joined uppercase word', () {
      // H → O → L → A within the same window.
      final t1 = translator.processGesture(_g('H', epochMs: 0));
      expect(t1.partialText, 'h');

      final t2 = translator.processGesture(_g('O', epochMs: 100));
      expect(t2.partialText, 'HO');

      final t3 = translator.processGesture(_g('L', epochMs: 200));
      expect(t3.partialText, 'HOL');

      final t4 = translator.processGesture(_g('A', epochMs: 300));
      expect(t4.partialText, 'HOLA');
    });

    // -------------------------------------------------------------------------
    // Reset clears all state
    // -------------------------------------------------------------------------
    test('reset clears buffer and confirmed text', () {
      translator.processGesture(_g('hola', epochMs: 0));
      final flushed = translator.flush();
      expect(flushed.confirmedText, 'hola');

      translator.reset();

      // After reset, everything should be empty.
      final t = translator.processGesture(_g('gracias', epochMs: 500));
      expect(t.confirmedText, '',
          reason: 'confirmed text cleared by reset');
      expect(t.partialText, 'gracias',
          reason: 'fresh window starts with new gesture');
    });

    // -------------------------------------------------------------------------
    // Emit on stream
    // -------------------------------------------------------------------------
    test('emits translations on output stream', () async {
      final translations = <Translation>[];
      translator.output.listen(translations.add);

      translator.processGesture(_g('hola', epochMs: 0));
      await Future<void>.delayed(Duration.zero);

      expect(translations.length, 1);
      expect(translations[0].partialText, 'hola');
    });
  });
}
