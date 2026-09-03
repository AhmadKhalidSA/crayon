import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/files.dart';

import '../api/or_model.dart';
import '../core/estimate.dart';
import '../data/gen_record.dart';

/// Everything the studio screen is currently configured to generate.
/// Parameters are stored as a loose map keyed by the model's own parameter
/// names, so a model the app has never seen still round-trips correctly.
class StudioState extends ChangeNotifier {
  Kind _kind = Kind.image;
  ORModel? _model;
  Task _task = Task.textToImage;
  String _prompt = '';
  final Map<String, dynamic> _params = {};

  Timer? _saveDebounce;
  bool _restoring = false;

  // sources
  final List<File> _refs = [];
  File? _firstFrame;
  File? _lastFrame;
  File? _sourceVideo;

  /// One optional mask per reference image, index aligned with [_refs].
  /// Masking is a tool ON an image, not a mode for the whole generation.
  final List<File?> _refMasks = [];

  /// Characters the next generation will be tagged with (auto, when you start
  /// from a character).
  final Set<String> _characterIds = {};

  /// Display name of the active character (for the studio banner). Not persisted
  /// with the record — only the id is.
  String? _characterLabel;

  /// Batch mode: [_refs] holds the fixed base image(s); each of these extra
  /// reference images spawns its own generation paired with the base. One click
  /// = many calls, so 20 references do not mean 20 manual attach/generate loops.
  final List<File> _batchRefs = [];

  List<String> get characterIds => _characterIds.toList();
  String? get characterLabel => _characterLabel;
  List<File> get batchRefs => List.unmodifiable(_batchRefs);
  bool get hasBatch => _batchRefs.isNotEmpty;

  void setCharacter(String id, [String? label]) {
    _characterIds
      ..clear()
      ..add(id);
    _characterLabel = label;
    notifyListeners();
  }

  void clearCharacters() {
    if (_characterIds.isEmpty && _characterLabel == null) return;
    _characterIds.clear();
    _characterLabel = null;
    notifyListeners();
  }

  void addBatchRef(File f) {
    _batchRefs.add(f);
    notifyListeners();
  }

  void removeBatchRef(int i) {
    if (i >= 0 && i < _batchRefs.length) {
      _batchRefs.removeAt(i);
      notifyListeners();
    }
  }

  void clearBatchRefs() {
    if (_batchRefs.isEmpty) return;
    _batchRefs.clear();
    notifyListeners();
  }

  Kind get kind => _kind;
  ORModel? get model => _model;
  Task get task => _task;
  String get prompt => _prompt;
  Map<String, dynamic> get params => Map.unmodifiable(_params);
  List<File> get refs => List.unmodifiable(_refs);
  File? get firstFrame => _firstFrame;
  File? get lastFrame => _lastFrame;
  File? get sourceVideo => _sourceVideo;

  /// The painted region for reference [i], if any.
  File? refMask(int i) => (i >= 0 && i < _refMasks.length) ? _refMasks[i] : null;

  List<File?> get refMasks => List.unmodifiable(_refMasks);

  bool get anyMask => _refMasks.any((m) => m != null);

  /// True when this is an unambiguous single image edit: one source, one
  /// painted region. Only then can the result be composited back so everything
  /// outside the mark is preserved. With several sources the output is a new
  /// composition, so there is nothing to preserve it against.
  bool get isSingleImageInpaint => _refs.length == 1 && refMask(0) != null;

  // ---------- persistence ----------
  //
  // The studio is restored exactly as it was left, including picked images,
  // so leaving the app or bouncing to the gallery never costs you the setup.
  // Reference files live in app storage, so their paths stay valid.

  static const _prefsKey = 'studio_state_v1';

