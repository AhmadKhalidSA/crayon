import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

import '../api/gen_backend.dart';
import '../api/or_model.dart';
import '../core/imaging.dart';
import '../data/db.dart';
import '../data/files.dart';
import '../data/gen_record.dart';
import 'studio_state.dart';

/// Builds a fresh backend for a given provider id. Each generation makes its
/// own from its model's provider, uses it, and closes it — a backend is never
/// shared across jobs.
typedef MakeBackend = GenBackend Function(String providerId);

/// Gallery contents plus the queue that produces them.
class LibraryState extends ChangeNotifier {
  LibraryState();

  final List<GenRecord> _items = [];
  final Map<String, String> _statusNote = {};
  final Set<String> _running = {};
  // Jobs the user cancelled: their in-flight result is discarded rather than
  // written, so a cancel actually stops the image landing.
  final Set<String> _cancelled = {};
  final _rand = Random();

  bool _loading = false;
  bool _hasMore = true;
  String? _kindFilter;
  bool _favouritesOnly = false;
  String _search = '';
  String? _category;

  Credits? credits;
  String? creditsError;

  List<GenRecord> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get hasMore => _hasMore;
  String? get kindFilter => _kindFilter;
  bool get favouritesOnly => _favouritesOnly;
  String get search => _search;
  String? get category => _category;
  bool get anyRunning => _running.isNotEmpty;
  int get runningCount => _running.length;
  String? noteFor(String id) => _statusNote[id];

  List<GenRecord> get active =>
      _items.where((g) => g.status == GenStatus.queued || g.status == GenStatus.running).toList();

  // ---------------- listing ----------------

  Future<void> setFilter({String? kind, bool? favourites, String? search}) async {
    _kindFilter = kind;
    if (favourites != null) _favouritesOnly = favourites;
    if (search != null) _search = search;
    await reload();
  }

  /// Filter the gallery to one category (null = all).
  Future<void> setCategory(String? category) async {
    _category = category;
    await reload();
  }

