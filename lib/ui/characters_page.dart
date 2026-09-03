import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/or_model.dart';
import '../core/theme.dart';
import '../data/character.dart';
import '../data/db.dart';
import '../data/files.dart';
import '../data/gen_record.dart';
import '../state/catalog_state.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import '../state/studio_state.dart';
import 'detail_page.dart';
import 'image_viewer.dart';
import 'model_sheet.dart';
import 'shell.dart';
import 'widgets/controls.dart';

/// A person/subject you reuse. Create one with a name + reference images; every
/// generation tagged with the character is browsable from their page.
class CharactersPage extends StatefulWidget {
  const CharactersPage({super.key});
  @override
  State<CharactersPage> createState() => _CharactersPageState();
}

class _CharactersPageState extends State<CharactersPage> {
  List<Character> _chars = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Db.characters();
    if (!mounted) return;
    setState(() {
      _chars = c;
      _loaded = true;
    });
  }

  Future<List<String>> _pickImages() async {
    final xs = await ImagePicker().pickMultiImage(imageQuality: 100);
    final out = <String>[];
    for (final x in xs) {
      final f = await Files.importRef(File(x.path));
      out.add(Files.rel(f.path));
    }
    return out;
  }

  Future<void> _create() async {
    final ctl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2)))),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('New character',
                    style: TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextBox(controller: ctl, hint: 'Name, e.g. Ahmed'),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PrimaryButton(
                  label: 'Add images & create',
                  icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final name = ctl.text.trim();
                    if (name.isEmpty) return;
                    final imgs = await _pickImages();
                    final id = 'c${DateTime.now().microsecondsSinceEpoch}';
                    await Db.upsertCharacter(Character(
                      id: id,
                      name: name,
                      coverPath: imgs.isNotEmpty ? imgs.first : null,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                    ));
                    for (final path in imgs) {
                      await Db.addCharacterImage(id, path);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 10),
              child: Row(
                children: [
                  Text('Characters', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 8),
                  Text('${_chars.length}', style: const TextStyle(color: T.faint, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded, color: T.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: T.muted))
                  : _chars.isEmpty
                      ? _empty()
                      : GridView.count(
                          crossAxisCount: 2,
                          padding: const EdgeInsets.fromLTRB(T.pad, 4, T.pad, 24),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.82,
                          children: [for (final c in _chars) _card(c)],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline_rounded, size: 40, color: T.muted),
              const SizedBox(height: 14),
              const Text('No characters yet',
                  style: TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Create a character with their reference images, then reuse them and see everything you made with them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: T.faint, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: 'New character', icon: Icons.add_rounded, onTap: _create),
            ],
          ),
        ),
      );

  Widget _card(Character c) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => CharacterDetailPage(id: c.id)));
        _load();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(T.rCard),
              child: c.cover != null
                  ? Image.file(c.cover!, fit: BoxFit.cover, width: double.infinity)
                  : Container(
                      color: T.surface,
                      child: const Center(child: Icon(Icons.person_outline_rounded, color: T.muted, size: 30)),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${c.genCount} image${c.genCount == 1 ? '' : 's'} · ${c.imagePaths.length} ref',
              style: const TextStyle(color: T.faint, fontSize: 11)),
        ],
      ),
    );
  }
}

/// One character: their reference images (add/remove/reuse), rename/delete, and
/// every generation tagged with them.
class CharacterDetailPage extends StatefulWidget {
  const CharacterDetailPage({super.key, required this.id});
  final String id;
  @override
  State<CharacterDetailPage> createState() => _CharacterDetailPageState();
}

