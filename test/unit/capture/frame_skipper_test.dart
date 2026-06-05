import 'package:flutter_test/flutter_test.dart';

import 'package:isla/capture/frame_skipper.dart';

void main() {
  group('FrameSkipper', () {
    late FrameSkipper skipper;

    setUp(() {
      skipper = FrameSkipper();
    });

    // -------------------------------------------------------------------------
    // Happy path — skip=2 means 1 in 3 passes
    // -------------------------------------------------------------------------
    test(
        'skip=2 processes 1 out of every 3 frames (spec: camera-capture happy)',
        () {
      // Pattern: true, false, false, true, false, false, ...
      expect(skipper.shouldProcessFrame(), isTrue, reason: 'frame 1 passes');
      expect(skipper.shouldProcessFrame(), isFalse, reason: 'frame 2 skipped');
      expect(skipper.shouldProcessFrame(), isFalse, reason: 'frame 3 skipped');

      expect(skipper.shouldProcessFrame(), isTrue, reason: 'frame 4 passes');
      expect(skipper.shouldProcessFrame(), isFalse, reason: 'frame 5 skipped');
      expect(skipper.shouldProcessFrame(), isFalse, reason: 'frame 6 skipped');

      expect(skipper.shouldProcessFrame(), isTrue, reason: 'frame 7 passes');
    });

    // -------------------------------------------------------------------------
    // Throttle — adjustForThermal reduces skip when FPS < 8
    // -------------------------------------------------------------------------
    test('adjustForThermal reduces skip factor when FPS < 8 '
        '(spec: camera-capture thermal edge)', () {
      expect(skipper.skipFactor, 2);
      skipper.adjustForThermal(7.0); // below threshold
      expect(skipper.skipFactor, 1, reason: 'skip factor reduced to 1');
    });

    test('adjustForThermal does NOT change skip factor when FPS >= 8', () {
      skipper.adjustForThermal(10.0);
      expect(skipper.skipFactor, 2);

      skipper.adjustForThermal(8.0);
      expect(skipper.skipFactor, 2, reason: 'exactly 8 is still OK');
    });

    // -------------------------------------------------------------------------
    // Reset — restores initial state
    // -------------------------------------------------------------------------
    test('reset restores initial skip factor and counter', () {
      skipper.shouldProcessFrame(); // counter → 1
      skipper.shouldProcessFrame(); // counter → 2
      skipper.adjustForThermal(5.0); // skipFactor → 1

      skipper.reset();

      expect(skipper.skipFactor, 2, reason: 'skip restored to default');
      expect(skipper.shouldProcessFrame(), isTrue,
          reason: 'counter resets to 0 → passes');
    });

    // -------------------------------------------------------------------------
    // Edge — thermal adjustment is reversible
    // -------------------------------------------------------------------------
    test('skip factor can only decrease, not increase, via adjustForThermal', () {
      // Once reduced, adjustForThermal won't increase it back.
      skipper.adjustForThermal(5.0); // → 1
      expect(skipper.skipFactor, 1);

      skipper.adjustForThermal(15.0); // FPS is fine but factor stays
      expect(skipper.skipFactor, 1,
          reason: 'adjustForThermal only reduces, does not restore');
    });
  });
}
