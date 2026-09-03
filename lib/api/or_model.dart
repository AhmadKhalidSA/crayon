import 'dart:convert';

enum Kind { image, video }

/// What a model can be asked to do. Derived from its declared capabilities,
/// never hardcoded per model.
/// Inpainting is deliberately absent: it is not a task, it is a tool applied
/// to an individual reference image, so a generation can mask one source and
/// leave another alone. The enum value is kept so older records still parse.
enum Task {
  textToImage,
  imageToImage,
  edit,
  inpaint,
  outpaint,
  textToVideo,
  imageToVideo,
  frames,
  refToVideo,
  videoToVideo,
  lipsync,
  upscaleVideo,
}

extension TaskX on Task {
  String get label => switch (this) {
        Task.textToImage => 'Text to image',
        Task.imageToImage => 'Image to image',
        Task.edit => 'Edit',
        Task.inpaint => 'Inpaint',
        Task.outpaint => 'Outpaint',
        Task.textToVideo => 'Text to video',
        Task.imageToVideo => 'Image to video',
        Task.frames => 'First / last frame',
        Task.refToVideo => 'Reference to video',
        Task.videoToVideo => 'Video to video',
        Task.lipsync => 'Avatar / lipsync',
        Task.upscaleVideo => 'Upscale',
      };

  String get short => switch (this) {
        Task.textToImage => 'T2I',
        Task.imageToImage => 'I2I',
        Task.edit => 'Edit',
        Task.inpaint => 'Inpaint',
        Task.outpaint => 'Outpaint',
        Task.textToVideo => 'T2V',
        Task.imageToVideo => 'I2V',
        Task.frames => 'Frames',
        Task.refToVideo => 'Ref',
        Task.videoToVideo => 'V2V',
        Task.lipsync => 'Avatar',
        Task.upscaleVideo => 'Upscale',
      };

  /// How many source images this task wants, and whether they are required.
  bool get needsImage => this == Task.imageToImage ||
      this == Task.edit ||
      this == Task.inpaint ||
      this == Task.outpaint ||
      this == Task.imageToVideo ||
      this == Task.frames ||
      this == Task.refToVideo ||
      this == Task.lipsync;

  bool get needsVideo => this == Task.videoToVideo || this == Task.upscaleVideo;


  bool get isVideo => index >= Task.textToVideo.index;
}

/// One declared parameter on an image model endpoint.
class ParamSpec {
  ParamSpec({required this.name, required this.type, this.values = const [], this.min, this.max});
  final String name;
  final String type; // enum | range | boolean
  final List<String> values;
  final num? min;
  final num? max;

  factory ParamSpec.fromJson(String name, Map<String, dynamic> j) => ParamSpec(
        name: name,
        type: (j['type'] ?? 'enum').toString(),
        values: ((j['values'] as List?) ?? const []).map((e) => e.toString()).toList(),
        min: j['min'] as num?,
        max: j['max'] as num?,
      );

  Map<String, dynamic> toJson() =>
      {'type': type, if (values.isNotEmpty) 'values': values, if (min != null) 'min': min, if (max != null) 'max': max};
}

class PriceLine {
  PriceLine(this.billable, this.unit, this.costUsd);
  final String billable;
  final String unit;
  final double costUsd;
  factory PriceLine.fromJson(Map<String, dynamic> j) => PriceLine(
      (j['billable'] ?? '').toString(), (j['unit'] ?? '').toString(), (j['cost_usd'] as num?)?.toDouble() ?? 0);
  Map<String, dynamic> toJson() => {'billable': billable, 'unit': unit, 'cost_usd': costUsd};
}

/// A model from /images/models or /videos/models, with its capabilities
/// flattened into something the UI can render directly.
class ORModel {
  ORModel({
    required this.id,
    required this.name,
    required this.kind,
    this.description = '',
    this.params = const {},
    this.pricing = const [],
    this.passthrough = const [],
    this.resolutions = const [],
    this.aspectRatios = const [],
    this.durations = const [],
    this.frameImages = const [],
    this.pricingSkus = const {},
    this.generateAudio = false,
    this.seed = false,
    this.upscaleMin,
    this.upscaleMax,
    this.creativity = false,
    this.created = 0,
  });

