import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/api/or_model.dart';
import 'package:crayon/core/estimate.dart';

void main() {
  group('image estimates', () {
    test('per-image pricing multiplies by the batch size', () {
      final m = ORModel(
        id: 'bytedance-seed/seedream-4.5',
        name: 'Seedream 4.5',
        kind: Kind.image,
        pricing: [PriceLine('output_image', 'image', 0.04)],
      );
      expect(Estimator.image(m, n: 1).usd, closeTo(0.04, 1e-9));
      expect(Estimator.image(m, n: 3).usd, closeTo(0.12, 1e-9));
      expect(Estimator.image(m, n: 1).exact, isTrue);
    });

    test('a model with no pricing reports metered rather than zero', () {
      final m = ORModel(id: 'x/y', name: 'X', kind: Kind.image);
      final e = Estimator.image(m);
      expect(e.unknown, isTrue);
      expect(e.label, 'metered');
    });

    test('token billed models are marked inexact', () {
      final m = ORModel(
        id: 'google/gemini-3-pro-image',
        name: 'Nano Banana Pro',
        kind: Kind.image,
        pricing: [PriceLine('output_image', 'token', 0.00012)],
      );
      final e = Estimator.image(m, resolution: '1K');
      expect(e.exact, isFalse);
      expect(e.usd, greaterThan(0));
      expect(e.label.startsWith('~\$'), isTrue);
    });
  });

  group('video estimates', () {
    test('per-second pricing scales with duration', () {
      final m = ORModel(
        id: 'kwaivgi/kling-v3.0-std',
        name: 'Kling 3.0 Std',
        kind: Kind.video,
        pricingSkus: {'duration_seconds': '0.084', 'duration_seconds_with_audio': '0.126'},
      );
      expect(Estimator.video(m, seconds: 5, audio: false).usd, closeTo(0.42, 1e-9));
      expect(Estimator.video(m, seconds: 5, audio: true).usd, closeTo(0.63, 1e-9));
      // measured: Kling billed a 5s minimum on a 3s request, so a per-second
      // figure is a floor and must never be presented as exact
      expect(Estimator.video(m, seconds: 3, audio: true).exact, isFalse);
      expect(Estimator.video(m, seconds: 3, audio: true).label.startsWith('~'), isTrue);
    });

    test('resolution specific SKUs win over the generic one', () {
      final m = ORModel(
        id: 'alibaba/wan-3.0',
        name: 'Wan 3.0',
        kind: Kind.video,
        pricingSkus: {
          'duration_seconds_480p': '0.05',
          'duration_seconds_720p': '0.1',
          'duration_seconds_1080p': '0.2',
        },
      );
      expect(Estimator.video(m, seconds: 10, resolution: '480p').usd, closeTo(0.5, 1e-9));
      expect(Estimator.video(m, seconds: 10, resolution: '1080p').usd, closeTo(2.0, 1e-9));
    });

    test('cents-per-second respects the minimum charge', () {
      final m = ORModel(
        id: 'runway/aleph-2',
        name: 'Aleph 2',
        kind: Kind.video,
        pricingSkus: {'cents_per_second_output': '28', 'minimum_cents_per_generation': '56'},
      );
      // 1 second would be $0.28 but the floor is $0.56
      expect(Estimator.video(m, seconds: 1).usd, closeTo(0.56, 1e-9));
      expect(Estimator.video(m, seconds: 5).usd, closeTo(1.40, 1e-9));
      expect(Estimator.video(m, seconds: 5).exact, isFalse);
    });

    test('token billed video refuses to invent a number', () {
      final m = ORModel(
        id: 'bytedance/seedance-2.5',
        name: 'Seedance 2.5',
        kind: Kind.video,
        pricingSkus: {'video_tokens': '0.0000107'},
      );
      final e = Estimator.video(m, seconds: 5);
      expect(e.unknown, isTrue);
      expect(e.label, 'metered');
    });
  });
}
