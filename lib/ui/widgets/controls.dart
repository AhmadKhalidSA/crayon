import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/or_model.dart';
import '../../core/theme.dart';

/// Horizontal wrap of selectable pills for an enum parameter.
class PillWrap extends StatelessWidget {
  const PillWrap({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.labelBuilder,
  });
  final List<String> values;
  final String? selected;
  final ValueChanged<String> onSelect;
  final String Function(String)? labelBuilder;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            Pill(
              label: labelBuilder?.call(v) ?? v,
              selected: v == selected,
              onTap: () => onSelect(v),
            ),
        ],
      );
}

/// Aspect ratio picker that draws the actual shape, so 9:16 reads as a tall
/// box rather than as text you have to decode.
class AspectPicker extends StatelessWidget {
  const AspectPicker({super.key, required this.values, required this.selected, required this.onSelect});
  final List<String> values;
  final String? selected;
  final ValueChanged<String> onSelect;

  static (double, double) _wh(String ar) {
    if (ar == 'auto') return (1, 1);
    final p = ar.split(':');
    if (p.length != 2) return (1, 1);
    return (double.tryParse(p[0]) ?? 1, double.tryParse(p[1]) ?? 1);
  }

  /// The API returns ratios in its own order (1:1, 1:4, 1:8, 2:3 ...), which
  /// is hard to scan when a model offers 18 of them. Show square first, then
  /// landscape widest-last, then portrait tallest-last.
  static List<String> order(List<String> vs) {
    final auto = vs.where((v) => v == 'auto').toList();
    final rest = vs.where((v) => v != 'auto').toList();
    double r(String v) {
      final (w, h) = _wh(v);
      return h == 0 ? 1 : w / h;
    }
    final square = rest.where((v) => r(v) == 1).toList();
    final land = rest.where((v) => r(v) > 1).toList()..sort((a, b) => r(a).compareTo(r(b)));
    final port = rest.where((v) => r(v) < 1).toList()..sort((a, b) => r(b).compareTo(r(a)));
    return [...auto, ...square, ...land, ...port];
  }

  @override
  Widget build(BuildContext context) {
    final values = order(this.values);
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final v = values[i];
          final sel = v == selected;
          final (w, h) = _wh(v);
          const box = 26.0;
          final scale = w > h ? box / w : box / h;
          return GestureDetector(
            onTap: () => onSelect(v),
            child: Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: sel ? T.surfaceHi : T.surface,
                borderRadius: BorderRadius.circular(T.rTight),
                border: Border.all(color: sel ? T.ink : T.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: box,
                    child: Center(
                      child: v == 'auto'
                          ? Icon(Icons.auto_awesome_outlined, size: 17, color: sel ? T.ink : T.muted)
                          : Container(
                              width: (w * scale).clamp(6.0, box),
                              height: (h * scale).clamp(6.0, box),
                              decoration: BoxDecoration(
                                border: Border.all(color: sel ? T.ink : T.muted, width: 1.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(v,
                      style: TextStyle(
                          fontSize: 9.5,
                          color: sel ? T.ink : T.muted,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Integer stepper, used for "number of images".
class Stepper2 extends StatelessWidget {
  const Stepper2({super.key, required this.value, required this.min, required this.max, required this.onChange});
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback? cb) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: cb,
            borderRadius: BorderRadius.circular(T.rTight),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(i, size: 17, color: cb == null ? T.faint : T.ink),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rTight),
        border: Border.all(color: T.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, value > min ? () => onChange(value - 1) : null),
          SizedBox(
            width: 30,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(color: T.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          btn(Icons.add_rounded, value < max ? () => onChange(value + 1) : null),
        ],
      ),
    );
  }
}

/// Duration slider that snaps to the exact seconds a model supports.
class DurationSlider extends StatelessWidget {
  const DurationSlider({super.key, required this.values, required this.value, required this.onChange});
  final List<int> values;
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    if (values.length <= 6) {
      return PillWrap(
        values: values.map((e) => '$e').toList(),
        selected: '$value',
        onSelect: (v) => onChange(int.parse(v)),
        labelBuilder: (v) => '${v}s',
      );
    }
    final sorted = [...values]..sort();
    final idx = sorted.indexOf(value).clamp(0, sorted.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$value seconds',
                style: const TextStyle(color: T.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${sorted.first}s – ${sorted.last}s', style: const TextStyle(color: T.faint, fontSize: 11.5)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            activeTrackColor: T.ink,
            inactiveTrackColor: T.border,
            thumbColor: T.ink,
            overlayColor: T.ink.withValues(alpha: 0.10),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: idx.toDouble(),
            min: 0,
            max: (sorted.length - 1).toDouble(),
            divisions: sorted.length > 1 ? sorted.length - 1 : null,
            onChanged: (v) => onChange(sorted[v.round()]),
          ),
        ),
      ],
    );
  }
}

/// Continuous slider for float passthrough params (creativity, upscale).
class NumSlider extends StatelessWidget {
  const NumSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
    this.decimals = 2,
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;
  final int decimals;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                activeTrackColor: T.ink,
                inactiveTrackColor: T.border,
                thumbColor: T.ink,
                overlayColor: T.ink.withValues(alpha: 0.10),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChange,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(value.toStringAsFixed(decimals),
                textAlign: TextAlign.right,
                style: const TextStyle(color: T.ink, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

/// A labelled on/off row.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChange, this.hint});
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;
  final String? hint;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChange(!value),
        borderRadius: BorderRadius.circular(T.rTight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint!, style: const TextStyle(color: T.faint, fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChange,
                activeColor: T.bg,
                activeTrackColor: T.ink,
                inactiveThumbColor: T.muted,
                inactiveTrackColor: T.surface,
                trackOutlineColor: WidgetStatePropertyAll(value ? T.ink : T.border),
              ),
            ],
          ),
        ),
      );
}

/// Square slot that either shows a picked image or an add affordance.
class ImageSlot extends StatelessWidget {
  const ImageSlot({
    super.key,
    required this.file,
    required this.onPick,
    this.onClear,
    this.label,
    this.size = 78,
    this.index,
  });
  final File? file;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? label;
  final double size;

  /// 1-based position shown in the corner. Reference order is meaningful:
  /// models resolve "the second image" positionally, so the number has to be
  /// visible or the prompt is a guess.
  final int? index;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: Material(
                  color: T.surface,
                  borderRadius: BorderRadius.circular(T.rTight),
                  child: InkWell(
                    onTap: onPick,
                    borderRadius: BorderRadius.circular(T.rTight),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(T.rTight),
                        border: Border.all(color: file == null ? T.border : T.borderHi),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: file == null
                          ? const Center(child: Icon(Icons.add_rounded, size: 20, color: T.muted))
                          : Image.file(file!, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              if (file != null && index != null)
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: T.bg.withValues(alpha: 0.82),
                      shape: BoxShape.circle,
                      border: Border.all(color: T.borderHi),
                    ),
                    child: Text('${index!}',
                        style: const TextStyle(
                            color: T.ink, fontSize: 10, fontWeight: FontWeight.w800, height: 1.1)),
                  ),
                ),
              if (file != null && onClear != null)
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: onClear,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: T.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: T.bg, width: 2),
                      ),
                      child: const Icon(Icons.close_rounded, size: 12, color: T.bg),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: size,
            child: Text(label!,
                style: const TextStyle(color: T.faint, fontSize: 10.5), textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }
}

