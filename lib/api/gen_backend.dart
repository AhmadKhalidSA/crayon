import 'dart:typed_data';

import 'or_model.dart';

/// One error type shared by every backend so the UI can show a single message
/// shape regardless of which provider produced it.
class ORException implements Exception {
  ORException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

/// Account balance, normalised. `remaining = total - used`. For a backend that
/// only exposes a single balance figure, `total` is the balance and `used` is 0.
class Credits {
  Credits(this.total, this.used, {this.unit = '\$'});
  final double total;
  final double used;

  /// Display unit (defaults to '\$').
  final String unit;
  double get remaining => total - used;
}

/// The images one generation produced, plus the real cost the provider charged.
class ImageResult {
  ImageResult(this.bytes, this.mediaType, this.cost);
  final List<Uint8List> bytes;
  final String mediaType;
  final double cost;
}

/// A server-side video job to poll (OpenRouter's async model).
class VideoJob {
  VideoJob({required this.id, required this.status, this.cost = 0, this.urls = const []});
  final String id;
  final String status; // pending | in_progress | completed | failed
  final double cost;
  final List<String> urls;
  bool get done => status == 'completed';
  bool get failed => status == 'failed';
}

/// A finished video, produced by a backend that runs the job to completion in
/// one call (a backend whose video carries no server-side id to resume).
class VideoResult {
  VideoResult(this.bytes, this.cost, {this.mediaType = 'video/mp4'});
  final Uint8List bytes;
  final double cost;
  final String mediaType;
}

/// The provider-neutral surface the app talks to. Everything above this line
/// (the studio, the gallery, the job runner) is written against this interface,
/// so a second provider needs no UI work — only a class that implements it.
///
/// [OpenRouter] is the backend today. Video is produced along one of two paths,
/// expressed by [videoResumable]:
///   - true  (OpenRouter): a POST returns a job id; the runner polls it and can
///     resume across an app restart.
///   - false: the job runs to completion in a single [runVideo] call and cannot
///     be resumed once it is gone. Kept as the seam for a future backend.
abstract class GenBackend {
  /// Stable id, also used as the on-disk catalogue cache filename.
  String get id; // 'openrouter'

  /// Human label for the settings screen.
  String get label;

  /// Whether video jobs have a server-side id that survives an app restart.
  bool get videoResumable;

  /// Account balance. Throws [ORException] on failure.
  Future<Credits> credits();

  /// Cheap key-validity probe for the settings screen.
  Future<bool> validate();

  /// The full image + video catalogue for this provider, as neutral [ORModel]s.
  /// [onProgress] reports (done, total) so a refresh bar can be shown.
  Future<List<ORModel>> listModels({void Function(int done, int total)? onProgress});

  /// Generate one image, run to completion, returning the bytes and real cost.
  /// [referenceDataUrls] are data URLs; a non-empty list means image-to-image.
  /// [onNote]/[onProgress] are optional live-status callbacks.
  Future<ImageResult> generateImage({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
    List<String> referenceDataUrls = const [],
    void Function(String note)? onNote,
    void Function(double progress)? onProgress,
  });

  // ---- resumable video path (used only when videoResumable == true) ----

  Future<VideoJob> createVideo({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
    List<Map<String, String>> frames = const [],
    List<String> referenceDataUrls = const [],
  });

  Future<VideoJob> pollVideo(String id);

  Future<Uint8List> downloadVideo(String jobId, {int index = 0});

  // ---- one-shot video path (used only when videoResumable == false) ----

  Future<VideoResult> runVideo({
    required String model,
    required String prompt,
    Map<String, dynamic> params = const {},
    List<Map<String, String>> frames = const [],
    List<String> referenceDataUrls = const [],
    void Function(String note)? onNote,
    void Function(double progress)? onProgress,
  });

  void close();
}
