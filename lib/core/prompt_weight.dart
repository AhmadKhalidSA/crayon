/// Prompt emphasis.
///
/// There are two conventions in the wild and they are not interchangeable:
///
/// * **Braces** `{word}` up, `[word]` down, nested to go further:
///   `{{word}}`, `{{{word}}}`. This is the NovelAI lineage and it is what
///   Dreamina emits. Ahmed confirmed this is what it does.
/// * **Numeric** `(word:1.2)`. This is the Automatic1111 / Compel lineage used
///   by Stable Diffusion tooling.
///
/// Neither is understood by the MODEL itself. Both are conventions read by the
/// pipeline in front of it, which is why the same syntax behaves differently
/// depending on whose product you are in. Braces are the default here because
/// that is the one observed working on Seedream through Dreamina.
///
/// [emphasise] is the third option and the only one that needs no parser at
/// all: it says the emphasis in words, which every instruction-following model
/// understands.
enum WeightStyle { braces, numeric }

class PromptWeight {
  static const maxLevel = 10;
  static const minLevel = -10;

  /// True when [open]...[close] wraps the ENTIRE string, rather than the string
  /// merely starting and ending with them ("{a} and {b}" must not count).
  static bool _wrapsWhole(String s, String open, String close) {
    if (s.length < 2 || !s.startsWith(open) || !s.endsWith(close)) return false;
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) return i == s.length - 1;
      }
    }
    return false;
  }

  static final _numeric = RegExp(r'^\((.*):([0-9]*\.?[0-9]+)\)$', dotAll: true);

  /// Emphasis level of a selection. 0 is neutral, positive is stronger.
  static int levelOf(String selection) => _peel(selection).level;

  /// The selection with all emphasis markup removed.
  static String bareText(String selection) => _peel(selection).text;

  static ({String text, int level}) _peel(String selection) {
    var s = selection.trim();
    var level = 0;
    while (true) {
      if (_wrapsWhole(s, '{', '}')) {
        s = s.substring(1, s.length - 1).trim();
        level++;
      } else if (_wrapsWhole(s, '[', ']')) {
        s = s.substring(1, s.length - 1).trim();
        level--;
      } else {
        final m = _numeric.firstMatch(s);
        if (m != null) {
          // map a numeric weight onto the same level scale
          final w = double.tryParse(m.group(2)!) ?? 1.0;
          level += ((w - 1.0) / 0.1).round();
          s = m.group(1)!.trim();
        } else {
          break;
        }
      }
    }
    return (text: s, level: level.clamp(minLevel, maxLevel));
  }

  /// Re-emits [selection] at [level] in [style]. Level 0 returns bare text, so
  /// stepping back to neutral leaves the words clean.
  static String applyLevel(String selection, int level, WeightStyle style) {
    final bare = bareText(selection);
    final l = level.clamp(minLevel, maxLevel);
    if (l == 0 || bare.isEmpty) return bare;

    if (style == WeightStyle.numeric) {
      final w = (1.0 + l * 0.1).clamp(0.1, 2.0);
      return '($bare:${w.toStringAsFixed(1)})';
    }
    // braces: one pair per level, brackets for negative
    final open = l > 0 ? '{' : '[';
    final close = l > 0 ? '}' : ']';
    final n = l.abs();
    return '${open * n}$bare${close * n}';
  }

  static String bump(String selection, {required bool up, WeightStyle style = WeightStyle.braces}) {
    final cur = _peel(selection);
    final next = (cur.level + (up ? 1 : -1)).clamp(minLevel, maxLevel);
    if (next == cur.level) return selection;
    return applyLevel(selection, next, style);
  }

  /// Human label for a level: "neutral", "+2", "-1".
  static String levelLabel(int level) => level == 0 ? 'neutral' : (level > 0 ? '+$level' : '$level');

  /// Plain-language emphasis, appended as a clause. Needs no parser anywhere,
  /// so it works on every model.
  static String emphasise(String prompt, String selection, {required bool strong}) {
    final bare = bareText(selection).trim();
    if (bare.isEmpty) return prompt;
    final clause = strong ? 'Put strong emphasis on $bare.' : 'Keep $bare subtle and understated.';
    final p = prompt.trimRight();
    if (p.toLowerCase().contains(clause.toLowerCase())) return prompt;
    final sep = p.isEmpty ? '' : (p.endsWith('.') || p.endsWith(',') ? ' ' : '. ');
    return '$p$sep$clause';
  }

  /// Removes every emphasis wrapper of both kinds from a whole prompt.
  static String stripAll(String prompt) {
    var out = prompt;
    final numeric = RegExp(r'\(([^()]*?):([0-9]*\.?[0-9]+)\)');
    while (numeric.hasMatch(out)) {
      out = out.replaceAllMapped(numeric, (m) => m.group(1)!);
    }
    final braces = RegExp(r'[{\[]([^{}\[\]]*)[}\]]');
    while (braces.hasMatch(out)) {
      out = out.replaceAllMapped(braces, (m) => m.group(1)!);
    }
    return out;
  }

  /// True when the prompt carries any emphasis markup at all.
  static bool hasMarkup(String prompt) =>
      RegExp(r'[{\[]').hasMatch(prompt) || RegExp(r'\([^()]*:[0-9]').hasMatch(prompt);

  static int wordCount(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;
}