/// Free-text field used for prompts and text passthrough params.
class TextBox extends StatelessWidget {
  const TextBox({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 4,
    this.onChanged,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: T.ink, fontSize: 15, height: 1.4),
        cursorColor: T.ink,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: T.faint, fontSize: 15),
          filled: true,
          fillColor: T.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
      );
}

/// Empty-state / message block.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, this.icon, this.action});
  final String text;
  final IconData? icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rCard),
          border: Border.all(color: T.border),
        ),
        child: Column(
          children: [
            if (icon != null) ...[Icon(icon, size: 22, color: T.muted), const SizedBox(height: 10)],
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: T.muted, fontSize: 13, height: 1.5)),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      );
}


/// Icon for a task. Real `Icons` constants so Flutter can still tree-shake the
/// icon font (a computed IconData disables that and fails the release build).
IconData taskIcon(Task t) => switch (t) {
      Task.textToImage => Icons.title_rounded,
      Task.imageToImage => Icons.photo_library_outlined,
      Task.edit => Icons.brush_outlined,
      Task.outpaint => Icons.open_in_full_rounded,
      Task.inpaint => Icons.format_paint_outlined,
      Task.textToVideo => Icons.movie_creation_outlined,
      Task.imageToVideo => Icons.animation_rounded,
      Task.frames => Icons.filter_frames_outlined,
      Task.refToVideo => Icons.collections_outlined,
      Task.videoToVideo => Icons.video_library_outlined,
      Task.lipsync => Icons.record_voice_over_outlined,
      Task.upscaleVideo => Icons.high_quality_outlined,
    };

/// Square task button: icon in the box, label underneath. Easier to hit than a
/// pill and the icon carries the meaning at a glance.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.selected, required this.onTap});
  final Task task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: selected ? T.ink : T.surface,
            borderRadius: BorderRadius.circular(T.rTight),
            child: InkWell(
              borderRadius: BorderRadius.circular(T.rTight),
              onTap: onTap,
              child: Container(
                height: 62,
                width: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(T.rTight),
                  border: Border.all(color: selected ? T.ink : T.border),
                ),
                child: Icon(taskIcon(task), size: 23, color: selected ? T.bg : T.ink),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            task.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              color: selected ? T.ink : T.muted,
              fontSize: 10.5,
              height: 1.25,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
