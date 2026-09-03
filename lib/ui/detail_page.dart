import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api/or_model.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/gen_record.dart';
import '../state/catalog_state.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import '../state/studio_state.dart';
import '../data/character.dart';
import 'image_viewer.dart';
import 'shell.dart';
import 'widgets/controls.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.id});
  final String id;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  GenRecord? _g;
  VideoPlayerController? _video;
  bool _busy = false;
  List<Character> _characters = const [];

  LibraryState? _lib;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lib = context.read<LibraryState>()..addListener(_onLibraryChanged);
    });
  }

  /// Reload when the job behind this page finishes, so an open detail view
  /// fills in instead of spinning until you navigate away and back.
  void _onLibraryChanged() {
    final g = _g;
    if (g == null || g.status == GenStatus.done) return;
    final fresh = _lib?.items.where((e) => e.id == widget.id);
    if (fresh != null && fresh.isNotEmpty && fresh.first.status != g.status) _load();
  }

  @override
  void dispose() {
    _lib?.removeListener(_onLibraryChanged);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final g = await Db.byId(widget.id);
    final chars = await Db.characters();
    if (!mounted) return;
    setState(() {
      _g = g;
      _characters = chars;
    });
    final vf = g?.file;
    if (g != null && g.isVideo && vf != null && vf.existsSync()) {
      final c = VideoPlayerController.file(vf);
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
      await c.play();
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    if (g == null) {
      return const Scaffold(
        backgroundColor: T.bg,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: T.muted)),
      );
    }
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(g.modelName),
        actions: [
          IconButton(
            icon: Icon(g.favorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 20),
            onPressed: () async {
              await context.read<LibraryState>().toggleFavourite(g);
              await _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            onPressed: () => _moreSheet(g),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(T.pad, 0, T.pad, 32),
        children: [
          _media(g),
          const SizedBox(height: 16),
          if (g.status == GenStatus.failed) ...[
            Notice(
              icon: Icons.error_outline_rounded,
              text: g.error ?? 'This generation failed.',
              action: GhostButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                dense: true,
                onTap: () => _regenerate(g),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (g.status == GenStatus.done) ...[
            _actionsGrid(g),
            const SizedBox(height: 18),
            if (!g.isVideo) ...[
              const SectionLabel('Edit with an instruction'),
              _presets(g),
              const SizedBox(height: 18),
            ],
          ],
          _inputImages(g),
          _categoryRow(g),
          _charactersRow(g),
          if (g.prompt.isNotEmpty) ...[
            SectionLabel(
              'Prompt',
              trailing: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: g.prompt));
                  _toast('Prompt copied');
                },
                child: const Text('Copy',
                    style: TextStyle(color: T.paragraph, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ),
            Panel(child: SelectableText(g.prompt, style: const TextStyle(color: T.paragraph, fontSize: 14, height: 1.5))),
            const SizedBox(height: 18),
          ],
          const SectionLabel('Details'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                _row('Model', g.modelName),
                _row('Model id', g.modelId, mono: true),
                _row('Task', g.task.label),
                if (g.width > 0) _row('Size', '${g.width} x ${g.height}'),
                if (g.durationSec > 0) _row('Length', '${g.durationSec}s'),
                _row('Cost', g.cost > 0 ? '\$${g.cost.toStringAsFixed(4)}' : 'not reported'),
                _row('Created', _when(g.createdAt)),
                for (final e in g.params.entries)
                  if (e.value != null && '${e.value}'.isNotEmpty) _row(_pretty(e.key), '${e.value}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _pretty(String k) {
    final s = k.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _row(String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(k, style: const TextStyle(color: T.faint, fontSize: 12.5))),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: T.paragraph,
                      fontSize: 12.5,
                      fontFamily: mono ? 'monospace' : null)),
            ),
          ],
        ),
      );

  Widget _media(GenRecord g) {
    if (g.status != GenStatus.done || g.filePath == null) {
      return AspectRatio(
        aspectRatio: g.aspect <= 0 ? 1 : g.aspect,
        child: Container(
          decoration: BoxDecoration(color: T.surface, borderRadius: BorderRadius.circular(T.rCard)),
          child: Center(
            child: g.status == GenStatus.failed
                ? const Icon(Icons.error_outline_rounded, color: T.muted)
                : const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: T.muted)),
          ),
        ),
      );
    }
    if (g.isVideo) {
      final v = _video;
      if (v == null || !v.value.isInitialized) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(color: T.surface, borderRadius: BorderRadius.circular(T.rCard)),
            child: const Center(
                child: SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: T.muted))),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(T.rCard),
        child: AspectRatio(
          aspectRatio: v.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              GestureDetector(
                onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                child: VideoPlayer(v),
              ),
              VideoProgressIndicator(
                v,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: T.ink,
                  bufferedColor: T.borderHi,
                  backgroundColor: T.border,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _fullscreen(g),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(T.rCard),
        child: Image.file(g.file!, fit: BoxFit.contain),
      ),
    );
  }

  /// Fullscreen viewer with double-tap zoom, and swipe left/right across every
  /// finished image in the current gallery view (starting on this one).
  void _fullscreen(GenRecord g) {
    final lib = context.read<LibraryState>();
    final imgs = lib.items
        .where((e) => !e.isVideo && e.status == GenStatus.done && e.file != null)
        .toList();
    var idx = imgs.indexWhere((e) => e.id == g.id);
    if (idx < 0) {
      ImageViewer.show(context, [g.file!], captions: [g.prompt]);
      return;
    }
    ImageViewer.show(context, [for (final e in imgs) e.file!],
        initialIndex: idx, captions: [for (final e in imgs) e.prompt]);
  }

  // ---------- actions ----------

  Widget _actionsGrid(GenRecord g) {
    final catalog = context.read<CatalogState>();
    final hasVideoModels = catalog.videos.isNotEmpty;
    final items = <_Action>[
      _Action('Regenerate', Icons.refresh_rounded, () => _regenerate(g)),
      _Action('Clone', Icons.content_copy_rounded, () => _clone(g)),
      if (!g.isVideo) _Action('Edit', Icons.brush_outlined, () => _sendToStudio(g, Task.edit)),
      if (!g.isVideo) _Action('Outpaint', Icons.open_in_full_rounded, () => _sendToStudio(g, Task.outpaint)),
      if (!g.isVideo && hasVideoModels)
        _Action('Animate', Icons.movie_creation_outlined, () => _animate(g)),
      if (!g.isVideo) _Action('Upscale', Icons.high_quality_outlined, () => _upscaleImage(g)),
      if (g.isVideo) _Action('Upscale', Icons.high_quality_outlined, () => _upscaleVideo(g)),
      _Action('Save', Icons.download_rounded, () => _save(g)),
      _Action('Share', Icons.ios_share_rounded, () => _share(g)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in items)
          SizedBox(
            width: (MediaQuery.of(context).size.width - T.pad * 2 - 16) / 3,
            child: Material(
              color: T.surface,
              borderRadius: BorderRadius.circular(T.rTight),
              child: InkWell(
                borderRadius: BorderRadius.circular(T.rTight),
                onTap: _busy ? null : a.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(T.rTight),
                    border: Border.all(color: T.border),
                  ),
                  child: Column(
                    children: [
                      Icon(a.icon, size: 18, color: T.ink),
                      const SizedBox(height: 6),
                      Text(a.label,
                          style: const TextStyle(color: T.paragraph, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------- input images ----------

  Widget _inputImages(GenRecord g) {
    final refs = g.refFiles;
    if (refs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Input images'),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: refs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _inputImageActions(refs, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(T.rTight),
                child: Image.file(refs[i], width: 76, height: 88, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text('Tap an input to view it or reuse it in a new generation.',
            style: TextStyle(color: T.faint, fontSize: 11.5)),
        const SizedBox(height: 18),
      ],
    );
  }

  void _inputImageActions(List<File> refs, int i) {
    showModalBottomSheet(
      context: context,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.fullscreen_rounded, size: 20, color: T.ink),
              title: const Text('View', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () {
                Navigator.pop(ctx);
                ImageViewer.show(context, refs, initialIndex: i);
              },
            ),
            ListTile(
              leading: const Icon(Icons.brush_outlined, size: 20, color: T.ink),
              title: const Text('Use in a new generation', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () {
                Navigator.pop(ctx);
                _useRefInStudio(refs[i]);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _useRefInStudio(File f) {
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();
    final cur = catalog.byId(_g?.modelId ?? '');
    ORModel? m = (cur != null && cur.maxRefs >= 1) ? cur : null;
    final capable = catalog.images.where((e) => e.maxRefs >= 1).toList()
      ..sort((a, b) => a.lowestPrice.compareTo(b.lowestPrice));
    m ??= capable.isEmpty ? null : capable.first;
    if (m == null) {
      _toast('No model in the catalogue accepts a reference image');
      return;
    }
    final shell = ShellState.of(context);
    studio.setModel(m);
    studio.useAsSource(f, target: Task.imageToImage, m: m);
    Navigator.pop(context);
    shell?.go(0);
    _toast('Added to a new generation');
  }

  // ---------- category ----------

  Widget _categoryRow(GenRecord g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Category'),
        GestureDetector(
          onTap: () => _pickCategory(g),
          child: Panel(
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 16, color: T.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(g.category ?? 'Uncategorised',
                      style: TextStyle(
                          color: g.category != null ? T.ink : T.faint,
                          fontSize: 14,
                          fontWeight: g.category != null ? FontWeight.w600 : FontWeight.w400)),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: T.faint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Future<void> _pickCategory(GenRecord g) async {
    final existing = await Db.categories();
    if (!mounted) return;
    final ctl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration:
                            BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2)))),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text('Category', style: TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextBox(controller: ctl, hint: 'New category name'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: PrimaryButton(
                    label: 'Save',
                    onTap: () async {
                      await _applyCategory(g, ctl.text.trim().isEmpty ? null : ctl.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
                if (existing.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('EXISTING', style: TextStyle(color: T.faint, fontSize: 11, letterSpacing: 1)),
                  ),
                  for (final c in existing)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined, size: 18, color: T.muted),
                      title: Text(c, style: const TextStyle(color: T.ink, fontSize: 14.5)),
                      trailing: g.category == c ? const Icon(Icons.check_rounded, size: 18, color: T.ink) : null,
                      onTap: () async {
                        await _applyCategory(g, c);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                ],
                if (g.category != null)
                  ListTile(
                    leading: const Icon(Icons.clear_rounded, size: 18, color: T.muted),
                    title: const Text('Remove category', style: TextStyle(color: T.paragraph, fontSize: 14.5)),
                    onTap: () async {
                      await _applyCategory(g, null);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyCategory(GenRecord g, String? category) async {
    await Db.setCategory(g.id, category);
    if (mounted) context.read<LibraryState>().refreshOne(g.id);
    await _load();
  }

  // ---------- characters ----------

  Widget _charactersRow(GenRecord g) {
    if (g.isVideo) return const SizedBox.shrink();
    final tagged = _characters.where((c) => g.characterIds.contains(c.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Characters',
          trailing: GhostButton(label: 'Tag', dense: true, onTap: () => _tagCharacters(g)),
        ),
        if (tagged.isEmpty)
          const Panel(
            child: Text('No character tagged. Tag who is in this image so it shows on their page.',
                style: TextStyle(color: T.faint, fontSize: 12.5)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final c in tagged) Pill(label: c.name, selected: true, onTap: () => _tagCharacters(g))],
          ),
        const SizedBox(height: 18),
      ],
    );
  }

  Future<void> _tagCharacters(GenRecord g) async {
    final selected = {...g.characterIds};
    await showModalBottomSheet(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration:
                            BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2)))),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text('Who is in this image?',
                      style: TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (_characters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text('You have no characters yet. Create one on the Characters page.',
                        style: TextStyle(color: T.faint, fontSize: 12.5)),
                  ),
                for (final c in _characters)
                  CheckboxListTile(
                    value: selected.contains(c.id),
                    onChanged: (v) => setSheet(() => v == true ? selected.add(c.id) : selected.remove(c.id)),
                    activeColor: T.ink,
                    checkColor: T.bg,
                    title: Text(c.name, style: const TextStyle(color: T.ink, fontSize: 14.5)),
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: c.cover != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(c.cover!, width: 34, height: 34, fit: BoxFit.cover))
                        : null,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: PrimaryButton(
                    label: 'Save',
                    onTap: () async {
                      await Db.setGenCharacters(g.id, selected.toList());
                      if (mounted) context.read<LibraryState>().refreshOne(g.id);
                      await _load();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// These are ordinary instruction edits sent to an edit-capable model.
  /// Nothing here uses a mask, because OpenRouter's image API exposes none.
  static const _editPresets = <String, String>{
    'Enhance detail': 'Increase the fine detail and sharpness across the whole image. Keep the composition, colours and subject identical.',
    'Relight': 'Relight this scene with warm golden hour light coming from the left. Keep the subject and composition identical.',
    'Remove object': 'Remove the distracting object and reconstruct the background behind it naturally.',
    'Change background': 'Replace the background with a clean neutral studio backdrop. Keep the subject exactly as it is.',
    'Restyle': 'Re-render this image in a cinematic, high contrast editorial style. Keep the subject and layout.',
    'Fix face': 'Improve the facial detail and symmetry naturally. Do not change the identity, expression or framing.',
  };

  Widget _presets(GenRecord g) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in _editPresets.entries)
          Pill(
            label: e.key,
            selected: false,
            onTap: () => _sendToStudio(g, Task.edit, prompt: e.value),
          ),
      ],
    );
  }

  Future<void> _regenerate(GenRecord g) async {
    final settings = context.read<SettingsState>();
    final catalog = context.read<CatalogState>();
    final lib = context.read<LibraryState>();
    if (!settings.hasKey) {
      _toast('Add your OpenRouter key in Settings first');
      return;
    }
    final m = catalog.byId(g.modelId);
    if (m == null) {
      _toast('That model is no longer in the catalogue');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final id = await lib.regenerate(g, m, (p) => settings.backendForId(p),
        autoSave: settings.autoSaveToGallery, refMaxSide: settings.refMaxSide);
    if (id != null && mounted) {
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Regenerating')));
    }
  }

  void _clone(GenRecord g) {
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();
    final shell = ShellState.of(context);
    studio.cloneFrom(g, catalog.byId(g.modelId));
    Navigator.pop(context);
    shell?.go(0);
  }

  /// Sends this output back into the studio as the source of a new job.
  void _sendToStudio(GenRecord g, Task target, {String? prompt}) {
    if (g.filePath == null) return;
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();

    ORModel? m = catalog.byId(g.modelId);
    if (m == null || !m.tasks.contains(target)) {
      // fall back to the cheapest image model that can actually do this task
      final capable = catalog.images.where((e) => e.tasks.contains(target)).toList()
        ..sort((a, b) => a.lowestPrice.compareTo(b.lowestPrice));
      if (capable.isEmpty) {
        _toast('No model in the catalogue supports ${target.label.toLowerCase()}');
        return;
      }
      m = capable.first;
      _toast('Using ${m.shortName} for this');
    }
    final shell = ShellState.of(context);
    studio.setModel(m);
    studio.useAsSource(g.file!, target: target, m: m);
    if (prompt != null) studio.setPromptAndNotify(prompt);
    Navigator.pop(context);
    shell?.go(0);
  }

  void _animate(GenRecord g) {
    if (g.filePath == null) return;
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();
    final capable = catalog.videos.where((e) => e.supportsFirstFrame).toList()
      ..sort((a, b) => a.lowestPrice.compareTo(b.lowestPrice));
    if (capable.isEmpty) {
      _toast('No video model supports a starting image');
      return;
    }
    final m = capable.first;
    final shell = ShellState.of(context);
    final messenger = ScaffoldMessenger.of(context);
    studio.setModel(m);
    studio.useAsSource(g.file!, target: Task.imageToVideo, m: m);
    studio.setPromptAndNotify(g.prompt);
    Navigator.pop(context);
    shell?.go(0);
    messenger.showSnackBar(SnackBar(content: Text('Animating with ${m.shortName}')));
  }

  /// Image "upscale" is a re-render at the model's largest resolution using
  /// the current image as the reference. There is no dedicated image upscaler
  /// on OpenRouter, so this is what upscaling honestly means here.
  void _upscaleImage(GenRecord g) {
    if (g.filePath == null) return;
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();
    final capable = catalog.images
        .where((e) => e.maxRefs >= 1 && e.imageResolutions.isNotEmpty)
        .toList()
      ..sort((a, b) => b.imageResolutions.length.compareTo(a.imageResolutions.length));
    final m = capable.isNotEmpty ? capable.first : catalog.byId(g.modelId);
    if (m == null) {
      _toast('No model available for this');
      return;
    }
    final shell = ShellState.of(context);
    final messenger = ScaffoldMessenger.of(context);
    studio.setModel(m);
    studio.useAsSource(g.file!, target: Task.imageToImage, m: m);
    final res = m.imageResolutions;
    if (res.isNotEmpty) studio.setParam('resolution', res.last);
    studio.setPromptAndNotify(
        'Recreate this exact image at maximum fidelity and resolution. Preserve every detail, colour and proportion. Do not change the content.');
    Navigator.pop(context);
    shell?.go(0);
    messenger.showSnackBar(
        SnackBar(content: Text('Re-rendering at ${res.isNotEmpty ? res.last : "max"} with ${m.shortName}')));
  }

  void _upscaleVideo(GenRecord g) {
    if (g.filePath == null) return;
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();
    final up = catalog.videos.where((e) => e.isUpscaler).toList();
    if (up.isEmpty) {
      _toast('No video upscaler in the catalogue');
      return;
    }
    final m = up.first;
    final shell = ShellState.of(context);
    studio.setModel(m);
    studio.useAsSource(g.file!, target: Task.upscaleVideo, m: m);
    Navigator.pop(context);
    shell?.go(0);
  }

  Future<void> _save(GenRecord g) async {
    if (g.filePath == null) return;
    setState(() => _busy = true);
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      if (g.isVideo) {
        await Gal.putVideo(g.file!.path, album: 'Crayon');
      } else {
        await Gal.putImage(g.file!.path, album: 'Crayon');
      }
      _toast('Saved to your gallery');
    } on GalException catch (e) {
      _toast('Could not save: ${e.type.message}');
    } catch (e) {
      _toast('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(GenRecord g) async {
    if (g.filePath == null) return;
    try {
      await Share.shareXFiles([XFile(g.file!.path)], text: g.prompt);
    } catch (e) {
      _toast('Could not share: $e');
    }
  }

  void _moreSheet(GenRecord g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.copy_rounded, size: 19, color: T.ink),
              title: const Text('Copy model id', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: g.modelId));
                Navigator.pop(ctx);
                _toast('Copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, size: 19, color: T.ink),
              title: const Text('Delete', style: TextStyle(color: T.ink, fontSize: 14.5)),
              subtitle: const Text('Removes the file from this device',
                  style: TextStyle(color: T.faint, fontSize: 11.5)),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<LibraryState>().remove(g);
                if (mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Action {
  _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}
