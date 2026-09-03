import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gen_backend.dart';
import 'or_model.dart';

export 'gen_backend.dart' show ORException, Credits, ImageResult, VideoJob, VideoResult;

/// Thin, honest wrapper over the three OpenRouter surfaces this app uses:
/// /images, /videos and /credits. No retries that could double-bill a
/// generation: only idempotent GETs are retried.
class OpenRouter implements GenBackend {
  OpenRouter(this.apiKey, {http.Client? client}) : _c = client ?? http.Client();

  static const base = 'https://openrouter.ai/api/v1';
  final String apiKey;
  final http.Client _c;

  @override
  String get id => 'openrouter';
  @override
  String get label => 'OpenRouter';
  @override
  bool get videoResumable => true;

  /// Image + video catalogue as one list.
  @override
  Future<List<ORModel>> listModels({void Function(int, int)? onProgress}) async {
    final vids = await videoModels();
    final imgs = await imageModels(onProgress: onProgress);
    return [...imgs, ...vids];
  }

  /// OpenRouter produces video through the resumable create/poll/download path,
  /// so this one-shot entry point is never used.
  @override
  Future<VideoResult> runVideo({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
    List<Map<String, String>> frames = const [],
    List<String> referenceDataUrls = const [],
    void Function(String note)? onNote,
    void Function(double progress)? onProgress,
  }) =>
      throw UnsupportedError('OpenRouter uses the resumable video path');

