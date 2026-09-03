import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/gen_record.dart';
import '../state/catalog_state.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';

/// A live view of the generation queue: what is running (with Cancel) and what
/// failed (with Retry). Reacts to the library as jobs progress.
class JobsSheet extends StatelessWidget {
  const JobsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryState>();
    final active = lib.active;
    final failed = lib.items.where((g) => g.status == GenStatus.failed).toList();

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(T.pad, 12, T.pad, 8),
              child: Row(
                children: [
                  const Text('Jobs',
                      style: TextStyle(color: T.ink, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${active.length} running',
                      style: const TextStyle(color: T.faint, fontSize: 12.5)),
                  const Spacer(),
                  if (active.isNotEmpty)
                    _link('Cancel all', () => lib.cancelAll()),
                  if (failed.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    _link('Clear failed', () => lib.clearFailed()),
                  ],
                ],
              ),
            ),
            Expanded(
              child: (active.isEmpty && failed.isEmpty)
                  ? const Center(
                      child: Text('No active or failed jobs.',
                          style: TextStyle(color: T.faint, fontSize: 13)),
                    )
                  : ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(T.pad, 4, T.pad, 20),
                      children: [
                        if (active.isNotEmpty) ...[
                          _sectionLabel('Running'),
                          for (final g in active) _ActiveRow(g: g, note: lib.noteFor(g.id)),
                        ],
                        if (failed.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _sectionLabel('Failed'),
                          for (final g in failed) _FailedRow(g: g),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: T.faint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );

  static Widget _link(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Text(label,
            style: const TextStyle(color: T.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
}

class _ActiveRow extends StatelessWidget {
  const _ActiveRow({required this.g, this.note});
  final GenRecord g;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.border),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: T.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.prompt.isEmpty ? g.modelName : g.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: T.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(note ?? (g.status == GenStatus.running ? 'Running' : 'Queued'),
                    style: const TextStyle(color: T.faint, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => lib.cancel(g),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: T.border),
                borderRadius: BorderRadius.circular(T.rField),
              ),
              child: const Text('Cancel', style: TextStyle(color: T.ink, fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.g});
  final GenRecord g;

  Future<void> _retry(BuildContext context) async {
    final lib = context.read<LibraryState>();
    final catalog = context.read<CatalogState>();
    final settings = context.read<SettingsState>();
    final m = catalog.byId(g.modelId);
    await lib.regenerate(g, m, (p) => settings.backendForId(p),
        autoSave: settings.autoSaveToGallery, refMaxSide: settings.refMaxSide);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rCard),
        border: Border.all(color: T.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: T.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.prompt.isEmpty ? g.modelName : g.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: T.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(g.error ?? 'Failed',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: T.faint, fontSize: 11.5, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _retry(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: T.border),
                borderRadius: BorderRadius.circular(T.rField),
              ),
              child: const Text('Retry', style: TextStyle(color: T.ink, fontSize: 12.5)),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => lib.remove(g),
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: T.faint),
          ),
        ],
      ),
    );
  }
}
