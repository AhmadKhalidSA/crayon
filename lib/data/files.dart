import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where generated media and picked reference images live on device.
class Files {
  static Directory? _root;

  /// Must be awaited once at startup so [resolve] and [rel] can run
  /// synchronously afterwards.
  static Future<void> ensureInit() async => root;

  @visibleForTesting
  static void debugReset() => _root = null;

  static Future<Directory> get root async {
    if (_root != null) return _root!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'crayon'));
    if (!await d.exists()) await d.create(recursive: true);
    for (final sub in ['out', 'refs', 'cache']) {
      final s = Directory(p.join(d.path, sub));
      if (!await s.exists()) await s.create(recursive: true);
    }
    _root = d;
    return d;
  }

  /// Stored paths are RELATIVE to [root].
  ///
  /// iOS gives the app container a UUID that changes on reinstall, and can
  /// change on update, so an absolute path saved yesterday points nowhere
  /// today. That is exactly how a gallery full of images turns into a gallery
  /// full of broken tiles after quitting the app. Everything is therefore
  /// stored relative and re-rooted on read.
  static String rel(String absolute) {
    final r = _root;
    if (r == null || absolute.isEmpty) return absolute;
    if (p.isWithin(r.path, absolute)) return p.relative(absolute, from: r.path);
    return absolute;
  }

  /// Turns a stored path back into a usable one. Handles three cases: already
  /// relative, absolute and still valid, and absolute but from an old
  /// container (re-rooted by the segment after the app folder), so rows
  /// written before this fix keep working with no migration.
  static String resolve(String stored) {
    final r = _root;
    if (r == null || stored.isEmpty) return stored;
    if (!p.isAbsolute(stored)) return p.join(r.path, stored);
    if (File(stored).existsSync()) return stored;
    const marker = '/crayon/';
    final i = stored.lastIndexOf(marker);
    if (i >= 0) return p.join(r.path, stored.substring(i + marker.length));
    return stored;
  }

  static File? fileFor(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    return File(resolve(stored));
  }

  static Future<File> writeOutput(String id, Uint8List bytes, String ext) async {
    final r = await root;
    final f = File(p.join(r.path, 'out', '$id.$ext'));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Copies a picked image into app storage so the record keeps working after
  /// the OS clears the picker's temp file.
  static Future<File> importRef(File src) async {
    final r = await root;
    final name = '${DateTime.now().microsecondsSinceEpoch}${p.extension(src.path)}';
    final dst = File(p.join(r.path, 'refs', name));
    await src.copy(dst.path);
    return dst;
  }

  static Future<File> writeRefBytes(Uint8List bytes, String ext) async {
    final r = await root;
    final f = File(p.join(r.path, 'refs', '${DateTime.now().microsecondsSinceEpoch}.$ext'));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static String extFor(String mediaType) {
    if (mediaType.contains('jpeg') || mediaType.contains('jpg')) return 'jpg';
    if (mediaType.contains('webp')) return 'webp';
    if (mediaType.contains('svg')) return 'svg';
    if (mediaType.contains('mp4')) return 'mp4';
    return 'png';
  }

  static Future<int> folderSize() async {
    final r = await root;
    var total = 0;
    await for (final e in r.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<void> deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(resolve(path));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
