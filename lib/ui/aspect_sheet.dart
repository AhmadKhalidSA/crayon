import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Aspect ratios grouped the way you actually think about them: square,
/// portrait, landscape. With 18 ratios on Seedream a flat strip is unusable.
class AspectSheet {
  static (double, double) wh(String ar) {
    if (ar == 'auto') return (1, 1);
    final p = ar.split(':');
    if (p.length != 2) return (1, 1);
    return (double.tryParse(p[0]) ?? 1, double.tryParse(p[1]) ?? 1);
  }

  static String category(String ar) {
    if (ar == 'auto') return 'Auto';
    final (w, h) = wh(ar);
    if (w == h) return 'Square';
    return w > h ? 'Landscape' : 'Portrait';
  }

  /// Groups in display order, each sorted from closest-to-square outwards.
  static Map<String, List<String>> group(List<String> values) {
    final out = <String, List<String>>{};
    for (final v in values) {
      out.putIfAbsent(category(v), () => []).add(v);
    }
    double ratio(String v) {
      final (w, h) = wh(v);
      return h == 0 ? 1 : w / h;
    }
    out['Landscape']?.sort((a, b) => ratio(a).compareTo(ratio(b)));
    out['Portrait']?.sort((a, b) => ratio(b).compareTo(ratio(a)));
    const order = ['Auto', 'Square', 'Portrait', 'Landscape'];
    return {
      for (final k in order)
        if (out[k] != null) k: out[k]!,
    };
  }

  static Future<String?> show(BuildContext context, List<String> values, String? selected) {
    final groups = group(values);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
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
                    decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text('Aspect ratio',
                    style: TextStyle(color: T.ink, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              for (final e in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text(e.key.toUpperCase(),
                      style: const TextStyle(
                          color: T.faint, fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final v in e.value)
                        _Tile(value: v, selected: v == selected, onTap: () => Navigator.pop(ctx, v)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.selected, required this.onTap});
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (w, h) = AspectSheet.wh(value);
    const box = 30.0;
    final scale = w > h ? box / w : box / h;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? T.surfaceHi : T.surface,
          borderRadius: BorderRadius.circular(T.rTight),
          border: Border.all(color: selected ? T.ink : T.border),
        ),
        child: Column(
          children: [
            SizedBox(
              height: box,
              child: Center(
                child: value == 'auto'
                    ? Icon(Icons.auto_awesome_outlined, size: 19, color: selected ? T.ink : T.muted)
                    : Container(
                        width: (w * scale).clamp(7.0, box),
                        height: (h * scale).clamp(7.0, box),
                        decoration: BoxDecoration(
                          border: Border.all(color: selected ? T.ink : T.muted, width: 1.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? T.ink : T.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// The button that opens the sheet, showing the current ratio as a shape.
class AspectButton extends StatelessWidget {
  const AspectButton({super.key, required this.values, required this.selected, required this.onSelect});
  final List<String> values;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final v = selected ?? (values.isEmpty ? '1:1' : values.first);
    final (w, h) = AspectSheet.wh(v);
    const box = 22.0;
    final scale = w > h ? box / w : box / h;
    return Material(
      color: T.surface,
      borderRadius: BorderRadius.circular(T.rField),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.rField),
        onTap: () async {
          final picked = await AspectSheet.show(context, values, selected);
          if (picked != null) onSelect(picked);
        },
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rField),
            border: Border.all(color: T.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: box,
                height: box,
                child: Center(
                  child: v == 'auto'
                      ? const Icon(Icons.auto_awesome_outlined, size: 17, color: T.ink)
                      : Container(
                          width: (w * scale).clamp(6.0, box),
                          height: (h * scale).clamp(6.0, box),
                          decoration: BoxDecoration(
                            border: Border.all(color: T.ink, width: 1.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Text(v, style: const TextStyle(color: T.ink, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(AspectSheet.category(v),
                  style: const TextStyle(color: T.faint, fontSize: 12)),
              const Spacer(),
              Text('${values.length}', style: const TextStyle(color: T.faint, fontSize: 12)),
              const Icon(Icons.expand_more_rounded, size: 18, color: T.muted),
            ],
          ),
        ),
      ),
    );
  }
}
