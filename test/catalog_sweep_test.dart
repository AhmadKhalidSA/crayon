import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/api/or_model.dart';
import 'package:crayon/core/estimate.dart';

/// Runs the real bundled catalogue through the same derivation the studio uses,
/// so a malformed or unusual model surfaces here rather than on the phone.
void main() {
  late List<ORModel> models;

  setUpAll(() {
    final raw = File('assets/catalog.json').readAsStringSync();
    models = (jsonDecode(raw) as List)
        .map((e) => ORModel.fromCache((e as Map).cast<String, dynamic>()))
        .toList();
  });

  test('the bundled snapshot has both kinds', () {
    expect(models.length, greaterThan(60));
    expect(models.where((m) => m.kind == Kind.image).length, greaterThan(40));
    expect(models.where((m) => m.kind == Kind.video).length, greaterThan(20));
  });

  test('every model derives at least one task', () {
    for (final m in models) {
      expect(m.tasks, isNotEmpty, reason: '${m.id} produced no task');
    }
  });

  test('every model produces a usable display name and price label', () {
    for (final m in models) {
      expect(m.shortName.trim(), isNotEmpty, reason: m.id);
      expect(m.brand.trim(), isNotEmpty, reason: m.id);
      expect(m.priceLabel.trim(), isNotEmpty, reason: m.id);
      // a price label must never render a raw exponent at the user
      expect(m.priceLabel.contains('e-'), isFalse, reason: '${m.id} -> ${m.priceLabel}');
    }
  });

  test('no estimate is negative, NaN or infinite for any real model', () {
    for (final m in models) {
      if (m.kind == Kind.image) {
        for (final res in [null, ...m.imageResolutions]) {
          final e = Estimator.image(m, n: 2, resolution: res, aspect: '1:1');
          expect(e.usd.isFinite, isTrue, reason: '${m.id} res=$res');
          expect(e.usd, greaterThanOrEqualTo(0), reason: '${m.id} res=$res');
        }
      } else {
        final durations = m.durations.isEmpty ? [5] : m.durations;
        for (final d in [durations.first, durations.last]) {
          for (final res in [null, ...m.resolutions]) {
            final e = Estimator.video(m, seconds: d, resolution: res);
            expect(e.usd.isFinite, isTrue, reason: '${m.id} ${d}s $res');
            expect(e.usd, greaterThanOrEqualTo(0), reason: '${m.id} ${d}s $res');
          }
        }
      }
    }
  });

  test('video tasks match the frames each model actually declares', () {
    for (final m in models.where((e) => e.kind == Kind.video)) {
      if (m.isUpscaler || m.isAvatar) continue;
      expect(m.tasks.contains(Task.imageToVideo), m.supportsFirstFrame, reason: m.id);
      expect(m.tasks.contains(Task.frames), m.supportsFirstFrame && m.supportsLastFrame,
          reason: m.id);
    }
  });

  test('image models that mandate a reference never offer text to image', () {
    final mandatory = models.where((m) => m.kind == Kind.image && m.requiresReference).toList();
    expect(mandatory, isNotEmpty, reason: 'expected the Recraft Styles line to require a reference');
    for (final m in mandatory) {
      expect(m.tasks.contains(Task.textToImage), isFalse, reason: m.id);
    }
  });

  test('the whole snapshot survives a cache round trip', () {
    final back = ORModel.decodeList(ORModel.encodeList(models));
    expect(back.length, models.length);
    for (var i = 0; i < models.length; i++) {
      expect(back[i].id, models[i].id);
      expect(back[i].tasks, models[i].tasks, reason: models[i].id);
      expect(back[i].priceLabel, models[i].priceLabel, reason: models[i].id);
    }
  });
}
