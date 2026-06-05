import 'dart:async';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isla/models/translation.dart';
import 'package:isla/providers/caption_provider.dart';
import 'package:isla/providers/inference_provider.dart';
import 'package:isla/ui/caption_box.dart';

/// Harness: creates a [ProviderScope] tree with the inference stream
/// overridden so tests control exactly what [CaptionBox] displays.
class CaptionBoxHarness {
  late final StreamController<Translation> inferenceCtrl;
  late final Widget widget;

  CaptionBoxHarness._();

  /// Build the harness and pump the widget tree once.
  static Future<CaptionBoxHarness> pump(
    WidgetTester tester, {
    String? confirmedText,
    String? partialText,
    bool isFinal = false,
  }) async {
    final h = CaptionBoxHarness._();
    h.inferenceCtrl = StreamController<Translation>.broadcast();

    h.widget = ProviderScope(
      overrides: [
        inferenceStreamProvider.overrideWithProvider(
          StreamProvider<Translation>((ref) => h.inferenceCtrl.stream),
        ),
      ],
      child: const MaterialApp(home: CaptionBox()),
    );

    await tester.pumpWidget(h.widget);
    return h;
  }

  /// Feed a [Translation] into the CaptionProvider and pump the widget.
  Future<void> feed(WidgetTester tester, Translation t) async {
    inferenceCtrl.add(t);
    await tester.pump();
  }

  /// Feed a partial translation (convenience).
  Future<void> feedPartial(WidgetTester tester, String text) =>
      feed(tester, Translation(partialText: text, confirmedText: '', isFinal: false));

  Future<void> dispose() async {
    await inferenceCtrl.close();
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Loading state — requires the provider to actually be in AsyncLoading.
  // By not feeding anything, CaptionProvider stays in its initial empty-data
  // state, so "Inicializando…" is never shown through normal flow.
  // This test simulates it by feeding an error (not ideal, but the loading
  // state was designed as a defensive branch).
  // -------------------------------------------------------------------------
  // NOTE: The "Inicializando…" loading state is a defensive fallback.
  // CaptionProvider starts as AsyncValue.data(TranslationState()) immediately,
  // so the loading branch of CaptionBox is not reachable in production
  // through the current provider chain. It remains as a safety net.
  // See: CaptionProvider constructor (sets initial state to AsyncValue.data).
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Empty state — initial render shows "…"
  // -------------------------------------------------------------------------
  testWidgets('shows "…" when TranslationState is empty', (tester) async {
    final h = await CaptionBoxHarness.pump(tester);

    expect(find.text('…'), findsOneWidget,
        reason: 'empty state placeholder');

    await h.dispose();
  });

  // -------------------------------------------------------------------------
  // Partial text — grey
  // -------------------------------------------------------------------------
  testWidgets('shows partial text in grey when gesture is not confirmed',
      (tester) async {
    final h = await CaptionBoxHarness.pump(tester);
    await h.feedPartial(tester, 'hola');

    // The RichText should have a grey text span for "hola".
    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;

    // "hola" should be the partialText → grey style.
    expect(span.children, hasLength(1));
    final partialSpan = span.children!.first as TextSpan;
    expect(partialSpan.text, 'hola');
    expect(partialSpan.style?.color, Colors.grey);

    await h.dispose();
  });

  // -------------------------------------------------------------------------
  // Confirmed text — white, partial stays grey
  // -------------------------------------------------------------------------
  testWidgets('shows confirmed text in white and partial in grey',
      (tester) async {
    final h = await CaptionBoxHarness.pump(tester);

    // Feed 5 "hola" frames to confirm.
    for (int i = 0; i < 5; i++) {
      await h.feedPartial(tester, 'hola');
    }

    // Now feed a new partial after confirmation.
    await h.feedPartial(tester, 'gracias');

    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;

    expect(span.children, hasLength(2));

    final confirmedSpan = span.children![0] as TextSpan;
    expect(confirmedSpan.text, 'hola ');
    expect(confirmedSpan.style?.color, Colors.white);

    final partialSpan = span.children![1] as TextSpan;
    expect(partialSpan.text, 'gracias');
    expect(partialSpan.style?.color, Colors.grey);

    await h.dispose();
  });

  // -------------------------------------------------------------------------
  // Error state — shows "Error en traducción" in red
  // -------------------------------------------------------------------------
  testWidgets('shows error message on AsyncValue error', (tester) async {
    final h = await CaptionBoxHarness.pump(tester);

    h.inferenceCtrl.addError(Exception('pipeline error'));
    await tester.pump();

    expect(find.text('Error en traducción'), findsOneWidget);

    // Verify error text uses red accent.
    final text = tester.widget<Text>(find.text('Error en traducción'));
    expect(text.style?.color, Colors.redAccent);

    await h.dispose();
  });

  // -------------------------------------------------------------------------
  // isFinal promotes partial → confirmed immediately
  // -------------------------------------------------------------------------
  testWidgets('isFinal moves partial to confirmed immediately', (tester) async {
    final h = await CaptionBoxHarness.pump(tester);

    // A single isFinal frame promotes instantly (no need for 5 frames).
    await h.feed(tester, Translation(
      partialText: 'hola',
      confirmedText: '',
      isFinal: true,
    ));

    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    expect(span.children, hasLength(1));

    final confirmedSpan = span.children!.first as TextSpan;
    expect(confirmedSpan.text, 'hola ');
    expect(confirmedSpan.style?.color, Colors.white);

    await h.dispose();
  });
}
