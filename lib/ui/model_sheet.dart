import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/or_model.dart';
import '../core/theme.dart';
import '../state/catalog_state.dart';
import '../state/settings_state.dart';

/// Full model browser. Grouped by brand, searchable, with the capabilities
/// and price of each model visible before you commit to it.
class ModelSheet extends StatefulWidget {
  const ModelSheet({super.key, required this.kind, this.selectedId});
  final Kind kind;
  final String? selectedId;

  static Future<ORModel?> show(BuildContext context, Kind kind, String? selectedId) {
    return showModalBottomSheet<ORModel>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ModelSheet(kind: kind, selectedId: selectedId),
    );
  }

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogState>();
    final groups = catalog.grouped(widget.kind, query: _query);
    final total = groups.values.fold<int>(0, (a, b) => a + b.length);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Text(widget.kind == Kind.image ? 'Image models' : 'Video models',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                Text('$total', style: const TextStyle(color: T.faint, fontSize: 13)),
                const Spacer(),
                if (catalog.refreshing)
                  const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: T.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: T.ink, fontSize: 14),
              cursorColor: T.ink,
              decoration: InputDecoration(
                hintText: 'Search models',
                hintStyle: const TextStyle(color: T.faint, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: T.faint),
                filled: true,
                fillColor: T.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
          const SizedBox(height: 8),
          Expanded(
            child: total == 0
                ? const Center(child: Text('No models match', style: TextStyle(color: T.faint)))
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 14, bottom: 8),
                          child: Text(entry.key.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall),
                        ),
                        for (final m in entry.value)
                          _ModelTile(m: m, selected: m.id == widget.selectedId),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.m, required this.selected});
  final ORModel m;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final caps = <String>[
      for (final t in m.tasks) t.short,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? T.surfaceHi : T.surface,
        borderRadius: BorderRadius.circular(T.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rCard),
          onTap: () => Navigator.pop(context, m),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.rCard),
              border: Border.all(color: selected ? T.ink : T.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(m.shortName,
                          style: const TextStyle(color: T.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    Text(m.priceLabel, style: const TextStyle(color: T.paragraph, fontSize: 12)),
                    const SizedBox(width: 4),
                    // pin to the front of the studio rail
                    Builder(builder: (ctx) {
                      final settings = ctx.watch<SettingsState>();
                      final fav = settings.isFavourite(m.id);
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        padding: EdgeInsets.zero,
                        icon: Icon(fav ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            size: 16, color: fav ? T.ink : T.faint),
                        tooltip: fav ? 'Unpin' : 'Pin to the front',
                        onPressed: () => settings.toggleFavourite(m.id),
                      );
                    }),
                    if (selected) const Icon(Icons.check_circle_rounded, size: 16, color: T.ink),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in caps)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: T.border),
                        ),
                        child: Text(c, style: const TextStyle(color: T.muted, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    if (m.kind == Kind.video && m.durations.isNotEmpty)
                      _meta('${m.durations.first}-${m.durations.last}s'),
                    if (m.kind == Kind.video && m.generateAudio) _meta('audio'),
                    if (m.kind == Kind.video && m.resolutions.isNotEmpty) _meta(m.resolutions.last),
                    if (m.kind == Kind.image && m.imageResolutions.isNotEmpty)
                      _meta(m.imageResolutions.last),
                    if (m.kind == Kind.image && m.maxN > 1) _meta('up to ${m.maxN}'),
                  ],
                ),
                if (m.description.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    m.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: T.faint, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _meta(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: T.bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(s, style: const TextStyle(color: T.faint, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}