class _CharacterDetailPageState extends State<CharacterDetailPage> {
  Character? _c;
  List<GenRecord> _gens = const [];
  bool _baking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Db.character(widget.id);
    final gens = await Db.page(offset: 0, limit: 200, characterId: widget.id);
    if (!mounted) return;
    setState(() {
      _c = c;
      _gens = gens;
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _addImages() async {
    final xs = await ImagePicker().pickMultiImage(imageQuality: 100);
    for (final x in xs) {
      final f = await Files.importRef(File(x.path));
      await Db.addCharacterImage(widget.id, Files.rel(f.path));
    }
    await _load();
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: _c?.name ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Rename', style: TextStyle(color: T.ink, fontSize: 16)),
        content: TextBox(controller: ctl, hint: 'Name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (ctl.text.trim().isNotEmpty) await Db.renameCharacter(widget.id, ctl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              await _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    await Db.deleteCharacter(widget.id);
    if (mounted) Navigator.pop(context);
  }

  void _useInStudio() {
    final c = _c;
    if (c == null) return;
    // Prefer the baked model sheet: one clean reference = cheaper AND more
    // consistent than re-feeding raw photos every time.
    final useSheet = c.hasSheet;
    final imgs = useSheet
        ? [c.modelSheet!]
        : c.images.where((f) => f.existsSync()).toList();
    if (imgs.isEmpty) {
      _toast('Add a reference image or bake a model sheet first');
      return;
    }
    final studio = context.read<StudioState>();
    final catalog = context.read<CatalogState>();
    final capable = catalog.images.where((e) => e.maxRefs >= 1).toList()
      ..sort((a, b) => a.lowestPrice.compareTo(b.lowestPrice));
    if (capable.isEmpty) {
      _toast('No model accepts a reference image');
      return;
    }
    final m = capable.first;
    final shell = ShellState.of(context);
    studio.startWithCharacter(c.id, c.name, imgs, m);
    Navigator.pop(context);
    shell?.go(0);
    _toast(useSheet
        ? 'Started with ${c.name}\'s model sheet'
        : 'Started a generation with ${c.name}');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Text(c?.name ?? 'Character'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: _rename),
          IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), onPressed: _delete),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: T.muted))
          : ListView(
              padding: const EdgeInsets.fromLTRB(T.pad, 0, T.pad, 32),
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SectionLabel('Reference images'),
                    const Spacer(),
                    GhostButton(label: 'Add', icon: Icons.add_rounded, dense: true, onTap: _addImages),
                  ],
                ),
                SizedBox(
                  height: 96,
                  child: c.images.isEmpty
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No reference images yet.', style: TextStyle(color: T.faint, fontSize: 12.5)))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: c.images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () => ImageViewer.show(context, c.images, initialIndex: i),
                            onLongPress: () => _removeImage(c, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(T.rTight),
                              child: Image.file(c.images[i], width: 80, height: 96, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                const Text('Long-press a reference to remove it.',
                    style: TextStyle(color: T.faint, fontSize: 11)),
                _sheetSection(c),
                const SizedBox(height: 14),
                PrimaryButton(
                    label: 'New generation with ${c.name}',
                    icon: Icons.auto_awesome_rounded,
                    onTap: _useInStudio),
                if (c.hasSheet)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Uses the model sheet as the single reference.',
                        style: TextStyle(color: T.faint, fontSize: 11)),
                  ),
                const SizedBox(height: 20),
                SectionLabel('Made with ${c.name}', trailing: Text('${_gens.length}',
                    style: const TextStyle(color: T.faint, fontSize: 12))),
                const SizedBox(height: 6),
                if (_gens.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Nothing tagged yet. Open an image and tag this character to see it here.',
                        style: TextStyle(color: T.faint, fontSize: 12.5)),
                  )
                else
                  MasonryGridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    itemCount: _gens.length,
                    itemBuilder: (_, i) {
                      final g = _gens[i];
                      return GestureDetector(
                        onTap: () async {
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => DetailPage(id: g.id)));
                          _load();
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(T.rCard),
                          child: g.file != null
                              ? Image.file(g.file!, fit: BoxFit.cover)
                              : Container(height: 120, color: T.surface),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  Future<void> _removeImage(Character c, int i) async {
    await Db.removeCharacterImage(c.id, c.imagePaths[i]);
    await _load();
  }

  // ---------------- model sheet ----------------

  Widget _sheetSection(Character c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const SectionLabel('Model sheet'),
            const Spacer(),
            if (c.hasSheet && !_baking)
              GhostButton(
                  label: 'Re-bake',
                  icon: Icons.refresh_rounded,
                  dense: true,
                  onTap: () => _bakeSheet(c)),
          ],
        ),
        if (_baking)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(T.rCard),
              border: Border.all(color: T.border),
            ),
            child: const Row(
              children: [
                SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: T.muted)),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Baking the model sheet… it shows up here and in the gallery when done.',
                      style: TextStyle(color: T.muted, fontSize: 12.5, height: 1.4)),
                ),
              ],
            ),
          )
        else if (c.hasSheet) ...[
          GestureDetector(
            onTap: () => ImageViewer.show(context, [c.modelSheet!]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(T.rCard),
              child: Image.file(c.modelSheet!, fit: BoxFit.contain, width: double.infinity),
            ),
          ),
          const SizedBox(height: 6),
          const Text('360 turnaround reference. New generations use just this one image.',
              style: TextStyle(color: T.faint, fontSize: 11)),
        ] else ...[
          const Text(
            'Bake a 360 turnaround from the photos above. Do it once — then every '
            'new generation uses this single sheet for a consistent look at low cost.',
            style: TextStyle(color: T.faint, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
              label: 'Bake model sheet',
              icon: Icons.auto_awesome_motion_rounded,
              onTap: () => _bakeSheet(c)),
        ],
      ],
    );
  }

  ORModel? _defaultSheetModel(CatalogState catalog) {
    final withRefs = catalog.images.where((e) => e.maxRefs >= 2).toList();
    final pool = withRefs.isNotEmpty ? withRefs : catalog.images.toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => a.lowestPrice.compareTo(b.lowestPrice));
    return pool.first;
  }

  Future<void> _bakeSheet(Character c) async {
    if (c.images.isEmpty) {
      _toast('Add reference photos first');
      return;
    }
    final settings = context.read<SettingsState>();
    final catalog = context.read<CatalogState>();
    var model = _defaultSheetModel(catalog);
    if (model == null) {
      _toast('No image model available');
      return;
    }
    final selected = <int>{for (var i = 0; i < c.images.length; i++) i};
    final promptCtl = TextEditingController(
        text: (c.sheetPrompt?.trim().isNotEmpty ?? false)
            ? c.sheetPrompt!
            : settings.characterSheetPrompt);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final cap = model!.maxRefs < 1 ? 1 : model!.maxRefs;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.86),
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
                      child: Text('Bake model sheet',
                          style: TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          // model
                          const SectionLabel('Model'),
                          GestureDetector(
                            onTap: () async {
                              final picked = await ModelSheet.show(ctx, Kind.image, model!.id);
                              if (picked != null) setModal(() => model = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: T.surface,
                                borderRadius: BorderRadius.circular(T.rField),
                                border: Border.all(color: T.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(model!.shortName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                                  ),
                                  const Icon(Icons.unfold_more_rounded, size: 18, color: T.muted),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text('Pick a model that accepts reference images for the most consistent sheet.',
                              style: TextStyle(color: T.faint, fontSize: 11)),
                          const SizedBox(height: 16),
                          // photos
                          SectionLabel('Photos to feed',
                              trailing: Text('up to $cap',
                                  style: const TextStyle(color: T.faint, fontSize: 11))),
                          SizedBox(
                            height: 84,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: c.images.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final on = selected.contains(i);
                                return GestureDetector(
                                  onTap: () => setModal(() => on ? selected.remove(i) : selected.add(i)),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(T.rTight),
                                        child: Opacity(
                                          opacity: on ? 1 : 0.4,
                                          child: Image.file(c.images[i],
                                              width: 70, height: 84, fit: BoxFit.cover),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Icon(
                                            on
                                                ? Icons.check_circle_rounded
                                                : Icons.radio_button_unchecked_rounded,
                                            size: 18,
                                            color: on ? T.ink : Colors.white70),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pick the clearest, most consistent shots. Blurry or heavy-makeup photos can '
                            'confuse the reconstruction. ${selected.length > cap ? 'Only the first $cap will be used.' : ''}',
                            style: const TextStyle(color: T.faint, fontSize: 11, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          // prompt
                          Row(
                            children: [
                              const SectionLabel('Prompt'),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setModal(
                                    () => promptCtl.text = SettingsState.defaultSheetPrompt),
                                child: const Text('Reset',
                                    style: TextStyle(color: T.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 16),
                              GestureDetector(
                                onTap: () async {
                                  await settings.setCharacterSheetPrompt(promptCtl.text);
                                  _toast('Saved as your default prompt');
                                },
                                child: const Text('Save as default',
                                    style: TextStyle(color: T.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          TextBox(controller: promptCtl, hint: 'How to build the sheet', maxLines: 10),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: PrimaryButton(
                        label: 'Bake sheet (uses credits)',
                        icon: Icons.auto_awesome_motion_rounded,
                        onTap: () async {
                          final imgs = [for (final i in selected) c.images[i]].take(cap).toList();
                          if (imgs.isEmpty) {
                            _toast('Pick at least one photo');
                            return;
                          }
                          final prompt = promptCtl.text.trim();
                          final lib = context.read<LibraryState>();
                          await Db.setCharacterSheetPrompt(c.id, prompt);
                          final id = await lib.submitModelSheet(
                            charId: c.id,
                            model: model!,
                            images: imgs,
                            prompt: prompt,
                            make: (p) => settings.backendForId(p),
                            autoSave: settings.autoSaveToGallery,
                            refMaxSide: settings.refMaxSide,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (id == null) {
                            _toast('Could not start the bake');
                            return;
                          }
                          setState(() => _baking = true);
                          _watchSheet(id);
                          _toast('Baking ${c.name}\'s model sheet…');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _watchSheet(String genId) {
    final lib = context.read<LibraryState>();
    void cb() {
      GenRecord? g;
      for (final e in lib.items) {
        if (e.id == genId) {
          g = e;
          break;
        }
      }
      if (g == null) return;
      if (g.status == GenStatus.done || g.status == GenStatus.failed) {
        lib.removeListener(cb);
        if (!mounted) return;
        setState(() => _baking = false);
        if (g.status == GenStatus.done) {
          _load();
          _toast('Model sheet ready');
        } else {
          _toast('Sheet bake failed — try again');
        }
      }
    }

    lib.addListener(cb);
  }
}