  Future<void> reload() async {
    _items.clear();
    _hasMore = true;
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    notifyListeners();
    try {
      final page = await Db.page(
        offset: _items.length,
        kindFilter: _kindFilter,
        favouritesOnly: _favouritesOnly,
        search: _search,
        category: _category,
      );
      if (page.length < 30) _hasMore = false;
      _items.addAll(page);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _replace(GenRecord g) {
    final i = _items.indexWhere((e) => e.id == g.id);
    if (i >= 0) {
      _items[i] = g;
    } else {
      _items.insert(0, g);
    }
    notifyListeners();
  }

  Future<void> toggleFavourite(GenRecord g) async {
    final n = g.copyWith(favorite: !g.favorite);
    await Db.upsert(n);
    _replace(n);
  }

  /// Re-read one record from the DB into the in-memory list (e.g. after its
  /// category or characters changed elsewhere).
  Future<void> refreshOne(String id) async {
    final fresh = await Db.byId(id);
    if (fresh != null) _replace(fresh);
  }

  Future<void> remove(GenRecord g) async {
    await Files.deleteQuietly(g.filePath);
    await Db.delete(g.id);
    _items.removeWhere((e) => e.id == g.id);
    notifyListeners();
  }

  // ---------------- jobs queue ----------------

  /// Stops a queued/running job: its in-flight result (if any) is discarded and
  /// the row is marked failed with a 'Cancelled' note. The network call may
  /// still finish provider-side, but nothing lands in the gallery.
  Future<void> cancel(GenRecord g) async {
    if (g.status != GenStatus.queued && g.status != GenStatus.running) return;
    _cancelled.add(g.id);
    final f = g.copyWith(
      status: GenStatus.failed,
      error: 'Cancelled',
      completedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await Db.upsert(f);
    _replace(f);
    _running.remove(g.id);
    _statusNote.remove(g.id);
    notifyListeners();
  }

  Future<void> cancelAll() async {
    for (final g in active) {
      await cancel(g);
    }
  }

  bool _isCancelled(String id) => _cancelled.contains(id);

  /// Deletes every failed row (and any stray file) in one go.
  Future<void> clearFailed() async {
    final failed = _items.where((e) => e.status == GenStatus.failed).toList();
    for (final g in failed) {
      await Files.deleteQuietly(g.filePath);
      await Db.delete(g.id);
    }
    _items.removeWhere((e) => e.status == GenStatus.failed);
    notifyListeners();
  }

  // ---------------- bulk actions ----------------

  /// Copies a finished generation into the phone gallery. Returns false if the
  /// file is missing or permission was denied.
  Future<bool> saveToDevice(GenRecord g) async {
    final f = g.file;
    if (f == null || !f.existsSync()) return false;
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return false;
      }
      if (g.isVideo) {
        await Gal.putVideo(f.path, album: 'Crayon');
      } else {
        await Gal.putImage(f.path, album: 'Crayon');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves many at once; returns how many actually landed in the phone gallery.
  Future<int> saveManyToDevice(Iterable<GenRecord> gs) async {
    var ok = 0;
    for (final g in gs) {
      if (g.status == GenStatus.done && await saveToDevice(g)) ok++;
    }
    return ok;
  }

  Future<void> removeMany(Iterable<GenRecord> gs) async {
    for (final g in gs.toList()) {
      await Files.deleteQuietly(g.filePath);
      await Db.delete(g.id);
    }
    final ids = gs.map((e) => e.id).toSet();
    _items.removeWhere((e) => ids.contains(e.id));
    notifyListeners();
  }

  Future<void> setCategoryMany(Iterable<String> ids, String? category) async {
    for (final id in ids) {
      await Db.setCategory(id, category);
      await refreshOne(id);
    }
  }

  /// Adds a character tag to each generation (union with any it already has).
  Future<void> addCharacterMany(Iterable<String> ids, String charId) async {
    for (final id in ids) {
      final g = await Db.byId(id);
      if (g == null) continue;
      final set = {...g.characterIds, charId}.toList();
      await Db.setGenCharacters(id, set);
      await refreshOne(id);
    }
  }

  /// Which provider the current [credits] figure is for (so the Spend screen can
  /// label it and refresh the right one as the selected model changes).
  String? creditsProvider;

  Future<void> refreshCredits(GenBackend backend) async {
    try {
      credits = await backend.credits();
      creditsProvider = backend.id;
      creditsError = null;
    } catch (e) {
      creditsError = e.toString();
    } finally {
      backend.close();
      notifyListeners();
    }
  }

  // ---------------- submitting ----------------

  String _id() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

  /// Queues one generation from the current studio configuration and starts it.
  /// Returns the record id, or null if the studio is not ready.
  Future<String?> submit(StudioState s, MakeBackend make,
      {bool autoSave = false, int refMaxSide = 2048}) async {
    final m = s.model;
    if (m == null || !s.canGenerate) return null;

    final src = s.sourcesForSubmit;
    final refPaths = <String>[
      ...src.refs.map((f) => Files.rel(f.path)),
      if (src.firstFrame != null) Files.rel(src.firstFrame!.path),
      if (src.lastFrame != null) Files.rel(src.lastFrame!.path),
      if (src.video != null) Files.rel(src.video!.path),
    ];

    final g = GenRecord(
      id: _id(),
      kind: m.kind,
      modelId: m.id,
      modelName: m.shortName,
      task: s.task,
      prompt: s.prompt.trim(),
      params: Map<String, dynamic>.from(s.params),
      refPaths: refPaths,
      status: GenStatus.queued,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      // the base mask, kept so a regenerate reproduces the same edit
      maskPath: s.isSingleImageInpaint && s.refMask(0) != null ? Files.rel(s.refMask(0)!.path) : null,
      characterIds: s.characterIds,
    );
    await Db.upsert(g);
    _items.insert(0, g);
    notifyListeners();

    unawaited(_run(g, m, make,
        autoSave: autoSave,
        refMaxSide: refMaxSide,
        sourceFiles: _SourceFiles(
          refs: src.refs,
          firstFrame: src.firstFrame,
          lastFrame: src.lastFrame,
          video: src.video,
          masks: src.masks,
        )));
    return g.id;
  }

  /// Batch: one generation per batch reference, each pairing the studio's base
  /// image(s) with that reference. Returns how many were started. This is the
  /// "attach my image once, run it against 20 references in one tap" flow.
  Future<int> submitBatch(StudioState s, MakeBackend make,
      {bool autoSave = false, int refMaxSide = 2048}) async {
    final m = s.model;
    if (m == null || m.kind != Kind.image || s.batchRefs.isEmpty) return 0;
    final base = s.refs; // the fixed subject image(s)
    final groupId = _id();
    var started = 0;
    for (final ref in s.batchRefs) {
      final combined = <File>[...base, ref];
      final g = GenRecord(
        id: _id(),
        kind: Kind.image,
        modelId: m.id,
        modelName: m.shortName,
        task: Task.edit,
        prompt: s.prompt.trim(),
        params: Map<String, dynamic>.from(s.params),
        refPaths: combined.map((f) => Files.rel(f.path)).toList(),
        status: GenStatus.queued,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        groupId: groupId,
        characterIds: s.characterIds,
      );
      await Db.upsert(g);
      _items.insert(0, g);
      notifyListeners();
      unawaited(_run(g, m, make,
          autoSave: autoSave, refMaxSide: refMaxSide, sourceFiles: _SourceFiles(refs: combined)));
      started++;
    }
    return started;
  }

  /// Bakes a character model sheet: feeds the chosen reference photos to [model]
  /// once with the sheet [prompt], and on completion the output is promoted to
  /// the character's stored sheet (via the `_sheet_for` marker in [_runImage]).
  /// Returns the generation id, or null if it could not start.
  Future<String?> submitModelSheet({
    required String charId,
    required ORModel model,
    required List<File> images,
    required String prompt,
    required MakeBackend make,
    bool autoSave = false,
    int refMaxSide = 2048,
  }) async {
    if (model.kind != Kind.image || images.isEmpty) return null;

    // Sensible defaults for a sheet: widest available canvas + best quality.
    final params = <String, dynamic>{'_sheet_for': charId};
    final ar = model.imageAspects.where((e) => e != 'auto').toList();
    if (ar.contains('16:9')) {
      params['aspect_ratio'] = '16:9';
    } else if (ar.isNotEmpty) {
      params['aspect_ratio'] = ar.first;
    }
    final q = model.qualities;
    if (q.isNotEmpty) params['quality'] = q.contains('high') ? 'high' : q.last;
    final res = model.imageResolutions;
    if (res.isNotEmpty) params['resolution'] = res.contains('2K') ? '2K' : res.last;

    final g = GenRecord(
      id: _id(),
      kind: Kind.image,
      modelId: model.id,
      modelName: model.shortName,
      task: images.length > 1 ? Task.edit : Task.imageToImage,
      prompt: prompt.trim(),
      params: params,
      refPaths: images.map((f) => Files.rel(f.path)).toList(),
      status: GenStatus.queued,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      characterIds: [charId],
    );
    await Db.upsert(g);
    _items.insert(0, g);
    notifyListeners();
    unawaited(_run(g, model, make,
        autoSave: autoSave, refMaxSide: refMaxSide, sourceFiles: _SourceFiles(refs: images)));
    return g.id;
  }

  /// Re-run an existing record with the exact same settings.
  Future<String?> regenerate(GenRecord old, ORModel? m, MakeBackend make,
      {bool autoSave = false, int refMaxSide = 2048}) async {
    if (m == null) return null;
    final g = GenRecord(
      id: _id(),
      kind: old.kind,
      modelId: old.modelId,
      modelName: old.modelName,
      task: old.task,
      prompt: old.prompt,
      params: Map<String, dynamic>.from(old.params),
      refPaths: old.refPaths,
      status: GenStatus.queued,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      maskPath: old.maskPath,
    );
    await Db.upsert(g);
    _items.insert(0, g);
    notifyListeners();

    final refs = old.refFiles;
    final oldMask = old.maskFile;
    unawaited(_run(g, m, make,
        autoSave: autoSave,
        refMaxSide: refMaxSide,
        sourceFiles: _SourceFiles(
          refs: old.task.needsImage && old.task != Task.imageToVideo && old.task != Task.frames
              ? refs
              : const [],
          firstFrame: (old.task == Task.imageToVideo || old.task == Task.frames || old.task == Task.lipsync) &&
                  refs.isNotEmpty
              ? refs.first
              : null,
          lastFrame: old.task == Task.frames && refs.length > 1 ? refs[1] : null,
          video: old.task.needsVideo && refs.isNotEmpty ? refs.last : null,
          masks: oldMask != null && oldMask.existsSync() ? [oldMask] : const [],
        )));
    return g.id;
  }

  /// Picks up jobs that were still running when the app was last closed.
  /// Image jobs cannot be resumed (the HTTP call is gone), so they are marked
  /// failed honestly rather than left spinning forever. Video jobs have a
  /// server-side id, so they genuinely resume.
  Future<void> resumeUnfinished(MakeBackend make, List<ORModel> catalog) async {
    final pending = await Db.unfinished();
    for (final g in pending) {
      final m = catalog.where((e) => e.id == g.modelId).firstOrNull;
      // Only a provider whose video jobs carry a server-side id can be resumed.
      if (m != null && g.kind == Kind.video && g.jobId != null) {
        final probe = make(m.provider);
        final resumable = probe.videoResumable;
        probe.close();
        if (resumable) {
          unawaited(_pollVideo(g, make, m.provider));
          continue;
        }
      }
      final failed = g.copyWith(
        status: GenStatus.failed,
        error: 'Interrupted when the app closed',
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await Db.upsert(failed);
      _replace(failed);
    }
  }

  // ---------------- execution ----------------

  Future<void> _run(GenRecord g0, ORModel m, MakeBackend make,
      {required _SourceFiles sourceFiles, bool autoSave = false, int refMaxSide = 2048}) async {
    _running.add(g0.id);
    var g = g0.copyWith(status: GenStatus.running);
    await Db.upsert(g);
    _replace(g);

    final backend = make(m.provider);
    try {
      if (m.kind == Kind.image) {
        await _runImage(g, m, backend, sourceFiles, autoSave, refMaxSide);
      } else {
        await _runVideo(g, m, backend, sourceFiles, make, autoSave, refMaxSide);
      }
    } catch (e) {
      if (!_isCancelled(g0.id)) await _fail(g, e.toString());
    } finally {
      backend.close();
      _running.remove(g0.id);
      _cancelled.remove(g0.id);
      _statusNote.remove(g0.id);
      notifyListeners();
    }
  }

  Future<void> _fail(GenRecord g, String msg) async {
    final f = g.copyWith(
      status: GenStatus.failed,
      error: msg,
      completedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await Db.upsert(f);
    _replace(f);
  }

  void _note(String id, String note) {
    _statusNote[id] = note;
    notifyListeners();
  }

  /// Copies a finished file into the phone's own gallery when the setting is
  /// on. Never fails a generation: the file is already safely in the app.
  Future<void> _autoSave(String path, bool isVideo) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return;
      }
      if (isVideo) {
        await Gal.putVideo(path, album: 'Crayon');
      } else {
        await Gal.putImage(path, album: 'Crayon');
      }
    } catch (_) {}
  }

  Future<void> _runImage(GenRecord g, ORModel m, GenBackend backend, _SourceFiles src, bool autoSave,
      int refMaxSide) async {
    _note(g.id, 'Preparing');
    final params = _imageParams(m, g);
    var prompt = g.prompt;
    final refs = <String>[];

    if (src.anyMask && src.refs.isNotEmpty) {
      _note(g.id, 'Marking the area');
      for (var i = 0; i < src.refs.length; i++) {
        final mask = src.maskFor(i);
        if (mask == null) {
          refs.add(await Imaging.toDataUrlCompressed(src.refs[i], maxSide: refMaxSide));
          continue;
        }
        final marked = await Imaging.buildInpaintInput(src.refs[i], mask);
        if (marked == null) throw ORException('Could not prepare the masked image.');
        final f = await Files.writeRefBytes(marked, 'png');
        refs.add(await Imaging.toDataUrlCompressed(f, maxSide: refMaxSide));
      }
      final many = src.refs.length > 1;
      final what = prompt.trim().isEmpty ? '' : ' with: $prompt';
      prompt = many
          ? 'The solid magenta marks show which part of each image to work from$what. '
              'Ignore the magenta colour itself, it is only a marker.'
          : 'Replace ONLY the area covered by the solid magenta mark$what. '
              'Match the surrounding lighting, perspective, colour and grain so the edit is invisible. '
              'Leave everything else exactly as it is.';
    } else if (g.task == Task.outpaint && src.refs.isNotEmpty) {
      final aspect = (g.params['aspect_ratio'] as String?) ?? '1:1';
      final zoom = (g.params['outpaint_zoom'] as num?)?.toDouble() ?? 1.35;
      final canvas = await Imaging.buildOutpaintCanvas(src.refs.first, targetAspect: aspect, zoomOut: zoom);
      if (canvas == null) throw ORException('Could not build the outpaint canvas from that image.');
      final f = await Files.writeRefBytes(canvas, 'png');
      refs.add(await Imaging.toDataUrlCompressed(f, maxSide: refMaxSide));
      prompt = prompt.trim().isEmpty
          ? 'Extend this image naturally to fill the empty transparent area. Continue the existing scene, lighting and style seamlessly to the edges. Do not alter the original content.'
          : '$prompt. Extend the image naturally into the empty transparent area, continuing the existing scene seamlessly to the edges without altering the original content.';
    } else {
      for (final f in src.refs) {
        refs.add(await Imaging.toDataUrlCompressed(f, maxSide: refMaxSide));
      }
    }

    _note(g.id, 'Generating');
    final res = await backend.generateImage(
      model: m.id,
      prompt: prompt,
      params: params,
      referenceDataUrls: refs,
      onNote: (n) => _note(g.id, n),
    );

    if (_isCancelled(g.id)) return;
    _note(g.id, 'Saving');
    var ext = Files.extFor(res.mediaType);

    // Inpaint: the model re-renders the whole frame, so the result is
    // composited back over the original through the mask. Only the painted
    // region actually changes; everything else is the original's own pixels.
    if (src.isSingleImageInpaint && res.bytes.isNotEmpty) {
      _note(g.id, 'Blending');
      final merged = await Imaging.compositeInpaint(
        original: src.refs.first,
        generated: res.bytes.first,
        mask: src.maskFor(0)!,
      );
      if (merged != null) {
        res.bytes
          ..clear()
          ..add(merged);
        ext = 'png';
      }
    }
    // n > 1 comes back as several images: first stays on this record, the rest
    // become sibling records so the gallery shows every one.
    for (var i = 0; i < res.bytes.length; i++) {
      final bytes = res.bytes[i];
      final size = await Imaging.size(bytes);
      if (i == 0) {
        final file = await Files.writeOutput(g.id, bytes, ext);
        final done = g.copyWith(
          status: GenStatus.done,
          filePath: Files.rel(file.path),
          width: size.width,
          height: size.height,
          cost: res.cost / res.bytes.length,
          completedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await Db.upsert(done);
        _replace(done);
        if (autoSave) await _autoSave(file.path, false);
        // If this generation is a character model-sheet bake, promote its output
        // to that character's stored sheet.
        final sheetFor = g.params['_sheet_for'] as String?;
        if (sheetFor != null && done.filePath != null) {
          await Db.setCharacterModelSheet(sheetFor, done.filePath);
        }
      } else {
        final sibId = _id();
        final file = await Files.writeOutput(sibId, bytes, ext);
        final sib = GenRecord(
          id: sibId,
          kind: g.kind,
          modelId: g.modelId,
          modelName: g.modelName,
          task: g.task,
          prompt: g.prompt,
          params: g.params,
          refPaths: g.refPaths,
          status: GenStatus.done,
          filePath: Files.rel(file.path),
          width: size.width,
          height: size.height,
          cost: res.cost / res.bytes.length,
          createdAt: g.createdAt + i,
          completedAt: DateTime.now().millisecondsSinceEpoch,
          groupId: g.id,
        );
        await Db.upsert(sib);
        _items.insert(0, sib);
        notifyListeners();
        if (autoSave) await _autoSave(file.path, false);
      }
    }
  }

  Future<void> _runVideo(GenRecord g, ORModel m, GenBackend backend, _SourceFiles src,
      MakeBackend make, bool autoSave, int refMaxSide) async {
    _note(g.id, 'Uploading');
    final frames = <Map<String, String>>[];
    if (src.firstFrame != null) {
      frames.add({
        'url': await Imaging.toDataUrlCompressed(src.firstFrame!, maxSide: refMaxSide),
        'frame_type': 'first_frame',
      });
    }
    if (src.lastFrame != null) {
      frames.add({
        'url': await Imaging.toDataUrlCompressed(src.lastFrame!, maxSide: refMaxSide),
        'frame_type': 'last_frame',
      });
    }
    final refs = <String>[];
    for (final f in src.refs) {
      refs.add(await Imaging.toDataUrlCompressed(f, maxSide: refMaxSide));
    }

    // Resumable backends (OpenRouter) return a job id we can poll and pick up
    // again after a restart. A one-shot backend runs the job to completion in
    // one call; there is no id to resume, so an interruption fails it.
    if (backend.videoResumable) {
      _note(g.id, 'Submitting');
      final job = await backend.createVideo(
        model: m.id,
        prompt: g.prompt,
        params: _videoParams(m, g),
        frames: frames,
        referenceDataUrls: refs,
      );
      final withJob = g.copyWith(jobId: job.id);
      await Db.upsert(withJob);
      _replace(withJob);
      await _pollVideo(withJob, make, m.provider, existingBackend: backend, autoSave: autoSave);
    } else {
      _note(g.id, 'Submitting');
      final res = await backend.runVideo(
        model: m.id,
        prompt: g.prompt,
        params: _videoParams(m, g),
        frames: frames,
        referenceDataUrls: refs,
        onNote: (n) => _note(g.id, n),
      );
      if (_isCancelled(g.id)) return;
      final file = await Files.writeOutput(g.id, res.bytes, 'mp4');
      final done = g.copyWith(
        status: GenStatus.done,
        filePath: Files.rel(file.path),
        cost: res.cost,
        durationSec: (g.params['duration'] as int?) ?? 0,
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await Db.upsert(done);
      _replace(done);
      if (autoSave) await _autoSave(file.path, true);
    }
  }

  /// Polls a resumable video job until it resolves. Runs on its own so it
  /// survives being re-entered after an app restart.
  Future<void> _pollVideo(GenRecord g, MakeBackend make, String provider,
      {GenBackend? existingBackend, bool autoSave = false}) async {
    final backend = existingBackend ?? make(provider);
    _running.add(g.id);
    try {
      final started = DateTime.now();
      var delay = const Duration(seconds: 5);
      while (true) {
        if (DateTime.now().difference(started) > const Duration(hours: 2)) {
          await _fail(g, 'Still not finished after two hours. The job may yet complete; check the provider.');
          return;
        }
        await Future.delayed(delay);
        final job = await backend.pollVideo(g.jobId!);
        if (job.failed) {
          await _fail(g, 'The provider reported the job failed.');
          return;
        }
        if (job.done) {
          if (_isCancelled(g.id)) return;
          _note(g.id, 'Downloading');
          final bytes = await backend.downloadVideo(g.jobId!);
          final file = await Files.writeOutput(g.id, bytes, 'mp4');
          final done = g.copyWith(
            status: GenStatus.done,
            filePath: Files.rel(file.path),
            cost: job.cost,
            durationSec: (g.params['duration'] as int?) ?? 0,
            completedAt: DateTime.now().millisecondsSinceEpoch,
          );
          await Db.upsert(done);
          _replace(done);
          if (autoSave) await _autoSave(file.path, true);
          return;
        }
        final secs = DateTime.now().difference(started).inSeconds;
        _note(g.id, job.status == 'in_progress' ? 'Rendering ${secs}s' : 'Queued ${secs}s');
        // back off gently: video jobs run minutes, not seconds
        if (delay.inSeconds < 15) delay = Duration(seconds: delay.inSeconds + 2);
      }
    } catch (e) {
      if (!_isCancelled(g.id)) await _fail(g, e.toString());
    } finally {
      _running.remove(g.id);
      _cancelled.remove(g.id);
      if (existingBackend == null) backend.close();
      _statusNote.remove(g.id);
      notifyListeners();
    }
  }

  // ---------------- payload shaping ----------------

  /// Only sends parameters the model actually declares, so an option left over
  /// from a previously selected model can never poison the request.
  Map<String, dynamic> _imageParams(ORModel m, GenRecord g) {
    final out = <String, dynamic>{};
    void put(String key) {
      final v = g.params[key];
      if (v == null) return;
      if (!m.params.containsKey(key)) return;
      out[key] = v;
    }

    for (final k in ['aspect_ratio', 'resolution', 'n', 'quality', 'background', 'output_format', 'seed']) {
      put(k);
    }
    // Outpaint drives the aspect through the canvas itself; asking the model
    // for a different ratio on top would crop the composite back off.
    if (g.task == Task.outpaint) out.remove('aspect_ratio');

    for (final k in m.passthrough) {
      final v = g.params[k];
      if (v != null && v != '') out[k] = v;
    }
    return out;
  }

  Map<String, dynamic> _videoParams(ORModel m, GenRecord g) {
    final out = <String, dynamic>{};
    final d = g.params['duration'];
    if (d != null && m.durations.isNotEmpty) out['duration'] = d;
    final r = g.params['resolution'];
    if (r != null && m.resolutions.contains(r)) out['resolution'] = r;
    final a = g.params['aspect_ratio'];
    if (a != null && m.aspectRatios.contains(a)) out['aspect_ratio'] = a;
    if (m.generateAudio && g.params['generate_audio'] != null) {
      out['generate_audio'] = g.params['generate_audio'];
    }
    if (m.seed && g.params['seed'] != null) out['seed'] = g.params['seed'];
    for (final k in m.passthrough) {
      final v = g.params[k];
      if (v != null && v != '') out[k] = v;
    }
    return out;
  }
}

class _SourceFiles {
  _SourceFiles({
    this.refs = const [],
    this.masks = const [],
    this.firstFrame,
    this.lastFrame,
    this.video,
  });
  final List<File> refs;

  /// Index aligned with [refs]; a null entry means that image is unmasked.
  final List<File?> masks;
  final File? firstFrame;
  final File? lastFrame;
  final File? video;

  File? maskFor(int i) => i < masks.length ? masks[i] : null;

  bool get anyMask => masks.any((m) => m != null);

  /// One source, one marked region: the only case where the output can be
  /// composited back over the original.
  bool get isSingleImageInpaint => refs.length == 1 && maskFor(0) != null;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