  Map<String, String> get _h => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/AhmadKhalidSA/crayon',
        'X-Title': 'Crayon',
      };

  Never _fail(http.Response r) {
    String msg = 'Request failed (${r.statusCode})';
    try {
      final j = jsonDecode(r.body);
      final e = j['error'];
      if (e is Map && e['message'] != null) {
        msg = e['message'].toString();
      } else if (e is Map && e['message'] == null && j['message'] != null) {
        msg = j['message'].toString();
      } else if (j['message'] != null) {
        msg = j['message'].toString();
      }
    } catch (_) {
      if (r.body.isNotEmpty) msg = r.body.substring(0, r.body.length.clamp(0, 300));
    }
    throw ORException(msg, code: r.statusCode);
  }

  Future<http.Response> _get(String path) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await _c.get(Uri.parse('$base$path'), headers: _h).timeout(const Duration(seconds: 45));
        if (r.statusCode >= 200 && r.statusCode < 300) return r;
        if (r.statusCode >= 500 || r.statusCode == 429) {
          last = ORException('HTTP ${r.statusCode}', code: r.statusCode);
        } else {
          _fail(r);
        }
      } on TimeoutException catch (e) {
        last = e;
      }
      await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    throw ORException('Network error: $last');
  }

  // ---------------- account ----------------

  @override
  Future<Credits> credits() async {
    final r = await _get('/credits');
    final d = jsonDecode(r.body)['data'] as Map<String, dynamic>;
    return Credits(
      (d['total_credits'] as num?)?.toDouble() ?? 0,
      (d['total_usage'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Cheap key validity probe used by the settings screen.
  @override
  Future<bool> validate() async {
    try {
      await credits();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------- catalogue ----------------

  Future<List<ORModel>> videoModels() async {
    final r = await _get('/videos/models');
    final list = (jsonDecode(r.body)['data'] as List).cast<Map<String, dynamic>>();
    return list.map(ORModel.video).toList();
  }

  /// Image models need a second call per model for their parameter schema.
  /// [onProgress] reports (done, total) so the UI can show a refresh bar.
  Future<List<ORModel>> imageModels({void Function(int, int)? onProgress}) async {
    final r = await _get('/images/models');
    final list = (jsonDecode(r.body)['data'] as List).cast<Map<String, dynamic>>();
    final out = List<ORModel?>.filled(list.length, null);
    var done = 0;
    const concurrency = 8;

    Future<void> worker(int start) async {
      for (var i = start; i < list.length; i += concurrency) {
        Map<String, dynamic>? ep;
        try {
          final er = await _get('/images/models/${list[i]['id']}/endpoints');
          ep = (jsonDecode(er.body)['data'] as Map?)?.cast<String, dynamic>() ??
              jsonDecode(er.body) as Map<String, dynamic>;
        } catch (_) {
          ep = null; // model still usable with defaults
        }
        out[i] = ORModel.image(list[i], ep);
        done++;
        onProgress?.call(done, list.length);
      }
    }

    await Future.wait(List.generate(concurrency, worker));
    return out.whereType<ORModel>().toList();
  }

  // ---------------- image generation ----------------

  /// POST /images. Returns every image the model produced plus the real cost
  /// OpenRouter charged, which is what the spend screen reports.
  /// [onNote]/[onProgress] are part of the [GenBackend] contract; OpenRouter's
  /// image call is a single POST with no intermediate progress, so it ignores
  /// them.
  @override
  Future<ImageResult> generateImage({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
    List<String> referenceDataUrls = const [],
    void Function(String note)? onNote,
    void Function(double progress)? onProgress,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      ...params,
      if (referenceDataUrls.isNotEmpty)
        'input_references': referenceDataUrls
            .map((u) => {
                  'type': 'image_url',
                  'image_url': {'url': u}
                })
            .toList(),
    };
    final r = await _c
        .post(Uri.parse('$base/images'), headers: _h, body: jsonEncode(body))
        .timeout(const Duration(minutes: 15));
    if (r.statusCode < 200 || r.statusCode >= 300) _fail(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final data = (j['data'] as List?) ?? const [];
    if (data.isEmpty) throw ORException('The model returned no image.');
    final bytes = <Uint8List>[];
    var media = 'image/png';
    for (final it in data) {
      final m = (it as Map).cast<String, dynamic>();
      final b64 = m['b64_json'];
      if (b64 is String && b64.isNotEmpty) {
        bytes.add(base64Decode(b64));
        media = (m['media_type'] ?? media).toString();
      } else if (m['url'] is String) {
        final dl = await _c.get(Uri.parse(m['url'] as String)).timeout(const Duration(minutes: 10));
        bytes.add(dl.bodyBytes);
      }
    }
    if (bytes.isEmpty) throw ORException('The model returned no image data.');
    final cost = ((j['usage'] as Map?)?['cost'] as num?)?.toDouble() ?? 0;
    return ImageResult(bytes, media, cost);
  }

  // ---------------- video generation ----------------

  /// POST /videos. Async: returns a job to poll.
  @override
  Future<VideoJob> createVideo({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
    List<Map<String, String>> frames = const [], // {url, frame_type}
    List<String> referenceDataUrls = const [],
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      ...params,
      if (frames.isNotEmpty)
        'frame_images': frames
            .map((f) => {
                  'type': 'image_url',
                  'image_url': {'url': f['url']},
                  'frame_type': f['frame_type'],
                })
            .toList(),
      if (referenceDataUrls.isNotEmpty)
        'input_references': referenceDataUrls
            .map((u) => {
                  'type': 'image_url',
                  'image_url': {'url': u}
                })
            .toList(),
    };
    final r = await _c
        .post(Uri.parse('$base/videos'), headers: _h, body: jsonEncode(body))
        .timeout(const Duration(minutes: 10));
    if (r.statusCode < 200 || r.statusCode >= 300) _fail(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return VideoJob(id: j['id'].toString(), status: (j['status'] ?? 'pending').toString());
  }

  @override
  Future<VideoJob> pollVideo(String id) async {
    final r = await _get('/videos/$id');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return VideoJob(
      id: j['id']?.toString() ?? id,
      status: (j['status'] ?? 'pending').toString(),
      cost: ((j['usage'] as Map?)?['cost'] as num?)?.toDouble() ?? 0,
      urls: ((j['unsigned_urls'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  /// Video content is behind the API key, so it must be fetched with headers
  /// rather than handed straight to a player.
  @override
  Future<Uint8List> downloadVideo(String jobId, {int index = 0}) async {
    final r = await _c
        .get(Uri.parse('$base/videos/$jobId/content?index=$index'), headers: {'Authorization': 'Bearer $apiKey'})
        .timeout(const Duration(minutes: 20));
    if (r.statusCode < 200 || r.statusCode >= 300) _fail(r);
    return r.bodyBytes;
  }

  @override
  void close() => _c.close();
}
