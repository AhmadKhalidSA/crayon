import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/db.dart';
import '../data/files.dart';
import '../data/gen_record.dart';
import 'widgets/controls.dart';

/// Where a source image comes from: the phone's gallery, or something this app
/// already generated.
class SourcePicker {
  static Future<File?> show(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
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
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add an image',
                    style: TextStyle(color: T.ink, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, size: 20, color: T.ink),
              title: const Text('Choose from gallery', style: TextStyle(color: T.ink, fontSize: 15)),
              subtitle: const Text('Photos on this device', style: TextStyle(color: T.faint, fontSize: 11.5)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded, size: 20, color: T.ink),
              title: const Text('From history', style: TextStyle(color: T.ink, fontSize: 15)),
              subtitle:
                  const Text('Something you generated in Crayon', style: TextStyle(color: T.faint, fontSize: 11.5)),
              onTap: () => Navigator.pop(ctx, 'history'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return null;

    if (choice == 'gallery') {
      try {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
        if (x == null) return null;
        return Files.importRef(File(x.path));
      } catch (_) {
        return null;
      }
    }

    if (!context.mounted) return null;
    final picked = await showModalBottomSheet<GenRecord>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _HistorySheet(),
    );
    final f = picked?.file;
    if (f == null || !f.existsSync()) return null;
    return Files.importRef(f);
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet();
  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  final _items = <GenRecord>[];
  bool _loading = true;
  bool _more = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final page = await Db.page(offset: _items.length, kindFilter: 'image', limit: 60);
    if (!mounted) return;
    setState(() {
      _items.addAll(page.where((g) => g.status == GenStatus.done && g.filePath != null));
      _more = page.length >= 60;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Text('From history', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                Text('${_items.length}', style: const TextStyle(color: T.faint, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6, color: T.faint)))
                : _items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Notice(
                          icon: Icons.image_outlined,
                          text: 'Nothing generated yet, so there is no history to pick from.',
                        ),
                      )
                    : GridView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: _items.length + (_more ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _items.length) {
                            _load();
                            return const SizedBox.shrink();
                          }
                          final g = _items[i];
                          return GestureDetector(
                            onTap: () => Navigator.pop(context, g),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(T.rTight),
                              child: Container(
                                color: T.surface,
                                child: Image.file(g.file!, fit: BoxFit.cover),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
