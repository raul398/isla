import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isla/models/translation.dart';
import 'package:isla/providers/caption_provider.dart';
import 'package:isla/providers/inference_provider.dart';

void main() {
  group('CaptionProvider', () {
    late StreamController<Translation> inferenceController;
    late ProviderContainer container;

    /// Builds a [ProviderContainer] that overrides the real inference provider
    /// with a controllable stream so tests don't need TFLite models.
    ProviderContainer _createContainer() {
      inferenceController = StreamController<Translation>.broadcast();
      return ProviderContainer(
        overrides: [
          inferenceStreamProvider.overrideWithProvider(
            StreamProvider<Translation>((ref) => inferenceController.stream),
          ),
        ],
      );
    }

    setUp(() {
      container = _createContainer();
    });

    tearDown(() async {
      await inferenceController.close();
      container.dispose();
    });

    /// Feed a [Translation] into the inference stream and wait for Riverpod
    /// to propagate the async value to [CaptionProvider].
    Future<void> emit(Translation t) async {
      inferenceController.add(t);
      // StreamProvider delivers events asynchronously — flush the microtask
      // queue so the CaptionProvider's ref.listen callback fires.
      await Future<void>.delayed(Duration.zero);
    }

    /// Returns the current [TranslationState] from the provider.
    TranslationState readState() {
      final async = container.read(captionProvider);
      return async.asData!.value;
    }

    // -------------------------------------------------------------------------
    // Happy path — 5 consistent frames promote partial → confirmed
    // -------------------------------------------------------------------------
    test('5 consecutive frames with the same partial text confirm the gesture '
        '(spec: streaming-captions progressive-confirmation happy)', () async {
      expect(readState().isEmpty, isTrue,
          reason: 'starts empty');

      // Send 4 consistent frames — still in grey zone.
      for (int i = 0; i < 4; i++) {
        await emit(Translation(
            partialText: 'hola', confirmedText: '', isFinal: false));
      }

      expect(readState().confirmedText, '',
          reason: 'not yet confirmed (need 5 frames)');
      expect(readState().partialText, 'hola',
          reason: 'still in partial/grey zone');

      // Frame #5 crosses the threshold.
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));

      expect(readState().confirmedText, 'hola',
          reason: 'now promoted to confirmed/white');
      expect(readState().partialText, '',
          reason: 'partial cleared after confirmation');
    });

    // -------------------------------------------------------------------------
    // Inconsistent frames — never reaches threshold → stays grey
    // -------------------------------------------------------------------------
    test('inconsistent frames never confirm (all grey) '
        '(spec: streaming-captions progressive-confirmation edge)', () async {
      // Mix different partial texts — none reaches 5 consecutive matches.
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));
      await emit(Translation(
          partialText: 'gracias', confirmedText: '', isFinal: false));
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));
      await emit(Translation(
          partialText: 'adios', confirmedText: '', isFinal: false));

      expect(readState().confirmedText, '',
          reason: 'nothing confirmed');
      expect(readState().partialText, 'adios',
          reason: 'latest is the current partial');
    });

    // -------------------------------------------------------------------------
    // isFinal — promotes to confirmed immediately
    // -------------------------------------------------------------------------
    test('isFinal immediately promotes partial to confirmed', () async {
      await emit(Translation(
        partialText: 'hola',
        confirmedText: '',
        isFinal: true,
      ));

      expect(readState().confirmedText, 'hola',
          reason: 'promoted instantly');
      expect(readState().partialText, '',
          reason: 'partial cleared');
      expect(readState().isFinal, isTrue);
    });

    // -------------------------------------------------------------------------
    // Timeout — 5s idle clears captions
    // -------------------------------------------------------------------------
    test('idle timeout clears confirmed and partial text after 5s '
        '(spec: streaming-captions empty-state happy)', () async {
      // Seed 5 consistent frames to confirm "hola".
      for (int i = 0; i < 5; i++) {
        await emit(Translation(
            partialText: 'hola', confirmedText: '', isFinal: false));
      }

      expect(readState().confirmedText, 'hola',
          reason: 'confirmed before timeout');

      // Wait past the 5-second idle timeout.
      await Future<void>.delayed(const Duration(seconds: 6));

      expect(readState().isEmpty, isTrue,
          reason: 'cleared by idle timeout');
    });

    // -------------------------------------------------------------------------
    // Empty frame — partialText empty resets confirmation buffer
    // -------------------------------------------------------------------------
    test('empty partial text resets the confirmation buffer', () async {
      // Build up 3 frames of "hola".
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));

      // Now send an empty translation (e.g. between gesture windows).
      await emit(Translation(
          partialText: '', confirmedText: '', isFinal: false));

      // The confirmation buffer was cleared — need 5 more.
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: false));

      expect(readState().confirmedText, '',
          reason: 'buffer was reset, needs 5 full frames again');
      expect(readState().partialText, 'hola',
          reason: 'still in grey zone');
    });

    // -------------------------------------------------------------------------
    // Error state — propagates from inference stream
    // -------------------------------------------------------------------------
    test('error from inference stream sets error state', () async {
      inferenceController.addError(Exception('Model crash'));
      await Future<void>.delayed(Duration.zero);

      final async = container.read(captionProvider);
      expect(async.hasError, isTrue);
    });

    // -------------------------------------------------------------------------
    // IsFinal appends to existing confirmed text
    // -------------------------------------------------------------------------
    test('multiple isFinal events accumulate confirmed text', () async {
      await emit(Translation(
          partialText: 'hola', confirmedText: '', isFinal: true));
      expect(readState().confirmedText, 'hola');

      await emit(Translation(
          partialText: 'gracias', confirmedText: '', isFinal: true));
      expect(readState().confirmedText, 'hola gracias',
          reason: 'space-separated accumulation');
    });
  });
}
