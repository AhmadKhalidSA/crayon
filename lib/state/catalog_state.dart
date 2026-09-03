import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../api/gen_backend.dart';
import '../api/or_model.dart';
import '../data/files.dart';

/// The model catalogue. Models are loaded (disk cache first, else the bundled
/// snapshot) and, when a key is present, refreshed live from OpenRouter.
class CatalogState extends ChangeNotifier {
  // provider id -> its bundled snapshot asset
  static const _assets = {
    'openrouter': 'assets/catalog.json',
  };

  final Map<String, List<ORModel>> _byProvider = {};
  List<ORModel> _all = [];
  bool _refreshing = false;
  String? _error;
  int _progress = 0;
  int _progressTotal = 0;
  DateTime? _lastRefresh;

  List<ORModel> get all => _all;
  List<ORModel> get images => _all.where((m) => m.kind == Kind.image).toList();
  List<ORModel> get videos => _all.where((m) => m.kind == Kind.video).toList();
  bool get refreshing => _refreshing;
  String? get error => _error;
  int get progress => _progress;
  int get progressTotal => _progressTotal;
  DateTime? get lastRefresh => _lastRefresh;
  bool get isEmpty => _all.isEmpty;

  List<ORModel> forKind(Kind k) => k == Kind.image ? images : videos;

  ORModel? byId(String id) {
    for (final m in _all) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _remerge() {
    _all = [for (final id in _assets.keys) ...(_byProvider[id] ?? const <ORModel>[])];
  }

  Future<File> _cacheFile(String provider) async =>
      File(p.join((await Files.root).path, 'catalog_$provider.json'));

  /// Load every provider's catalogue (disk cache first, else the bundled
  /// snapshot) and merge into one list.
  Future<void> load() async {
    for (final entry in _assets.entries) {
      final provider = entry.key;
      List<ORModel> models = const [];
      try {
        final f = await _cacheFile(provider);
        if (await f.exists()) models = ORModel.decodeList(await f.readAsString());
      } catch (_) {}
      if (models.isEmpty) {
        try {
          models = ORModel.decodeList(await rootBundle.loadString(entry.value));
        } catch (_) {}
      }
      for (final m in models) {
        m.provider = provider;
      }
      _byProvider[provider] = models;
    }
    _remerge();
    notifyListeners();
  }

  /// Refresh one provider from its backend, cache it, and re-merge.
  Future<void> refresh(GenBackend backend, {bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    _error = null;
    _progress = 0;
    _progressTotal = 0;
    notifyListeners();

    try {
      final models = await backend.listModels(onProgress: (d, t) {
        _progress = d;
        _progressTotal = t;
        notifyListeners();
      });
      if (models.isNotEmpty) {
        for (final m in models) {
          m.provider = backend.id;
        }
        try {
          await (await _cacheFile(backend.id)).writeAsString(ORModel.encodeList(models));
        } catch (_) {}
        _byProvider[backend.id] = models;
        _lastRefresh = DateTime.now();
        _remerge();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      backend.close();
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Models grouped by brand for the picker, optionally filtered to one
  /// [provider] ('' or null = all providers).
  Map<String, List<ORModel>> grouped(Kind k, {String query = '', String? provider}) {
    final q = query.trim().toLowerCase();
    final list = forKind(k).where((m) {
      if (provider != null && provider.isNotEmpty && m.provider != provider) return false;
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) ||
          m.id.toLowerCase().contains(q) ||
          m.description.toLowerCase().contains(q);
    }).toList();
    final out = <String, List<ORModel>>{};
    for (final m in list) {
      out.putIfAbsent(m.brand, () => []).add(m);
    }
    for (final v in out.values) {
      v.sort((a, b) => a.shortName.compareTo(b.shortName));
    }
    final keys = out.keys.toList()..sort();
    return {for (final k2 in keys) k2: out[k2]!};
  }

  static String pretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
}
