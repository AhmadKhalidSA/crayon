import '../api/or_model.dart';

/// A price estimate that knows whether it is trustworthy.
///
/// Some models bill per image or per second, which is exactly computable.
/// Others bill per output token, where the token count depends on what the
/// model decides to render. Rather than invent a number, those come back
/// [exact] = false, or with [unknown] set so the UI can say "metered".
class Estimate {
  const Estimate(this.usd, {this.exact = true, this.unknown = false, this.note});
  final double usd;
  final bool exact;
  final bool unknown;
  final String? note;

  static const metered = Estimate(0, exact: false, unknown: true, note: 'billed by the provider');

  String get label {
    if (unknown) return 'metered';
    final s = usd >= 1 ? usd.toStringAsFixed(2) : usd.toStringAsFixed(usd >= 0.01 ? 3 : 4);
    final trimmed = s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
    return '${exact ? '' : '~'}\$$trimmed';
  }
}

/// Megapixels for an aspect ratio at a resolution tier, used by the
/// per-megapixel models (Flux).
double _megapixels(String? resolution, String? aspect) {
  final tier = switch (resolution) {
    '512' => 512 * 512,
    '1K' => 1024 * 1024,
    '2K' => 2048 * 2048,
    '4K' => 4096 * 4096,
    _ => 1024 * 1024,
  };
  // Aspect changes the shape, not meaningfully the pixel budget these
  // providers bill for, so the tier area is the right basis.
  return tier / 1000000.0;
}

class Estimator {
  /// Cost of one image generation request.
  static Estimate image(ORModel m, {int n = 1, String? resolution, String? aspect, String? quality}) {
    if (m.pricing.isEmpty) return Estimate.metered;

    final perImage = m.pricing.where((p) => p.unit == 'image' && p.costUsd > 0).toList();
    if (perImage.isNotEmpty) {
      // Providers list several tiers (1K/2K/4K). Pick by resolution index when
      // the counts line up, otherwise quote the cheapest and mark it inexact.
      if (perImage.length == 1) {
        return Estimate(perImage.first.costUsd * n);
      }
      final sorted = [...perImage]..sort((a, b) => a.costUsd.compareTo(b.costUsd));
      final tiers = m.imageResolutions;
      if (tiers.isNotEmpty && resolution != null) {
        final idx = tiers.indexOf(resolution);
        if (idx >= 0 && idx < sorted.length) return Estimate(sorted[idx].costUsd * n);
      }
      return Estimate(sorted.first.costUsd * n, exact: false);
    }

    final perMp = m.pricing.where((p) => p.unit == 'megapixel' && p.costUsd > 0).toList();
    if (perMp.isNotEmpty) {
      final mp = _megapixels(resolution, aspect);
      final rate = perMp.map((e) => e.costUsd).reduce((a, b) => a < b ? a : b);
      return Estimate(rate * mp * n, exact: false);
    }

    // Token-billed (Google, OpenAI). Output image token counts are stable per
    // family in practice, so this is a measured approximation, not a guess:
    // Gemini image output measured at ~1120 tokens for 1K, ~4096 for Flux-class.
    final outTok = m.pricing
        .where((p) => p.unit == 'token' && (p.billable.contains('output') || p.billable.contains('image')))
        .toList();
    if (outTok.isNotEmpty) {
      final rate = outTok.map((e) => e.costUsd).reduce((a, b) => a > b ? a : b);
      final tokens = switch (resolution) {
        '4K' => 4096.0,
        '2K' => 2048.0,
        _ => 1120.0,
      };
      return Estimate(rate * tokens * n, exact: false, note: 'token billed');
    }
    return Estimate.metered;
  }

  /// Cost of one video generation request.
  static Estimate video(ORModel m, {required int seconds, String? resolution, bool audio = true}) {
    final skus = m.pricingSkus;
    if (skus.isEmpty) return Estimate.metered;

    double? num_(String k) => double.tryParse(skus[k] ?? '');

    // 1. per-second SKUs, most specific key first.
    //
    // MEASURED 2026-08-27: Kling v3.0 Std was asked for duration=3 and billed
    // $0.63, which is 5 x its $0.126 with-audio second rate. The provider
    // applied a 5 second minimum that appears nowhere in its pricing_skus. So
    // per-second maths is a FLOOR, not a guarantee, and these estimates are
    // reported as approximate. The figure the Spend screen totals is always the
    // real cost read back from the API, never this.
    final res = (resolution ?? '').toLowerCase();
    final candidates = <String>[
      if (audio && res.isNotEmpty) 'duration_seconds_with_audio_$res',
      if (audio) 'duration_seconds_with_audio',
      if (!audio && res.isNotEmpty) 'duration_seconds_without_audio_$res',
      if (!audio) 'duration_seconds_without_audio',
      if (res.isNotEmpty) 'duration_seconds_$res',
      'duration_seconds',
    ];
    for (final k in candidates) {
      final v = num_(k);
      if (v != null) {
        return Estimate(v * seconds, exact: false, note: 'providers may bill a minimum length');
      }
    }

    // 2. cents-per-second SKUs (Runway, Flux video)
    final centKeys = <String>[
      if (res.isNotEmpty) 'cents_per_second_output_$res',
      'cents_per_second_output',
    ];
    for (final k in centKeys) {
      final v = num_(k);
      if (v != null) {
        var usd = v / 100 * seconds;
        final minC = num_('minimum_cents_per_generation');
        if (minC != null && usd < minC / 100) usd = minC / 100;
        return Estimate(usd, exact: false, note: 'providers may bill a minimum length');
      }
    }
    for (final e in skus.entries) {
      if (e.key.startsWith('cents_per_video_output_second')) {
        if (res.isEmpty || e.key.endsWith(res)) {
          final v = double.tryParse(e.value);
          if (v != null) return Estimate(v / 100 * seconds, exact: res.isNotEmpty);
        }
      }
    }

    // 3. token-billed video (Seedance). Tokens depend on frames x pixels, which
    // the provider computes server-side. Do not fake a number.
    if (skus.keys.any((k) => k.contains('token'))) {
      return const Estimate(0, exact: false, unknown: true, note: 'token billed, varies with resolution');
    }
    return Estimate.metered;
  }
}
