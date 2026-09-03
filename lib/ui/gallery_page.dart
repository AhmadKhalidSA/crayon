import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/character.dart';
import '../data/db.dart';
import '../data/gen_record.dart';
import '../state/library_state.dart';
import 'detail_page.dart';
import 'jobs_sheet.dart';
import 'shell.dart';
import 'widgets/controls.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _searching = false;
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        context.read<LibraryState>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryState>();
    final items = lib.items;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _selectMode ? _selectHeader(lib) : _header(lib),
            if (!_selectMode) _filters(lib),
            Expanded(
              child: items.isEmpty && !lib.loading
                  ? _empty(lib)
                  : RefreshIndicator(
                      onRefresh: lib.reload,
                      color: T.ink,
                      backgroundColor: T.surface,
                      child: MasonryGridView.count(
                        controller: _scroll,
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        padding: const EdgeInsets.fromLTRB(T.pad, 4, T.pad, 24),
                        itemCount: items.length + (lib.hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 1.6, color: T.faint)),
                              ),
                            );
                          }
                          final g = items[i];
                          return _Tile(
                            g: g,
                            note: lib.noteFor(g.id),
                            selectionMode: _selectMode,
                            selected: _selected.contains(g.id),
                            onTap: () => _selectMode ? _toggle(g) : _open(g),
                            onLongPress: () => _enterSelect(g),
                          );
                        },
                      ),
                    ),
            ),
            if (_selectMode) _selectionBar(lib),
          ],
        ),
      ),
    );
  }

  void _open(GenRecord g) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: g.id)));
  }

  // ---------- selection ----------

  void _enterSelect(GenRecord g) => setState(() {
        _selectMode = true;
        _selected.add(g.id);
      });

  void _toggle(GenRecord g) => setState(() {
        if (!_selected.remove(g.id)) _selected.add(g.id);
        if (_selected.isEmpty) _selectMode = false;
      });

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  List<GenRecord> _selectedRecords(LibraryState lib) =>
      lib.items.where((g) => _selected.contains(g.id)).toList();

  Widget _selectHeader(LibraryState lib) {
    final all = lib.items.map((e) => e.id).toSet();
    final allSelected = _selected.length >= all.length && all.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: _exitSelect,
            icon: const Icon(Icons.close_rounded, size: 20, color: T.muted),
          ),
          Text('${_selected.length} selected',
              style: const TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() {
              if (allSelected) {
                _selected.clear();
                _selectMode = false;
              } else {
                _selected.addAll(all);
              }
            }),
            child: Text(allSelected ? 'None' : 'All',
                style: const TextStyle(color: T.muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar(LibraryState lib) {
    final n = _selected.length;
    return Container(
      decoration: const BoxDecoration(
        color: T.bg,
        border: Border(top: BorderSide(color: T.border)),
      ),
      padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _act(Icons.download_rounded, 'Save', n == 0 ? null : () => _saveSelected(lib)),
            _act(Icons.folder_outlined, 'Category', n == 0 ? null : () => _categorizeSelected(lib)),
            _act(Icons.person_outline_rounded, 'Character', n == 0 ? null : () => _tagCharacterSelected(lib)),
            _act(Icons.delete_outline_rounded, 'Delete', n == 0 ? null : () => _deleteSelected(lib)),
          ],
        ),
      ),
    );
  }

  Widget _act(IconData icon, String label, VoidCallback? onTap) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: T.ink),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: T.muted, fontSize: 11)),
              ],
            ),
          ),
        ),
      );

  Future<void> _saveSelected(LibraryState lib) async {
    final sel = _selectedRecords(lib);
    final ok = await lib.saveManyToDevice(sel);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved $ok of ${sel.length} to your phone')));
    _exitSelect();
  }

  Future<void> _deleteSelected(LibraryState lib) async {
    final sel = _selectedRecords(lib);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rCard)),
        title: const Text('Delete selected?', style: TextStyle(color: T.ink, fontSize: 17)),
        content: Text('${sel.length} generations will be permanently deleted.',
            style: const TextStyle(color: T.paragraph, fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: T.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: T.ink, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (yes != true) return;
    await lib.removeMany(sel);
    _exitSelect();
  }

  Future<void> _categorizeSelected(LibraryState lib) async {
    final cats = await Db.categories();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String?>(
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
            ListTile(
              leading: const Icon(Icons.add_rounded, size: 20, color: T.ink),
              title: const Text('New category', style: TextStyle(color: T.ink, fontSize: 14.5)),
              onTap: () async {
                final name = await _askName(ctx);
                if (name != null && name.trim().isNotEmpty) {
                  if (ctx.mounted) Navigator.pop(ctx, name.trim());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_rounded, size: 20, color: T.muted),
              title: const Text('Remove from category', style: TextStyle(color: T.muted, fontSize: 14.5)),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final c in cats)
              ListTile(
                leading: const Icon(Icons.folder_outlined, size: 19, color: T.muted),
                title: Text(c, style: const TextStyle(color: T.ink, fontSize: 14.5)),
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await lib.setCategoryMany(_selected.toList(), chosen.isEmpty ? null : chosen);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Updated ${_selected.length} generations')));
    _exitSelect();
  }

  Future<void> _tagCharacterSelected(LibraryState lib) async {
    final chars = await Db.characters();
    if (!mounted) return;
    if (chars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No characters yet. Create one on the Characters tab.')));
      return;
    }
    final chosen = await showModalBottomSheet<Character>(
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tag as', style: TextStyle(color: T.faint, fontSize: 12.5))),
            ),
            for (final c in chars)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, size: 19, color: T.muted),
                title: Text(c.name, style: const TextStyle(color: T.ink, fontSize: 14.5)),
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await lib.addCharacterMany(_selected.toList(), chosen.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tagged ${_selected.length} as ${chosen.name}')));
    _exitSelect();
  }

  Future<String?> _askName(BuildContext ctx) {
    final c = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: T.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rCard)),
        title: const Text('New category', style: TextStyle(color: T.ink, fontSize: 16)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(color: T.ink),
          cursorColor: T.ink,
          decoration: const InputDecoration(hintText: 'Name', hintStyle: TextStyle(color: T.faint)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Cancel', style: TextStyle(color: T.muted))),
          TextButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('Add', style: TextStyle(color: T.ink, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _openJobs() {
    showModalBottomSheet(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const JobsSheet(),
    );
  }

  Widget _header(LibraryState lib) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 10),
      child: Row(
        children: [
          if (!_searching) ...[
            Text('Gallery', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 8),
            Text('${lib.items.length}', style: const TextStyle(color: T.faint, fontSize: 13)),
            const Spacer(),
            _jobsButton(lib),
            IconButton(
              onPressed: () => setState(() => _searching = true),
              icon: const Icon(Icons.search_rounded, size: 20, color: T.muted),
            ),
          ] else
            Expanded(
              child: TextField(
                controller: _search,
                autofocus: true,
                style: const TextStyle(color: T.ink, fontSize: 14),
                cursorColor: T.ink,
                onChanged: (v) => lib.setFilter(search: v),
                decoration: InputDecoration(
                  hintText: 'Search prompts',
                  hintStyle: const TextStyle(color: T.faint, fontSize: 14),
                  filled: true,
                  fillColor: T.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 17, color: T.muted),
                    onPressed: () {
                      _search.clear();
                      lib.setFilter(search: '');
                      setState(() => _searching = false);
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(T.rField),
                    borderSide: const BorderSide(color: T.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(T.rField),
                    borderSide: const BorderSide(color: T.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(T.rField),
                    borderSide: const BorderSide(color: T.borderHi),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _jobsButton(LibraryState lib) {
    final running = lib.runningCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: _openJobs,
          icon: const Icon(Icons.playlist_play_rounded, size: 22, color: T.muted),
        ),
        if (running > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: T.ink, borderRadius: BorderRadius.circular(8)),
              child: Text('$running',
                  style: const TextStyle(
                      color: T.bg, fontSize: 9, fontWeight: FontWeight.w800, height: 1.3)),
            ),
          ),
      ],
    );
  }

  Widget _filters(LibraryState lib) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: T.pad),
        children: [
          Pill(
            label: 'All',
            selected: lib.kindFilter == null && !lib.favouritesOnly,
            onTap: () => lib.setFilter(kind: null, favourites: false),
          ),
          const SizedBox(width: 8),
          Pill(
            label: 'Images',
            selected: lib.kindFilter == 'image',
            onTap: () => lib.setFilter(kind: 'image', favourites: false),
          ),
          const SizedBox(width: 8),
          Pill(
            label: 'Video',
            selected: lib.kindFilter == 'video',
            onTap: () => lib.setFilter(kind: 'video', favourites: false),
          ),
          const SizedBox(width: 8),
          Pill(
            label: 'Saved',
            selected: lib.favouritesOnly,
            onTap: () => lib.setFilter(kind: null, favourites: !lib.favouritesOnly),
          ),
          const SizedBox(width: 8),
          Pill(
            label: lib.category ?? 'Category',
            selected: lib.category != null,
            onTap: () => _pickCategoryFilter(lib),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCategoryFilter(LibraryState lib) async {
    final cats = await Db.categories();
    if (!mounted) return;
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
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.apps_rounded, size: 19, color: T.ink),
              title: const Text('All categories', style: TextStyle(color: T.ink, fontSize: 14.5)),
              trailing: lib.category == null ? const Icon(Icons.check_rounded, size: 18, color: T.ink) : null,
              onTap: () {
                Navigator.pop(ctx);
                lib.setCategory(null);
              },
            ),
            if (cats.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No categories yet. Add one from an image.',
                      style: TextStyle(color: T.faint, fontSize: 12.5)),
                ),
              ),
            for (final c in cats)
              ListTile(
                leading: const Icon(Icons.folder_outlined, size: 19, color: T.muted),
                title: Text(c, style: const TextStyle(color: T.ink, fontSize: 14.5)),
                trailing: lib.category == c ? const Icon(Icons.check_rounded, size: 18, color: T.ink) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  lib.setCategory(c);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _empty(LibraryState lib) {
    final filtered = lib.kindFilter != null || lib.favouritesOnly || lib.search.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(T.pad),
      children: [
        const SizedBox(height: 60),
        Notice(
          icon: filtered ? Icons.filter_alt_off_rounded : Icons.auto_awesome_outlined,
          text: filtered
              ? 'Nothing matches this filter yet.'
              : 'Nothing generated yet.\nHead to the studio, pick a model and write a prompt.',
          action: filtered
              ? GhostButton(
                  label: 'Clear filters',
                  dense: true,
                  onTap: () {
                    _search.clear();
                    lib.setFilter(kind: null, favourites: false, search: '');
                  },
                )
              : GhostButton(
                  label: 'Open studio',
                  dense: true,
                  icon: Icons.tune_rounded,
                  onTap: () => ShellState.of(context)?.go(0),
                ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.g,
    required this.onTap,
    this.onLongPress,
    this.note,
    this.selectionMode = false,
    this.selected = false,
  });
  final GenRecord g;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? note;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Keep the placeholder the same shape as the eventual output so the grid
    // does not jump when the image lands.
    final ratio = g.aspect <= 0 ? 1.0 : g.aspect;

    Widget body;
    if (g.status == GenStatus.done && g.filePath != null) {
      body = g.isVideo
          ? _videoThumb()
          : Image.file(
              g.file!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _broken(),
            );
    } else if (g.status == GenStatus.failed) {
      body = _failed();
    } else {
      body = _pending();
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(T.rCard),
            child: Stack(
              children: [
                Container(
                  color: T.surface,
                  child: AspectRatio(aspectRatio: ratio, child: body),
                ),
                if (selectionMode)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? T.bg.withValues(alpha: 0.35) : Colors.transparent,
                        border: selected ? Border.all(color: T.ink, width: 2) : null,
                        borderRadius: BorderRadius.circular(T.rCard),
                      ),
                    ),
                  ),
                if (selectionMode)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? T.ink : T.bg.withValues(alpha: 0.5),
                        border: Border.all(color: selected ? T.ink : T.ink.withValues(alpha: 0.7), width: 1.5),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, size: 15, color: T.bg)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (g.isVideo) ...[
                const Icon(Icons.videocam_rounded, size: 12, color: T.faint),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  g.prompt.isEmpty ? g.modelName : g.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: T.faint, fontSize: 11),
                ),
              ),
              if (g.favorite) const Icon(Icons.bookmark_rounded, size: 11, color: T.muted),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _videoThumb() => Stack(
        fit: StackFit.expand,
        children: [
          Container(color: T.surfaceHi),
          const Center(child: Icon(Icons.play_circle_outline_rounded, size: 34, color: T.muted)),
          if (g.durationSec > 0)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(4)),
                child: Text('${g.durationSec}s',
                    style: const TextStyle(color: T.ink, fontSize: 9.5, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      );

  Widget _pending() => Container(
        color: T.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.8, color: T.muted)),
              const SizedBox(height: 10),
              Text(note ?? 'Queued',
                  style: const TextStyle(color: T.muted, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _failed() => Container(
        color: T.surface,
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 20, color: T.muted),
              const SizedBox(height: 8),
              Text(
                g.error ?? 'Failed',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: T.faint, fontSize: 10.5, height: 1.35),
              ),
            ],
          ),
        ),
      );

  Widget _broken() => Container(
        color: T.surface,
        child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 20, color: T.faint)),
      );
}
