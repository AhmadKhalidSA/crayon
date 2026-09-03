import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/or_model.dart';
import '../core/estimate.dart';
import '../core/imaging.dart';
import '../core/prompt_weight.dart';
import '../core/rail_order.dart';
import '../core/theme.dart';
import '../data/files.dart';
import '../state/catalog_state.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import '../state/studio_state.dart';
import 'aspect_sheet.dart';
import 'brush_screen.dart';
import 'crop_screen.dart';
import 'image_viewer.dart';
import 'model_sheet.dart';
import 'prompt_editor.dart';
import 'source_picker.dart';
import 'shell.dart';
import 'widgets/controls.dart';

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});
  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _prompt = TextEditingController();
  final _passthroughCtl = <String, TextEditingController>{};
  bool _advancedOpen = false;
  String? _lastSyncedPrompt;
  final _railScroll = ScrollController();
  String? _railModelId;

  @override
  void dispose() {
    _railScroll.dispose();
    _prompt.dispose();
    for (final c in _passthroughCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The studio state can be rewritten from elsewhere (Clone / Edit / Animate),
  /// so the text field follows it without fighting the user's cursor.
  void _syncPrompt(StudioState s) {
    if (s.prompt != _lastSyncedPrompt && s.prompt != _prompt.text) {
      _prompt.text = s.prompt;
      _prompt.selection = TextSelection.collapsed(offset: _prompt.text.length);
    }
    _lastSyncedPrompt = s.prompt;
  }

  /// Gallery or history, then a crop step, then it lands in the studio.
  Future<File?> _pickImage() async {
    final picked = await SourcePicker.show(context);
    if (picked == null || !mounted) return null;
    final cropped = await CropScreen.open(context, picked);
    return cropped ?? picked;
  }

  Future<File?> _pickVideo() async {
    try {
      final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (x == null) return null;
      return Files.importRef(File(x.path));
    } catch (e) {
      if (mounted) _toast('Could not open the picker: $e');
      return null;
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Tapping an existing reference: reorder it, swap the picture, or drop it.
  void _refActions(StudioState s, int i) {
    final last = s.refs.length - 1;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Image ${i + 1}',
                    style: const TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            if (i > 0)
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded, size: 19, color: T.ink),
                title: const Text('Make it image 1', style: TextStyle(color: T.ink, fontSize: 14.5)),
                onTap: () {
                  s.moveRef(i, 0);
                  Navigator.pop(ctx);
                },
              ),
            if (i > 0)
              ListTile(
                leading: const Icon(Icons.chevron_left_rounded, size: 19, color: T.ink),
                title: Text('Move earlier (to $i)', style: const TextStyle(color: T.ink, fontSize: 14.5)),
                onTap: () {
                  s.moveRef(i, i - 1);
                  Navigator.pop(ctx);
                },
              ),
            if (i < last)
              ListTile(
                leading: const Icon(Icons.chevron_right_rounded, size: 19, color: T.ink),
                title: Text('Move later (to ${i + 2})', style: const TextStyle(color: T.ink, fontSize: 14.5)),
                onTap: () {
                  s.moveRef(i, i + 1);
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.brush_rounded, size: 19, color: T.ink),
              title: const Text('Draw on it', style: TextStyle(color: T.ink, fontSize: 14.5)),
              subtitle: const Text('Block out faces or anything the model should not see',
                  style: TextStyle(color: T.faint, fontSize: 11.5)),
              onTap: () async {
                Navigator.pop(ctx);
                final src = s.refs.length > i ? s.refs[i] : null;
                if (src == null || !mounted) return;
                final r = await BrushScreen.open(context, src, BrushMode.block);
                if (r?.image != null) s.replaceRefAt(i, r!.image!);
              },
            ),
            ListTile(
              leading: const Icon(Icons.crop_rounded, size: 19, color: T.ink),
              title: const Text('Crop', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(ctx);
                final src = s.refs.length > i ? s.refs[i] : null;
                if (src == null || !mounted) return;
                final c = await CropScreen.open(context, src);
                if (c != null) s.replaceRefAt(i, c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded, size: 19, color: T.ink),
              title: const Text('Replace picture', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(ctx);
                final f = await _pickImage();
                if (f != null) s.replaceRefAt(i, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded, size: 19, color: T.ink),
              title: const Text('Remove', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () {
                s.removeRefAt(i);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    final s = context.read<StudioState>();
    final settings = context.read<SettingsState>();
    final lib = context.read<LibraryState>();

    s.setPrompt(_prompt.text);
    if (!settings.hasKey) {
      _toast('Add your OpenRouter key in Settings first');
      ShellState.of(context)?.go(4);
      return;
    }
    final blocker = s.blocker;
    if (blocker != null) {
      _toast(blocker);
      return;
    }
    final id = await lib.submit(s, (p) => settings.backendForId(p),
        autoSave: settings.autoSaveToGallery, refMaxSide: settings.refMaxSide);
    if (id == null) {
      _toast('Could not start that generation');
      return;
    }
    await settings.rememberModel(s.model!.id, s.kind == Kind.video);
    if (!mounted) return;
    ShellState.of(context)?.go(1);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogState>();
    final s = context.watch<StudioState>();
    _syncPrompt(s);
    final m = s.model;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, catalog, s),
            Expanded(
              child: m == null
                  ? const Center(child: Text('No models available', style: TextStyle(color: T.faint)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(T.pad, 4, T.pad, 24),
                      children: [
                        _modelRail(context, catalog, s, m),
                        const SizedBox(height: 18),
                        if (m.tasks.length > 1) ...[
                          const SectionLabel('Task'),
                          _taskTabs(s, m),
                          const SizedBox(height: 18),
                        ],
                        _sources(context, s, m),
                        _characterBanner(s),
                        _batchSection(context, s, m),
                        SectionLabel(
                          'Prompt',
                          trailing: _prompt.text.trim().isEmpty
                              ? null
                              : Text('${PromptWeight.wordCount(_prompt.text)} words',
                                  style: const TextStyle(color: T.faint, fontSize: 11)),
                        ),
                        _promptField(s),
                        const SizedBox(height: 18),
                        ..._params(context, s, m),
                        _advanced(context, s, m),
                        const SizedBox(height: 8),
                      ],
                    ),
            ),
            _bottomBar(context, s),
          ],
        ),
      ),
    );
  }

  // ---------- header ----------

  Widget _header(BuildContext context, CatalogState catalog, StudioState s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(T.rPill),
              border: Border.all(color: T.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _kindTab(context, catalog, s, Kind.image, 'Image'),
                _kindTab(context, catalog, s, Kind.video, 'Video'),
              ],
            ),
          ),
          const Spacer(),
          Consumer<LibraryState>(
            builder: (_, lib, __) => lib.runningCount == 0
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () => ShellState.of(context)?.go(1),
                    child: Row(
                      children: [
                        const SizedBox(
                            width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: T.muted)),
                        const SizedBox(width: 7),
                        Text('${lib.runningCount} running',
                            style: const TextStyle(color: T.muted, fontSize: 12)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kindTab(BuildContext context, CatalogState catalog, StudioState s, Kind k, String label) {
    final sel = s.kind == k;
    return GestureDetector(
      onTap: () {
        if (sel) return;
        final list = catalog.forKind(k);
        if (list.isEmpty) {
          _toast('No $label models in the catalogue');
          return;
        }
        final settings = context.read<SettingsState>();
        final remembered = catalog.byId(k == Kind.video ? settings.lastVideoModel : settings.lastImageModel);
        s.setKind(k, list);
        if (remembered != null && remembered.kind == k) s.setModel(remembered);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? T.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(T.rPill),
        ),
        child: Text(label,
            style: TextStyle(
                color: sel ? T.bg : T.muted, fontSize: 13.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ---------- model rail ----------

  static const _railNameStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700);
  static const _railPriceStyle = TextStyle(fontSize: 10.5);

  double _textWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  /// Scroll offset that puts chip [index] just inside the left edge. Chip width
  /// is content width plus the 14pt padding on each side; separators are 8pt.
  double _railOffset(List<ORModel> ordered, int index, List<String> favs) {
    var x = 0.0;
    for (var i = 0; i < index; i++) {
      final e = ordered[i];
      final pin = favs.contains(e.id) ? 16.0 : 0.0;
      final w = [
        _textWidth(e.shortName, _railNameStyle) + pin,
        _textWidth(e.priceLabel, _railPriceStyle),
      ].reduce((a, b) => a > b ? a : b);
      x += w + 28 + 8;
    }
    // leave a sliver of the previous chip visible so it reads as scrollable
    return x - 12;
  }

  Widget _modelRail(BuildContext context, CatalogState catalog, StudioState s, ORModel m) {
    final list = catalog.forKind(s.kind);
    final settings = context.watch<SettingsState>();
    final ordered = RailOrder.sort(list, settings.favourites);

    // Bring the selection into view when it changes from anywhere (boot, the
    // model sheet, Clone, Animate). ensureVisible cannot be used: in a lazy
    // horizontal list an off-screen item has no context yet, so the offset is
    // measured from the chips instead.
    if (m.id != _railModelId) {
      final first = _railModelId == null;
      _railModelId = m.id;
      final idx = ordered.indexWhere((e) => e.id == m.id);
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_railScroll.hasClients) return;
          final target = _railOffset(ordered, idx, settings.favourites)
              .clamp(0.0, _railScroll.position.maxScrollExtent);
          if ((target - _railScroll.offset).abs() < 2) return;
          if (first) {
            _railScroll.jumpTo(target);
          } else {
            _railScroll.animateTo(target,
                duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
          }
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Model  ·  hold to pin',
          trailing: GestureDetector(
            onTap: () async {
              final picked = await ModelSheet.show(context, s.kind, m.id);
              if (picked != null) s.setModel(picked);
            },
            child: Row(
              children: [
                Text('All ${list.length}',
                    style: const TextStyle(color: T.paragraph, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right_rounded, size: 15, color: T.paragraph),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            controller: _railScroll,
            itemCount: ordered.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final e = ordered[i];
              final sel = e.id == m.id;
              final fav = settings.isFavourite(e.id);
              return GestureDetector(
                onTap: () => s.setModel(e),
                onLongPress: () async {
                  await settings.toggleFavourite(e.id);
                  if (!mounted) return;
                  _toast(settings.isFavourite(e.id)
                      ? '${e.shortName} pinned to the front'
                      : '${e.shortName} unpinned');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? T.ink : T.surface,
                    borderRadius: BorderRadius.circular(T.rTight),
                    border: Border.all(color: sel ? T.ink : T.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (fav) ...[
                            Icon(Icons.push_pin_rounded, size: 11, color: sel ? T.bg : T.muted),
                            const SizedBox(width: 5),
                          ],
                          Text(e.shortName,
                              style: _railNameStyle.copyWith(color: sel ? T.bg : T.ink)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(e.priceLabel,
                          style: _railPriceStyle.copyWith(
                              color: sel ? T.bg.withValues(alpha: 0.6) : T.faint)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- tasks ----------

  Widget _taskTabs(StudioState s, ORModel m) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: m.tasks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = m.tasks[i];
          return TaskTile(task: t, selected: s.task == t, onTap: () => s.setTask(t));
        },
      ),
    );
  }

  // ---------- source images ----------

  Widget _sources(BuildContext context, StudioState s, ORModel m) {
    final t = s.task;
    if (!t.needsImage && !t.needsVideo && !m.requiresReference) return const SizedBox.shrink();

    Widget block;
    if (t == Task.frames) {
      block = Row(
        children: [
          ImageSlot(
            file: s.firstFrame,
            label: 'First frame',
            onPick: () async {
              final f = await _pickImage();
              if (f != null) s.setFirstFrame(f);
            },
            onClear: () => s.setFirstFrame(null),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: T.faint),
          const SizedBox(width: 12),
          ImageSlot(
            file: s.lastFrame,
            label: 'Last frame',
            onPick: () async {
              final f = await _pickImage();
              if (f != null) s.setLastFrame(f);
            },
            onClear: () => s.setLastFrame(null),
          ),
        ],
      );
    } else if (t == Task.imageToVideo || t == Task.lipsync) {
      block = Row(
        children: [
          ImageSlot(
            file: s.firstFrame,
            label: t == Task.lipsync ? 'Character' : 'Start image',
            onPick: () async {
              final f = await _pickImage();
              if (f != null) s.setFirstFrame(f);
            },
            onClear: () => s.setFirstFrame(null),
          ),
        ],
      );
    } else if (t.needsVideo) {
      block = Row(
        children: [
          ImageSlot(
            file: s.sourceVideo,
            label: 'Source video',
            onPick: () async {
              final f = await _pickVideo();
              if (f != null) s.setSourceVideo(f);
            },
            onClear: () => s.setSourceVideo(null),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Video is uploaded from your device and sent to the model as the source clip.',
                style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.4)),
          ),
        ],
      );
    } else {
      final max = s.maxRefs;
      block = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (var i = 0; i < s.refs.length; i++)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ImageSlot(
                      file: s.refs[i],
                      index: max > 1 ? i + 1 : null,
                      onPick: () => _refActions(s, i),
                      onClear: () => s.removeRefAt(i),
                    ),
                    const SizedBox(height: 6),
                    _maskButton(s, i),
                  ],
                ),
              if (s.refs.length < max)
                ImageSlot(
                  file: null,
                  label: s.refs.isEmpty ? null : 'Add',
                  onPick: () async {
                    final f = await _pickImage();
                    if (f != null) s.addRef(f);
                  },
                ),
            ],
          ),
          if (s.anyMask) ...[
            const SizedBox(height: 10),
            Text(
              s.isSingleImageInpaint
                  ? 'Only the marked area will change. Everything you did not paint comes back '
                    'from your original, pixel for pixel.'
                  : 'The marked areas tell the model which part of each image to work from. '
                    'With more than one source the result is a new picture, so nothing is '
                    'preserved pixel for pixel.',
              style: const TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
            ),
          ],
          if (max > 1 && s.refs.length > 1) ...[
            const SizedBox(height: 10),
            const Text(
              'Order matters. Say "the first image" or "image 2" in your prompt '
              'and the model resolves it by these numbers. Tap an image to reorder it.',
              style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
            ),
          ],
        ],
      );
    }

    final label = switch (t) {
      Task.outpaint => 'Image to extend',
      Task.edit => 'Image to edit',
      Task.refToVideo => 'Reference images',
      Task.videoToVideo || Task.upscaleVideo => 'Source video',
      Task.lipsync => 'Character image',
      _ => 'Source images',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          label,
          trailing: (t == Task.imageToImage || t == Task.edit || t == Task.refToVideo) && s.maxRefs > 1
              ? Text('up to ${s.maxRefs}', style: const TextStyle(color: T.faint, fontSize: 11))
              : null,
        ),
        block,
        if (t == Task.outpaint) ...[
          const SizedBox(height: 14),
          const SectionLabel('Extend to'),
          AspectButton(
            values: m.imageAspects.where((e) => e != 'auto').toList(),
            selected: s.param<String>('aspect_ratio'),
            onSelect: (v) => s.setParam('aspect_ratio', v),
          ),
          const SizedBox(height: 12),
          const Text('How much to add', style: TextStyle(color: T.muted, fontSize: 12)),
          NumSlider(
            value: (s.param<num>('outpaint_zoom') ?? 1.35).toDouble(),
            min: 1.1,
            max: 2.5,
            decimals: 2,
            onChange: (v) => s.setParam('outpaint_zoom', v),
          ),
          const Text(
            'Your image is placed on a larger empty canvas and the model paints the new area. '
            'Bigger values leave more room to invent.',
            style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.4),
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }

  /// Tapping anywhere in the prompt opens the full screen editor. The inline
  /// box stays as a readable preview so the studio still shows the prompt.
  Widget _promptField(StudioState s) {
    final text = _prompt.text;
    final empty = text.trim().isEmpty;
    final hint = s.task == Task.edit
        ? 'Describe the change, e.g. make the jacket red'
        : s.task == Task.upscaleVideo
            ? 'Optional guidance'
            : 'Describe what you want';
    return Material(
      color: T.surface,
      borderRadius: BorderRadius.circular(T.rField),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.rField),
        onTap: () => _openPromptEditor(s),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rField),
            border: Border.all(color: T.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  empty ? hint : text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: empty ? T.faint : T.ink,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_full_rounded, size: 15, color: T.faint),
            ],
          ),
        ),
      ),
    );
  }

  /// Small button under each reference image. Masking belongs to the image,
  /// so two sources can each carry their own marked region.
  Widget _maskButton(StudioState s, int i) {
    final masked = s.refMask(i) != null;
    return SizedBox(
      width: 78,
      child: Material(
        color: masked ? T.ink : T.surface,
        borderRadius: BorderRadius.circular(T.rTight),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rTight),
          onTap: () => _markArea(s, i),
          onLongPress: masked ? () => s.setRefMask(i, null) : null,
          child: Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.rTight),
              border: Border.all(color: masked ? T.ink : T.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(masked ? Icons.check_rounded : Icons.format_paint_outlined,
                    size: 13, color: masked ? T.bg : T.ink),
                const SizedBox(width: 5),
                Text(masked ? 'Masked' : 'Inpaint',
                    style: TextStyle(
                        color: masked ? T.bg : T.paragraph,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markArea(StudioState s, int i) async {
    final src = s.refMask(i) == null ? (i < s.refs.length ? s.refs[i] : null) : s.refs[i];
    if (src == null) return;
    final r = await BrushScreen.open(context, src, BrushMode.mask);
    if (r?.mask == null || !mounted) return;
    if (!await Imaging.maskHasContent(r!.mask!)) {
      if (mounted) _toast('Nothing was painted, so there is no area to change');
      return;
    }
    s.setRefMask(i, r.mask);
  }

  Future<void> _openPromptEditor(StudioState s) async {
    final out = await PromptEditor.open(context, _prompt.text, s.model);
    if (out == null || !mounted) return;
    _prompt.text = out;
    s.setPromptAndNotify(out);
    setState(() {});
  }

  // ---------- parameters ----------

  List<Widget> _params(BuildContext context, StudioState s, ORModel m) {
    final out = <Widget>[];

    if (m.kind == Kind.image) {
      if (m.imageAspects.isNotEmpty && s.task != Task.outpaint) {
        out.addAll([
          const SectionLabel('Aspect ratio'),
          AspectButton(
            values: m.imageAspects,
            selected: s.param<String>('aspect_ratio'),
            onSelect: (v) => s.setParam('aspect_ratio', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.imageResolutions.isNotEmpty) {
        out.addAll([
          const SectionLabel('Resolution'),
          PillWrap(
            values: m.imageResolutions,
            selected: s.param<String>('resolution'),
            onSelect: (v) => s.setParam('resolution', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.qualities.isNotEmpty) {
        out.addAll([
          const SectionLabel('Quality'),
          PillWrap(
            values: m.qualities,
            selected: s.param<String>('quality'),
            onSelect: (v) => s.setParam('quality', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.backgrounds.isNotEmpty) {
        out.addAll([
          const SectionLabel('Background'),
          PillWrap(
            values: m.backgrounds,
            selected: s.param<String>('background'),
            onSelect: (v) => s.setParam('background', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.outputFormats.isNotEmpty) {
        out.addAll([
          const SectionLabel('Format'),
          PillWrap(
            values: m.outputFormats,
            selected: s.param<String>('output_format'),
            onSelect: (v) => s.setParam('output_format', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.maxN > 1) {
        out.addAll([
          const SectionLabel('Images'),
          Row(
            children: [
              Stepper2(
                value: (s.param<int>('n') ?? 1),
                min: 1,
                max: m.maxN,
                onChange: (v) => s.setParam('n', v),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Each image is billed separately.',
                    style: TextStyle(color: T.faint, fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ]);
      }
    } else {
      if (m.durations.isNotEmpty) {
        out.addAll([
          const SectionLabel('Length'),
          DurationSlider(
            values: m.durations,
            value: s.param<int>('duration') ?? m.durations.first,
            onChange: (v) => s.setParam('duration', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.aspectRatios.isNotEmpty) {
        out.addAll([
          const SectionLabel('Aspect ratio'),
          AspectButton(
            values: m.aspectRatios,
            selected: s.param<String>('aspect_ratio'),
            onSelect: (v) => s.setParam('aspect_ratio', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.resolutions.isNotEmpty) {
        out.addAll([
          const SectionLabel('Resolution'),
          PillWrap(
            values: m.resolutions,
            selected: s.param<String>('resolution'),
            onSelect: (v) => s.setParam('resolution', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.upscaleMin != null && m.upscaleMax != null) {
        out.addAll([
          const SectionLabel('Upscale factor'),
          NumSlider(
            value: (s.param<num>('upscale_factor') ?? m.upscaleMin!).toDouble(),
            min: m.upscaleMin!.toDouble(),
            max: m.upscaleMax!.toDouble(),
            onChange: (v) => s.setParam('upscale_factor', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.creativity) {
        out.addAll([
          const SectionLabel('Creativity'),
          NumSlider(
            value: (s.param<num>('creativity') ?? 0.3).toDouble(),
            min: 0,
            max: 1,
            onChange: (v) => s.setParam('creativity', v),
          ),
          const SizedBox(height: 18),
        ]);
      }
      if (m.generateAudio) {
        out.addAll([
          Panel(
            child: SwitchRow(
              label: 'Generate audio',
              hint: 'Turning this off is usually cheaper',
              value: s.param<bool>('generate_audio') ?? true,
              onChange: (v) => s.setParam('generate_audio', v),
            ),
          ),
          const SizedBox(height: 18),
        ]);
      }
    }
    return out;
  }

  // ---------- advanced / passthrough ----------

  Widget _advanced(BuildContext context, StudioState s, ORModel m) {
    final showAll = context.watch<SettingsState>().showAllParams;
    final pass =
        showAll ? m.passthrough.toList() : m.passthrough.where((p) => !_hiddenPassthrough.contains(p)).toList();
    final showSeed = m.supportsSeed;
    if (pass.isEmpty && !showSeed) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _advancedOpen = !_advancedOpen),
          borderRadius: BorderRadius.circular(T.rTight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text('ADVANCED', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 6),
                Icon(_advancedOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16, color: T.faint),
              ],
            ),
          ),
        ),
        if (_advancedOpen)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSeed) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Seed',
                            style: TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 130,
                        child: TextBox(
                          controller: _ctl('seed', s),
                          hint: 'random',
                          keyboardType: TextInputType.number,
                          onChanged: (v) => s.setParam('seed', int.tryParse(v.trim())),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Same seed plus same prompt reproduces a result.',
                      style: TextStyle(color: T.faint, fontSize: 11.5)),
                  if (pass.isNotEmpty) const Divider(height: 26),
                ],
                for (var i = 0; i < pass.length; i++) ...[
                  _passthroughField(s, pass[i]),
                  if (i != pass.length - 1) const SizedBox(height: 12),
                ],
                if (pass.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'These are provider-specific options passed straight through. '
                    'If a provider rejects one, the error appears on the generation.',
                    style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Passthrough params the app already exposes properly, or that would be
  /// meaningless to type by hand.
  static const _hiddenPassthrough = {
    'aspectRatio',
    'ratio',
    'size',
    'audio',
    'images',
    'videos',
    'video',
    'last_image',
    'req_key',
    'cachedContent',
    'keyframes',
    'output_format',
    'random_seed',
    'creativity',
  };

  static const _boolPassthrough = {
    'watermark',
    'aigc_watermark',
    'prompt_optimizer',
    'fast_pretreatment',
    'prompt_extend',
    'enable_prompt_expansion',
    'enhancePrompt',
    'remove_background',
    'caption',
    'return_last_frame',
    'contentModeration',
    'moderation',
    'style_match',
  };

  static const _numPassthrough = {
    'cfg_scale',
    'guidance',
    'steps',
    'strength',
    'safety_tolerance',
    'conditioningScale',
    'expressiveness',
    'intensity',
    'complexity',
    'movement',
    'version',
  };

  TextEditingController _ctl(String key, StudioState s) {
    return _passthroughCtl.putIfAbsent(key, () {
      final v = s.params[key];
      return TextEditingController(text: v == null ? '' : v.toString());
    });
  }

  Widget _passthroughField(StudioState s, String key) {
    final pretty = key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase();
    final label = pretty[0].toUpperCase() + pretty.substring(1);

    if (_boolPassthrough.contains(key)) {
      return SwitchRow(
        label: label,
        value: s.params[key] == true,
        onChange: (v) => s.setParam(key, v ? true : null),
      );
    }
    if (_numPassthrough.contains(key)) {
      return Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 110,
            child: TextBox(
              controller: _ctl(key, s),
              hint: 'default',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => s.setParam(key, num.tryParse(v.trim())),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextBox(
          controller: _ctl(key, s),
          hint: key == 'negative_prompt' ? 'What to avoid' : 'Optional',
          maxLines: key.contains('prompt') ? 3 : 1,
          onChanged: (v) => s.setParam(key, v.trim().isEmpty ? null : v.trim()),
        ),
      ],
    );
  }

  // ---------- character + batch ----------

  Widget _characterBanner(StudioState s) {
    if (s.characterIds.isEmpty) return const SizedBox.shrink();
    final name = s.characterLabel ?? 'Character';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rCard),
          border: Border.all(color: T.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline_rounded, size: 18, color: T.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Tagging as $name',
                  style: const TextStyle(color: T.ink, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: s.clearCharacters,
              child: const Icon(Icons.close_rounded, size: 18, color: T.faint),
            ),
          ],
        ),
      ),
    );
  }

  // Batch pairs a fixed subject (the refs above) with each extra reference and
  // fires one generation per reference. Only meaningful for an image edit / i2i
  // model that takes at least two references.
  bool _batchAllowed(StudioState s, ORModel m) =>
      m.kind == Kind.image &&
      (s.task == Task.edit || s.task == Task.imageToImage) &&
      s.maxRefs >= 2;

  Future<void> _addBatchRefs(StudioState s) async {
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty) return;
      for (final x in picked) {
        final f = await Files.importRef(File(x.path));
        s.addBatchRef(f);
      }
    } catch (e) {
      if (mounted) _toast('Could not add images: $e');
    }
  }

  Future<void> _batchGenerate() async {
    final s = context.read<StudioState>();
    final settings = context.read<SettingsState>();
    final lib = context.read<LibraryState>();
    s.setPrompt(_prompt.text);
    if (!settings.hasKey) {
      _toast('Add your key in Settings first');
      ShellState.of(context)?.go(4);
      return;
    }
    if (s.refs.isEmpty) {
      _toast('Add your subject image above first');
      return;
    }
    if (!s.hasBatch) {
      _toast('Add at least one batch reference');
      return;
    }
    final go = await _confirmBatch(s.batchRefs.length, s.estimate);
    if (go != true) return;
    final n = await lib.submitBatch(s, (p) => settings.backendForId(p),
        autoSave: settings.autoSaveToGallery, refMaxSide: settings.refMaxSide);
    if (n == 0) {
      _toast('Could not start the batch');
      return;
    }
    s.clearBatchRefs();
    if (!mounted) return;
    _toast('Started $n generations');
    ShellState.of(context)?.go(1);
  }

  Future<bool?> _confirmBatch(int n, Estimate per) {
    final totalLabel = per.unknown ? null : Estimate(per.usd * n, exact: per.exact).label;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rCard)),
        title: const Text('Run batch?', style: TextStyle(color: T.ink, fontSize: 17)),
        content: Text(
          totalLabel == null
              ? '$n generations, one per reference.\nCost is billed by the provider.'
              : '$n generations, one per reference.\nAbout $totalLabel total (${per.label} each).',
          style: const TextStyle(color: T.paragraph, fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: T.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Run $n', style: const TextStyle(color: T.ink, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _batchSection(BuildContext context, StudioState s, ORModel m) {
    if (!_batchAllowed(s, m)) return const SizedBox.shrink();
    final refs = s.batchRefs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Batch references',
          trailing: refs.isEmpty
              ? null
              : Text('${refs.length}', style: const TextStyle(color: T.faint, fontSize: 11)),
        ),
        const Text(
          'Each reference below runs as its own generation, paired with your '
          'subject image above. One tap, many results.',
          style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (var i = 0; i < refs.length; i++)
              ImageSlot(
                file: refs[i],
                index: i + 1,
                onPick: () => ImageViewer.show(context, [refs[i]]),
                onClear: () => s.removeBatchRef(i),
              ),
            ImageSlot(
              file: null,
              label: refs.isEmpty ? 'Add references' : 'Add',
              onPick: () => _addBatchRefs(s),
            ),
          ],
        ),
        if (refs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Batch generate (${refs.length})',
                  icon: Icons.auto_awesome_motion_rounded,
                  onTap: _batchGenerate,
                ),
              ),
              const SizedBox(width: 10),
              GhostButton(label: 'Clear', dense: true, onTap: s.clearBatchRefs),
            ],
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }

  // ---------- bottom bar ----------

  Widget _bottomBar(BuildContext context, StudioState s) {
    final est = s.estimate;
    final blocker = s.blocker;
    return Container(
      decoration: const BoxDecoration(
        color: T.bg,
        border: Border(top: BorderSide(color: T.border)),
      ),
      padding: const EdgeInsets.fromLTRB(T.pad, 12, T.pad, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(est.label,
                  style: const TextStyle(color: T.ink, fontSize: 17, fontWeight: FontWeight.w700)),
              Text(est.unknown ? (est.note ?? 'metered') : (est.note ?? 'estimated'),
                  style: const TextStyle(color: T.faint, fontSize: 10.5)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: PrimaryButton(
              label: blocker ?? 'Generate',
              icon: blocker == null ? Icons.auto_awesome_rounded : null,
              onTap: blocker == null ? _generate : null,
            ),
          ),
        ],
      ),
    );
  }
}