  final String id;
  final String name;
  final Kind kind;
  final String description;
  final int created;

  /// Which backend this model belongs to ('openrouter').
  /// Stamped when a catalogue is loaded; drives which backend a generation runs
  /// on and the provider filter in the picker. Mutable so a whole list can be
  /// tagged after it is built without threading it through every factory.
  String provider = 'openrouter';

  // image side
  final Map<String, ParamSpec> params;
  final List<PriceLine> pricing;

  // shared / video side
  final List<String> passthrough;
  final List<String> resolutions;
  final List<String> aspectRatios;
  final List<int> durations;
  final List<String> frameImages;
  final Map<String, String> pricingSkus;
  final bool generateAudio;
  final bool seed;
  final num? upscaleMin;
  final num? upscaleMax;
  final bool creativity;

  // ---------- derived ----------

  /// "bytedance-seed" -> "ByteDance Seed"
  String get brand {
    final raw = id.split('/').first;
    if (name.contains(':')) return name.split(':').first.trim();
    return raw.split(RegExp(r'[-_]')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  /// "ByteDance Seed: Seedream 4.5" -> "Seedream 4.5"
  String get shortName => name.contains(':') ? name.split(':').last.trim() : name;

  int get maxRefs {
    if (kind == Kind.image) return (params['input_references']?.max ?? 0).toInt();
    // video models take references when their price sheet mentions them,
    // or when the provider exposes an images passthrough.
    final hasRefSku = pricingSkus.keys.any((k) => k.contains('reference'));
    final hasImgPass = passthrough.any((p) => p == 'images' || p == 'image_style_references');
    return (hasRefSku || hasImgPass) ? 4 : 0;
  }

  int get maxN => (params['n']?.max ?? 1).toInt();

  /// Some models (Recraft's Styles line) declare input_references.min = 1,
  /// which means they physically cannot do text-to-image: a reference is
  /// mandatory. Honour it, or the studio offers a task the API will reject.
  int get minRefs => kind == Kind.image ? (params['input_references']?.min ?? 0).toInt() : 0;

  bool get requiresReference => minRefs >= 1;

  bool get supportsVideoInput =>
      pricingSkus.keys.any((k) => k.contains('video_input')) ||
      passthrough.any((p) => p == 'video' || p == 'videos');

  bool get isAvatar => id.contains('avatar') || id.contains('heygen');
  bool get isUpscaler => id.contains('upscale');

  bool get supportsFirstFrame => frameImages.contains('first_frame');
  bool get supportsLastFrame => frameImages.contains('last_frame');

  List<String> get imageAspects => params['aspect_ratio']?.values ?? const [];
  List<String> get imageResolutions => params['resolution']?.values ?? const [];
  List<String> get qualities => params['quality']?.values ?? const [];
  List<String> get backgrounds => params['background']?.values ?? const [];
  List<String> get outputFormats => params['output_format']?.values ?? const [];
  bool get supportsSeed => kind == Kind.image ? params.containsKey('seed') : seed;

  /// The task tabs this model should show, in display order.
  List<Task> get tasks {
    if (kind == Kind.image) {
      final t = <Task>[];
      if (!requiresReference) t.add(Task.textToImage);
      if (maxRefs >= 1) {
        t.add(Task.imageToImage);
        t.add(Task.edit);
        t.add(Task.outpaint);
      }
      return t.isEmpty ? [Task.textToImage] : t;
    }
    if (isUpscaler) return [Task.upscaleVideo];
    if (isAvatar) return [Task.lipsync];
    final t = <Task>[];
    t.add(Task.textToVideo);
    if (supportsFirstFrame) t.add(Task.imageToVideo);
    if (supportsFirstFrame && supportsLastFrame) t.add(Task.frames);
    if (maxRefs > 0) t.add(Task.refToVideo);
    if (supportsVideoInput) t.add(Task.videoToVideo);
    return t;
  }

  /// Cheapest advertised unit price, used for sorting and the model list.
  double get lowestPrice {
    final vals = <double>[
      ...pricing.map((p) => p.costUsd),
      ...pricingSkus.values.map((v) => double.tryParse(v) ?? 0),
    ].where((v) => v > 0).toList();
    if (vals.isEmpty) return 0;
    vals.sort();
    return vals.first;
  }

  /// Human price label for the model list.
  String get priceLabel {
    if (kind == Kind.image) {
      final perImage = pricing.where((p) => p.unit == 'image').toList();
      if (perImage.isNotEmpty) {
        final v = perImage.map((e) => e.costUsd).reduce((a, b) => a < b ? a : b);
        return '\$${_trim(v)} / image';
      }
      final mp = pricing.where((p) => p.unit == 'megapixel').toList();
      if (mp.isNotEmpty) {
        final v = mp.map((e) => e.costUsd).reduce((a, b) => a < b ? a : b);
        return '\$${_trim(v)} / MP';
      }
      final tok = pricing.where((p) => p.unit == 'token' && p.billable.contains('output')).toList();
      if (tok.isNotEmpty) {
        // ~1120-4096 output tokens per image in practice; quote a typical image.
        final v = tok.map((e) => e.costUsd).reduce((a, b) => a < b ? a : b);
        return '~\$${_trim(v * 1120)} / image';
      }
      return 'metered';
    }
    // video: quote per second at the cheapest resolution
    final perSec = <double>[];
    pricingSkus.forEach((k, v) {
      final d = double.tryParse(v);
      if (d == null) return;
      if (k.contains('duration_seconds')) perSec.add(d);
      if (k.startsWith('cents_per_second')) perSec.add(d / 100);
    });
    if (perSec.isNotEmpty) {
      perSec.sort();
      return '\$${_trim(perSec.first)} / sec';
    }
    final tokens = pricingSkus.entries.where((e) => e.key.contains('token')).toList();
    if (tokens.isNotEmpty) return 'metered / token';
    return 'metered';
  }

  static String _trim(double v) {
    if (v >= 1) return v.toStringAsFixed(2);
    if (v >= 0.01) return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  // ---------- parsing ----------

  /// From /api/v1/images/models list item merged with its /endpoints payload.
  factory ORModel.image(Map<String, dynamic> listItem, Map<String, dynamic>? endpoints) {
    final eps = (endpoints?['endpoints'] as List?) ?? const [];
    // Merge every endpoint's capabilities so the union is offered; providers
    // differ (one gemini endpoint allows 4K, another does not).
    final params = <String, ParamSpec>{};
    final pricing = <PriceLine>[];
    final pass = <String>{};
    for (final e in eps) {
      final m = e as Map<String, dynamic>;
      final sp = (m['supported_parameters'] as Map?)?.cast<String, dynamic>() ?? const {};
      sp.forEach((k, v) {
        final spec = ParamSpec.fromJson(k, (v as Map).cast<String, dynamic>());
        final prev = params[k];
        if (prev == null) {
          params[k] = spec;
        } else {
          // union of enum values, widest range
          final vals = <String>{...prev.values, ...spec.values}.toList();
          params[k] = ParamSpec(
            name: k,
            type: spec.type,
            values: vals,
            min: prev.min == null || spec.min == null ? (prev.min ?? spec.min) : (prev.min! < spec.min! ? prev.min : spec.min),
            max: prev.max == null || spec.max == null ? (prev.max ?? spec.max) : (prev.max! > spec.max! ? prev.max : spec.max),
          );
        }
      });
      for (final p in (m['pricing'] as List?) ?? const []) {
        pricing.add(PriceLine.fromJson((p as Map).cast<String, dynamic>()));
      }
      for (final p in (m['allowed_passthrough_parameters'] as List?) ?? const []) {
        pass.add(p.toString());
      }
    }
    return ORModel(
      id: listItem['id'].toString(),
      name: (listItem['name'] ?? listItem['id']).toString(),
      description: (listItem['description'] ?? '').toString(),
      created: (listItem['created'] as num?)?.toInt() ?? 0,
      kind: Kind.image,
      params: params,
      pricing: pricing,
      passthrough: pass.toList(),
    );
  }

  /// From /api/v1/videos/models (already flat, no endpoints call needed).
  factory ORModel.video(Map<String, dynamic> j) {
    final up = j['upscale_factor'];
    return ORModel(
      id: j['id'].toString(),
      name: (j['name'] ?? j['id']).toString(),
      description: (j['description'] ?? '').toString(),
      created: (j['created'] as num?)?.toInt() ?? 0,
      kind: Kind.video,
      resolutions: ((j['supported_resolutions'] as List?) ?? const []).map((e) => e.toString()).toList(),
      aspectRatios: ((j['supported_aspect_ratios'] as List?) ?? const []).map((e) => e.toString()).toList(),
      durations: ((j['supported_durations'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      frameImages: ((j['supported_frame_images'] as List?) ?? const []).map((e) => e.toString()).toList(),
      pricingSkus: ((j['pricing_skus'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
      passthrough:
          ((j['allowed_passthrough_parameters'] as List?) ?? const []).map((e) => e.toString()).toList(),
      generateAudio: j['generate_audio'] == true,
      seed: j['seed'] == true,
      upscaleMin: up is Map ? up['min'] as num? : null,
      upscaleMax: up is Map ? up['max'] as num? : null,
      creativity: j['creativity'] != null,
    );
  }

  // ---------- cache serialisation ----------

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'provider': provider,
        'description': description,
        'created': created,
        'params': params.map((k, v) => MapEntry(k, v.toJson())),
        'pricing': pricing.map((e) => e.toJson()).toList(),
        'passthrough': passthrough,
        'resolutions': resolutions,
        'aspect_ratios': aspectRatios,
        'durations': durations,
        'frame_images': frameImages,
        'pricing_skus': pricingSkus,
        'generate_audio': generateAudio,
        'seed': seed,
        'upscale_min': upscaleMin,
        'upscale_max': upscaleMax,
        'creativity': creativity,
      };

  factory ORModel.fromCache(Map<String, dynamic> j) => ORModel(
        id: j['id'].toString(),
        name: j['name'].toString(),
        kind: j['kind'] == 'video' ? Kind.video : Kind.image,
        description: (j['description'] ?? '').toString(),
        created: (j['created'] as num?)?.toInt() ?? 0,
        params: ((j['params'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), ParamSpec.fromJson(k.toString(), (v as Map).cast<String, dynamic>()))),
        pricing: ((j['pricing'] as List?) ?? const [])
            .map((e) => PriceLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        passthrough: ((j['passthrough'] as List?) ?? const []).map((e) => e.toString()).toList(),
        resolutions: ((j['resolutions'] as List?) ?? const []).map((e) => e.toString()).toList(),
        aspectRatios: ((j['aspect_ratios'] as List?) ?? const []).map((e) => e.toString()).toList(),
        durations: ((j['durations'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        frameImages: ((j['frame_images'] as List?) ?? const []).map((e) => e.toString()).toList(),
        pricingSkus: ((j['pricing_skus'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        generateAudio: j['generate_audio'] == true,
        seed: j['seed'] == true,
        upscaleMin: j['upscale_min'] as num?,
        upscaleMax: j['upscale_max'] as num?,
        creativity: j['creativity'] == true,
      )..provider = (j['provider'] ?? 'openrouter').toString();

  static String encodeList(List<ORModel> m) => jsonEncode(m.map((e) => e.toJson()).toList());
  static List<ORModel> decodeList(String s) =>
      (jsonDecode(s) as List).map((e) => ORModel.fromCache((e as Map).cast<String, dynamic>())).toList();
}
