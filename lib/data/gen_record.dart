import 'dart:convert';

import 'dart:io';

import '../api/or_model.dart';
import 'files.dart';

enum GenStatus { queued, running, done, failed }

/// One generation attempt. Rows are written the moment a job is queued so a
/// crash mid-flight leaves a visible failed row rather than a silent gap.
class GenRecord {
  GenRecord({
    required this.id,
    required this.kind,
    required this.modelId,
    required this.modelName,
    required this.task,
    required this.prompt,
    this.params = const {},
    this.refPaths = const [],
    this.status = GenStatus.queued,
    this.jobId,
    this.filePath,
    this.width = 0,
    this.height = 0,
    this.durationSec = 0,
    this.cost = 0,
    this.error,
    required this.createdAt,
    this.completedAt,
    this.favorite = false,
    this.groupId,
    this.maskPath,
    this.category,
    this.characterIds = const [],
  });

  final String id;
  final Kind kind;
  final String modelId;
  final String modelName;
  final Task task;
  final String prompt;
  final Map<String, dynamic> params;
  final List<String> refPaths;
  final GenStatus status;
  final String? jobId;
  final String? filePath;
  final int width;
  final int height;
  final int durationSec;
  final double cost;
  final String? error;
  final int createdAt;
  final int? completedAt;
  final bool favorite;

  /// Images generated together (n > 1) share a group so the gallery can show
  /// them as one batch when needed.
  final String? groupId;

  /// Inpaint only: the painted region, kept so a regenerate reuses it.
  final String? maskPath;

  /// User-assigned category name for organising the gallery.
  final String? category;

  /// Ids of the [Character]s used in this generation (for the Characters view
  /// and backfill tagging).
  final List<String> characterIds;

  bool get isVideo => kind == Kind.video;

  /// The output on disk right now. Stored paths are relative, so they must be
  /// re-rooted rather than used directly.
  File? get file => Files.fileFor(filePath);

  List<File> get refFiles =>
      refPaths.map(Files.fileFor).whereType<File>().where((f) => f.existsSync()).toList();

  File? get maskFile => Files.fileFor(maskPath);
  double get aspect => (width > 0 && height > 0) ? width / height : 1.0;

  GenRecord copyWith({
    GenStatus? status,
    String? jobId,
    String? filePath,
    int? width,
    int? height,
    int? durationSec,
    double? cost,
    String? error,
    int? completedAt,
    bool? favorite,
    String? category,
    List<String>? characterIds,
  }) =>
      GenRecord(
        id: id,
        kind: kind,
        modelId: modelId,
        modelName: modelName,
        task: task,
        prompt: prompt,
        params: params,
        refPaths: refPaths,
        status: status ?? this.status,
        jobId: jobId ?? this.jobId,
        filePath: filePath ?? this.filePath,
        width: width ?? this.width,
        height: height ?? this.height,
        durationSec: durationSec ?? this.durationSec,
        cost: cost ?? this.cost,
        error: error ?? this.error,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
        favorite: favorite ?? this.favorite,
        groupId: groupId,
        maskPath: maskPath,
        category: category ?? this.category,
        characterIds: characterIds ?? this.characterIds,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'kind': kind.name,
        'model_id': modelId,
        'model_name': modelName,
        'task': task.name,
        'prompt': prompt,
        'params': jsonEncode(params),
        'ref_paths': jsonEncode(refPaths),
        'status': status.name,
        'job_id': jobId,
        'file_path': filePath,
        'width': width,
        'height': height,
        'duration_sec': durationSec,
        'cost': cost,
        'error': error,
        'created_at': createdAt,
        'completed_at': completedAt,
        'favorite': favorite ? 1 : 0,
        'group_id': groupId,
        'mask_path': maskPath,
        'category': category,
        'character_ids': jsonEncode(characterIds),
      };

  factory GenRecord.fromRow(Map<String, Object?> r) => GenRecord(
        id: r['id'] as String,
        kind: r['kind'] == 'video' ? Kind.video : Kind.image,
        modelId: r['model_id'] as String? ?? '',
        modelName: r['model_name'] as String? ?? '',
        task: Task.values.firstWhere((t) => t.name == r['task'], orElse: () => Task.textToImage),
        prompt: r['prompt'] as String? ?? '',
        params: _decodeMap(r['params']),
        refPaths: _decodeList(r['ref_paths']),
        status: GenStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => GenStatus.done),
        jobId: r['job_id'] as String?,
        filePath: r['file_path'] as String?,
        width: (r['width'] as num?)?.toInt() ?? 0,
        height: (r['height'] as num?)?.toInt() ?? 0,
        durationSec: (r['duration_sec'] as num?)?.toInt() ?? 0,
        cost: (r['cost'] as num?)?.toDouble() ?? 0,
        error: r['error'] as String?,
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        completedAt: (r['completed_at'] as num?)?.toInt(),
        favorite: (r['favorite'] as num?)?.toInt() == 1,
        groupId: r['group_id'] as String?,
        maskPath: r['mask_path'] as String?,
        category: r['category'] as String?,
        characterIds: _decodeList(r['character_ids']),
      );

  static Map<String, dynamic> _decodeMap(Object? v) {
    if (v is! String || v.isEmpty) return {};
    try {
      return (jsonDecode(v) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static List<String> _decodeList(Object? v) {
    if (v is! String || v.isEmpty) return const [];
    try {
      return (jsonDecode(v) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }
}
