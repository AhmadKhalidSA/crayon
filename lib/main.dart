import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api/or_model.dart';
import 'core/theme.dart';
import 'data/files.dart';
import 'state/catalog_state.dart';
import 'state/library_state.dart';
import 'state/settings_state.dart';
import 'state/studio_state.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: T.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider(create: (_) => CatalogState()),
        ChangeNotifierProvider(create: (_) => StudioState()),
        ChangeNotifierProvider(create: (_) => LibraryState()),
      ],
      child: const CrayonApp(),
    ),
  );
}

class CrayonApp extends StatefulWidget {
  const CrayonApp({super.key});
  @override
  State<CrayonApp> createState() => _CrayonAppState();
}

class _CrayonAppState extends State<CrayonApp> {
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final settings = context.read<SettingsState>();
    final catalog = context.read<CatalogState>();
    final studio = context.read<StudioState>();
    final library = context.read<LibraryState>();

    // resolve() and rel() need the app folder, and every stored path is
    // relative to it, so this has to happen before any of them are read
    await Files.ensureInit();

    await settings.load();
    await catalog.load();

    // Restore the last used model, else the cheapest capable image model.
    final imgs = catalog.images;
    if (imgs.isNotEmpty) {
      final remembered = catalog.byId(settings.lastImageModel);
      studio.setModel(remembered ?? _defaultImageModel(imgs));
    }

    // bring back exactly what was on screen last time
    await studio.restore((id) => catalog.byId(id));
    if (studio.model == null && imgs.isNotEmpty) {
      studio.setModel(_defaultImageModel(imgs));
    }

    await library.reload();
    if (mounted) setState(() => _booted = true);

    // Background: refresh the OpenRouter catalogue live when a key is present,
    // then re-point the studio at the refreshed instance of the same model.
    unawaited(() async {
      if (settings.hasKey) {
        await catalog.refresh(settings.backend());
      }
      final cur = studio.model;
      if (cur != null) {
        final fresh = catalog.byId(cur.id);
        if (fresh != null) studio.setModel(fresh);
      } else if (catalog.images.isNotEmpty) {
        studio.setModel(_defaultImageModel(catalog.images));
      }
    }());

    // Live account balance, if a key is set.
    if (studio.model != null && settings.hasKey) {
      unawaited(library.refreshCredits(settings.backend()));
    }
    unawaited(library.resumeUnfinished((p) => settings.backendForId(p), catalog.all));
  }

  ORModel _defaultImageModel(List<ORModel> imgs) {
    // Nano Banana is a good, cheap, well-behaved default when present.
    for (final id in [
      'google/gemini-3.1-flash-image',
      'bytedance-seed/seedream-4.5',
      'google/gemini-2.5-flash-image',
    ]) {
      final m = imgs.where((e) => e.id == id).toList();
      if (m.isNotEmpty) return m.first;
    }
    final sorted = [...imgs]..sort((a, b) => a.lowestPrice.compareTo(b.lowestPrice));
    return sorted.first;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crayon',
      debugShowCheckedModeBanner: false,
      theme: T.build(),
      home: _booted ? const Shell() : const _Splash(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: T.bg,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: T.muted),
          ),
        ),
      );
}