  void _scheduleSave() {
    if (_restoring) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _prefsKey,
        jsonEncode({
          'kind': _kind.name,
          'model': _model?.id,
          'task': _task.name,
          'prompt': _prompt,
          'params': _params,
          'refs': _refs.map((f) => Files.rel(f.path)).toList(),
          'first': _firstFrame == null ? null : Files.rel(_firstFrame!.path),
          'last': _lastFrame == null ? null : Files.rel(_lastFrame!.path),
          'video': _sourceVideo == null ? null : Files.rel(_sourceVideo!.path),
          'masks': _refMasks.map((m) => m == null ? null : Files.rel(m.path)).toList(),
          'saved_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  /// Restores the previous session. [lookup] resolves a model id against the
  /// live catalogue, so a model that disappeared is skipped rather than
  /// leaving the studio pointing at nothing.
  Future<void> restore(ORModel? Function(String id) lookup) async {
    _restoring = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;

      final m = j['model'] == null ? null : lookup(j['model'].toString());
      if (m != null) {
        _model = m;
        _kind = m.kind;
        final t = Task.values.firstWhere((e) => e.name == j['task'], orElse: () => m.tasks.first);
        _task = m.tasks.contains(t) ? t : m.tasks.first;
      }

      _prompt = (j['prompt'] ?? '').toString();
      _params
        ..clear()
        ..addAll(((j['params'] as Map?) ?? const {}).cast<String, dynamic>());

      File? alive(Object? path) {
        final f = Files.fileFor(path?.toString());
        return (f != null && f.existsSync()) ? f : null;
      }

      _refs
        ..clear()
        ..addAll(((j['refs'] as List?) ?? const []).map(alive).whereType<File>());
      _firstFrame = alive(j['first']);
      _lastFrame = alive(j['last']);
      _sourceVideo = alive(j['video']);
      _refMasks
        ..clear()
        ..addAll(((j['masks'] as List?) ?? const []).map(alive));
      while (_refMasks.length < _refs.length) {
        _refMasks.add(null);
      }
    } catch (_) {
      // a corrupt blob must never stop the app booting
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ---------- selection ----------

  void setKind(Kind k, List<ORModel> available) {
    if (_kind == k) return;
    _kind = k;
    _model = null;
    if (available.isNotEmpty) setModel(available.first);
    notifyListeners();
    _scheduleSave();
  }

  void setModel(ORModel m) {
    _model = m;
    _kind = m.kind;
    final tasks = m.tasks;
    if (!tasks.contains(_task)) _task = tasks.isEmpty ? Task.textToImage : tasks.first;
    _applyDefaults();
    _pruneSourcesForTask();
    notifyListeners();
    _scheduleSave();
  }

  void setTask(Task t) {
    _task = t;
    _pruneSourcesForTask();
    notifyListeners();
    _scheduleSave();
  }

  void setPrompt(String p) {
    _prompt = p;
    _scheduleSave();
    // No notify: the text field owns its own state and rebuilding it on every
    // keystroke would fight the cursor. Listeners re-read on submit.
  }

  void setPromptAndNotify(String p) {
    _prompt = p;
    notifyListeners();
    _scheduleSave();
  }

  void setParam(String key, dynamic value) {
    if (value == null) {
      _params.remove(key);
    } else {
      _params[key] = value;
    }
    notifyListeners();
    _scheduleSave();
  }

  T? param<T>(String key) => _params[key] as T?;

  /// Sensible starting values derived from what the model actually allows.
  void _applyDefaults() {
    final m = _model;
    _params.clear();
    if (m == null) return;

    if (m.kind == Kind.image) {
      final ar = m.imageAspects;
      // Prefer 'auto' when the model offers it (match the reference image's
      // proportions), otherwise a square, otherwise the first option.
      if (ar.isNotEmpty) {
        _params['aspect_ratio'] =
            ar.contains('auto') ? 'auto' : (ar.contains('1:1') ? '1:1' : ar.first);
      }
      final res = m.imageResolutions;
      if (res.isNotEmpty) {
        _params['resolution'] = res.contains('2K')
            ? '2K'
            : res.contains('1K')
                ? '1K'
                : res.first;
      }
      if (m.maxN > 1) _params['n'] = 1;
      final q = m.qualities;
      if (q.isNotEmpty) _params['quality'] = q.contains('high') ? 'high' : q.first;
    } else {
      final ar = m.aspectRatios;
      if (ar.isNotEmpty) _params['aspect_ratio'] = ar.contains('16:9') ? '16:9' : ar.first;
      final res = m.resolutions;
      if (res.isNotEmpty) {
        _params['resolution'] = res.contains('720p') ? '720p' : res.first;
      }
      final d = m.durations;
      if (d.isNotEmpty) {
        // shortest sensible clip keeps the default cheap
        _params['duration'] = d.contains(5) ? 5 : d.first;
      }
      if (m.generateAudio) _params['generate_audio'] = true;
      if (m.upscaleMin != null) _params['upscale_factor'] = m.upscaleMin;
    }
  }

  /// Sources are DELIBERATELY not cleared when the task changes. Flipping to
  /// Text to image and back used to wipe the images you had just picked. What
  /// a task does not use is simply not sent (see [sourcesForSubmit]).
  ///
  /// The one thing that must still happen is trimming to the current model's
  /// reference cap, because sending more than it allows is a guaranteed error.
  void _pruneSourcesForTask() {
    final cap = modelRefCap;
    if (cap > 0 && _refs.length > cap) _refs.removeRange(cap, _refs.length);
  }

  /// Exactly the sources the current task should send, so unused ones can be
  /// kept in the UI without leaking into the request.
  ({List<File> refs, List<File?> masks, File? firstFrame, File? lastFrame, File? video})
      get sourcesForSubmit {
    final t = _task;
    return (
      // outpaint and inpaint work from a single image even though the model
      // would accept more, so the extras are kept in the UI but not sent
      refs: t == Task.imageToImage || t == Task.edit || t == Task.refToVideo
          ? List<File>.from(_refs)
          : t == Task.outpaint
              ? (_refs.isEmpty ? const <File>[] : [_refs.first])
              : const <File>[],
      masks: t == Task.imageToImage || t == Task.edit
          ? List<File?>.from(_refMasks.take(_refs.length))
          : const <File?>[],
      firstFrame: t == Task.imageToVideo || t == Task.frames || t == Task.lipsync ? _firstFrame : null,
      lastFrame: t == Task.frames ? _lastFrame : null,
      video: t.needsVideo ? _sourceVideo : null,
    );
  }

  // ---------- sources ----------

  /// How many references the CURRENT task can show. Outpaint works from one
  /// image; everything else follows the model's own cap.
  int get maxRefs {
    final m = _model;
    if (m == null) return 0;
    if (_task == Task.outpaint) return 1;
    return m.maxRefs;
  }

  /// The model's cap regardless of task, used when trimming kept sources so a
  /// task that shows no references does not silently discard them.
  int get modelRefCap => _model?.maxRefs ?? 0;

  void addRef(File f) {
    if (_refs.length >= maxRefs) return;
    _refs.add(f);
    _refMasks.add(null);
    notifyListeners();
    _scheduleSave();
  }

  void setRefMask(int i, File? mask) {
    while (_refMasks.length < _refs.length) {
      _refMasks.add(null);
    }
    if (i < 0 || i >= _refMasks.length) return;
    _refMasks[i] = mask;
    notifyListeners();
    _scheduleSave();
  }

  void removeRefAt(int i) {
    if (i >= 0 && i < _refs.length) _refs.removeAt(i);
    if (i >= 0 && i < _refMasks.length) _refMasks.removeAt(i);
    notifyListeners();
    _scheduleSave();
  }

  /// Reference order is part of the prompt's meaning, so it has to be editable
  /// without removing and re-picking everything.
  void moveRef(int from, int to) {
    if (from < 0 || from >= _refs.length) return;
    if (to < 0 || to >= _refs.length || to == from) return;
    final f = _refs.removeAt(from);
    _refs.insert(to, f);
    if (from < _refMasks.length) {
      final m = _refMasks.removeAt(from);
      _refMasks.insert(to.clamp(0, _refMasks.length), m);
    }
    notifyListeners();
    _scheduleSave();
  }

  void replaceRefAt(int i, File f) {
    if (i < 0 || i >= _refs.length) return;
    _refs[i] = f;
    // the old mark was drawn for the old picture, so it no longer means anything
    if (i < _refMasks.length) _refMasks[i] = null;
    notifyListeners();
    _scheduleSave();
  }

  void setFirstFrame(File? f) {
    _firstFrame = f;
    notifyListeners();
    _scheduleSave();
  }

  void setLastFrame(File? f) {
    _lastFrame = f;
    notifyListeners();
    _scheduleSave();
  }

  void setSourceVideo(File? f) {
    _sourceVideo = f;
    notifyListeners();
    _scheduleSave();
  }

  void clearSources() {
    _refs.clear();
    _firstFrame = null;
    _lastFrame = null;
    _sourceVideo = null;
    _refMasks.clear();
    notifyListeners();
    _scheduleSave();
  }

  // ---------- validation ----------

  /// null when ready, otherwise the reason the Generate button is disabled.
  String? get blocker {
    final m = _model;
    if (m == null) return 'Pick a model';
    if (_task != Task.upscaleVideo && _prompt.trim().isEmpty) {
      if (_task == Task.imageToVideo || _task == Task.frames || _task == Task.lipsync) {
        // some providers allow an image-only video request
        if (_firstFrame == null) return 'Write a prompt';
      } else {
        return 'Write a prompt';
      }
    }
    if (m.requiresReference && _refs.isEmpty) return 'This model needs a reference image';
    switch (_task) {
      case Task.imageToImage:
      case Task.edit:
        if (_refs.isEmpty) return 'Add a source image';
        break;
      case Task.outpaint:
        if (_refs.isEmpty) return 'Add the image to extend';
        break;
      case Task.imageToVideo:
        if (_firstFrame == null) return 'Add a starting image';
        break;
      case Task.frames:
        if (_firstFrame == null) return 'Add a first frame';
        if (_lastFrame == null) return 'Add a last frame';
        break;
      case Task.refToVideo:
        if (_refs.isEmpty) return 'Add a reference image';
        break;
      case Task.lipsync:
        if (_firstFrame == null) return 'Add the character image';
        break;
      case Task.videoToVideo:
      case Task.upscaleVideo:
        if (_sourceVideo == null) return 'Add a source video';
        break;
      default:
        break;
    }
    return null;
  }

  bool get canGenerate => blocker == null;

  Estimate get estimate {
    final m = _model;
    if (m == null) return Estimate.metered;
    if (m.kind == Kind.image) {
      return Estimator.image(
        m,
        n: (_params['n'] as int?) ?? 1,
        resolution: _params['resolution'] as String?,
        aspect: _params['aspect_ratio'] as String?,
        quality: _params['quality'] as String?,
      );
    }
    return Estimator.video(
      m,
      seconds: (_params['duration'] as int?) ?? 5,
      resolution: _params['resolution'] as String?,
      audio: _params['generate_audio'] != false,
    );
  }

  // ---------- reuse an earlier generation ----------

  /// "Clone": load a past generation's settings back into the studio.
  void cloneFrom(GenRecord g, ORModel? m) {
    if (m != null) {
      _model = m;
      _kind = m.kind;
      _task = m.tasks.contains(g.task) ? g.task : (m.tasks.isNotEmpty ? m.tasks.first : g.task);
    } else {
      _kind = g.kind;
      _task = g.task;
    }
    _prompt = g.prompt;
    _params
      ..clear()
      ..addAll(g.params);
    _refs
      ..clear()
      ..addAll(g.refFiles);
    _refMasks
      ..clear()
      ..addAll(List<File?>.filled(_refs.length, null));
    _firstFrame = null;
    _lastFrame = null;
    _sourceVideo = null;
    notifyListeners();
    _scheduleSave();
  }

  /// Start a fresh generation anchored on a character: loads up to [maxRefs]
  /// (capped at 3) of the character's own reference images as the sources, so
  /// the model actually locks onto that person instead of just being labelled
  /// with them. Auto aspect then matches the reference's proportions.
  void startWithCharacter(String id, String name, List<File> images, ORModel m) {
    _model = m;
    _kind = m.kind;
    _task = m.tasks.contains(Task.edit)
        ? Task.edit
        : (m.tasks.contains(Task.imageToImage) ? Task.imageToImage : _task);
    _applyDefaults();
    _refs.clear();
    _refMasks.clear();
    _batchRefs.clear();
    final cap = maxRefs < 3 ? maxRefs : 3;
    for (final f in images.take(cap)) {
      _refs.add(f);
      _refMasks.add(null);
    }
    _characterIds
      ..clear()
      ..add(id);
    _characterLabel = name;
    notifyListeners();
    _scheduleSave();
  }

  /// "Edit"/"Animate": start a new job from an existing output file.
  void useAsSource(File f, {required Task target, ORModel? m}) {
    if (m != null) {
      _model = m;
      _kind = m.kind;
    }
    _task = target;
    if (target == Task.imageToVideo || target == Task.frames || target == Task.lipsync) {
      _firstFrame = f;
      _refs.clear();
    } else if (target == Task.videoToVideo || target == Task.upscaleVideo) {
      _sourceVideo = f;
    } else {
      _refs
        ..clear()
        ..add(f);
    }
    notifyListeners();
    _scheduleSave();
  }
}
