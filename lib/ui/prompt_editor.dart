import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../api/enhance.dart';
import '../api/or_model.dart';
import '../core/prompt_weight.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../state/settings_state.dart';
import '../state/studio_state.dart';
import 'widgets/controls.dart';

/// Full screen prompt writing surface: counts, selection emphasis, and a
/// personal library of saved prompts.
class PromptEditor extends StatefulWidget {
  const PromptEditor({super.key, required this.initial, required this.model});
  final String initial;
  final ORModel? model;

  static Future<String?> open(BuildContext context, String initial, ORModel? model) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PromptEditor(initial: initial, model: model),
      ),
    );
  }

  @override
  State<PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<PromptEditor> {
  late final TextEditingController _c;
  final _focus = FocusNode();
  bool _saved = false;
  bool _enhancing = false;

  /// The text before the last enhance, so it can be put back in one tap.
  String? _beforeEnhance;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
    _c.addListener(_onChanged);
    _refreshSavedFlag();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _refreshSavedFlag() async {
    final v = await Db.isPromptSaved(_c.text);
    if (mounted) setState(() => _saved = v);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  TextSelection get _sel => _c.selection;
  bool get _hasSelection => _sel.isValid && !_sel.isCollapsed;
  String get _selectedText => _hasSelection ? _sel.textInside(_c.text) : '';

  /// Replaces the current selection, keeping it selected so weight can be
  /// stepped repeatedly without re-selecting the words each time.
  void _replaceSelection(String replacement) {
    if (!_hasSelection) return;
    final start = _sel.start;
    final text = _c.text.replaceRange(start, _sel.end, replacement);
    _c.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: start + replacement.length),
    );
  }

  void _bump({required bool up}) {
    if (!_hasSelection) return;
    final cur = _selectedText;
    final style = context.read<SettingsState>().weightStyle;
    final next = PromptWeight.bump(cur, up: up, style: style);
    if (next == cur) return;
    _replaceSelection(next);
    HapticFeedback.selectionClick();
  }

  void _emphasise({required bool strong}) {
    if (!_hasSelection) return;
    final out = PromptWeight.emphasise(_c.text, _selectedText, strong: strong);
    _c.value = TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
    _toast(strong ? 'Emphasis added in words' : 'Toned down in words');
  }

  Future<void> _save() async {
    final t = _c.text.trim();
    if (t.isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    await Db.savePrompt(t);
    await _refreshSavedFlag();
    if (mounted) _toast('Prompt saved');
  }

  /// Rewrites the prompt with a small text model and shows the result. The
  /// original is kept so one tap puts it back.
  Future<void> _enhance() async {
    final settings = context.read<SettingsState>();
    final studio = context.read<StudioState>();
    // Prompt enhancement always runs on an OpenRouter chat model, whatever the
    // active image provider is, so it needs the OpenRouter key specifically.
    if (settings.openRouterKey.trim().isEmpty) {
      _toast('Add your OpenRouter key in Settings to enhance prompts');
      return;
    }
    if (_c.text.trim().isEmpty) {
      _toast('Write something to enhance');
      return;
    }
    setState(() => _enhancing = true);
    final api = PromptEnhancer(settings.openRouterKey);
    try {
      final out = await api.enhance(
        prompt: _c.text,
        target: widget.model,
        task: studio.task,
        model: settings.enhanceModel,
      );
      if (!mounted) return;
      final before = _c.text;
      setState(() {
        _beforeEnhance = before;
        _c.value = TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
        _enhancing = false;
      });
      await _refreshSavedFlag();
    } catch (e) {
      if (mounted) {
        setState(() => _enhancing = false);
        _toast('$e');
      }
    } finally {
      api.close();
    }
  }

  void _undoEnhance() {
    final before = _beforeEnhance;
    if (before == null) return;
    setState(() {
      _c.value = TextEditingValue(text: before, selection: TextSelection.collapsed(offset: before.length));
      _beforeEnhance = null;
    });
  }

  Future<void> _openLibrary() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: T.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _SavedPromptsSheet(),
    );
    if (picked != null && mounted) {
      _c.value = TextEditingValue(text: picked, selection: TextSelection.collapsed(offset: picked.length));
      await _refreshSavedFlag();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chars = _c.text.characters.length;
    final words = PromptWeight.wordCount(_c.text);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Prompt'),
        actions: [
          _enhancing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                      child: SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: T.muted))),
                )
              : IconButton(
                  tooltip: 'Enhance this prompt',
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                  onPressed: _enhance,
                ),
          IconButton(
            tooltip: 'Saved prompts',
            icon: const Icon(Icons.bookmarks_outlined, size: 20),
            onPressed: _openLibrary,
          ),
          IconButton(
            tooltip: _saved ? 'Already saved' : 'Save this prompt',
            icon: Icon(_saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, size: 20),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(T.pad, 4, T.pad, 4),
              child: TextField(
                controller: _c,
                focusNode: _focus,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: T.ink, fontSize: 16, height: 1.5),
                cursorColor: T.ink,
                decoration: const InputDecoration(
                  hintText: 'Describe what you want',
                  hintStyle: TextStyle(color: T.faint, fontSize: 16),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          _enhanceBar(),
          _selectionBar(),
          _footer(chars, words),
        ],
      ),
    );
  }

  Widget _enhanceBar() {
    if (_beforeEnhance == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(T.pad, 10, T.pad, 10),
      decoration: const BoxDecoration(
        color: T.surfaceHi,
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high_rounded, size: 14, color: T.ink),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Rewritten. Keep it, or put your words back.',
                style: TextStyle(color: T.paragraph, fontSize: 12)),
          ),
          GestureDetector(
            onTap: _undoEnhance,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('Revert',
                  style: TextStyle(color: T.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    if (!_hasSelection) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(T.pad, 10, T.pad, 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: T.border))),
        child: Row(
          children: [
            const Icon(Icons.text_fields_rounded, size: 14, color: T.faint),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Select a word or phrase to change its emphasis',
                  style: TextStyle(color: T.faint, fontSize: 11.5)),
            ),
            if (PromptWeight.hasMarkup(_c.text))
              GestureDetector(
                onTap: () {
                  final out = PromptWeight.stripAll(_c.text);
                  _c.value =
                      TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
                },
                child: const Text('Clear weights',
                    style: TextStyle(color: T.paragraph, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );
    }

    final level = PromptWeight.levelOf(_selectedText);
    final style = context.watch<SettingsState>().weightStyle;
    final bare = PromptWeight.bareText(_selectedText);
    final preview = bare.length > 24 ? '${bare.substring(0, 24)}…' : bare;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(T.pad, 10, T.pad, 10),
      decoration: const BoxDecoration(
        color: T.surface,
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('"$preview"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: T.ink, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              _miniBtn(Icons.remove_rounded, () => _bump(up: false)),
              Container(
                width: 62,
                alignment: Alignment.center,
                child: Text(PromptWeight.levelLabel(level),
                    style: TextStyle(
                        color: level == 0 ? T.faint : T.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              _miniBtn(Icons.add_rounded, () => _bump(up: true)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Emphasise in words',
                  dense: true,
                  icon: Icons.north_east_rounded,
                  onTap: () => _emphasise(strong: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GhostButton(
                  label: 'Tone down',
                  dense: true,
                  icon: Icons.south_west_rounded,
                  onTap: () => _emphasise(strong: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  style == WeightStyle.braces
                      ? 'Plus and minus wrap the words in braces, {like} {{this}}, the way Dreamina does. '
                        'Minus goes the other way with [brackets].'
                      : 'Plus and minus write (text:weight), the Stable Diffusion form.',
                  style: const TextStyle(color: T.faint, fontSize: 10.5, height: 1.4),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.read<SettingsState>().setWeightStyle(
                    style == WeightStyle.braces ? WeightStyle.numeric : WeightStyle.braces),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(T.rPill),
                    border: Border.all(color: T.border),
                  ),
                  child: Text(style == WeightStyle.braces ? '{ }' : '( : )',
                      style: const TextStyle(color: T.ink, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData i, VoidCallback onTap) => Material(
        color: T.bg,
        borderRadius: BorderRadius.circular(T.rTight),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rTight),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.rTight),
              border: Border.all(color: T.border),
            ),
            child: Icon(i, size: 16, color: T.ink),
          ),
        ),
      );

  Widget _footer(int chars, int words) {
    return Container(
      decoration: const BoxDecoration(
        color: T.bg,
        border: Border(top: BorderSide(color: T.border)),
      ),
      padding: const EdgeInsets.fromLTRB(T.pad, 10, T.pad, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$words words  ·  $chars characters',
                    style: const TextStyle(color: T.paragraph, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                // Deliberately not showing a cap: OpenRouter publishes no prompt
                // limit for any image or video model, and a 20,000 character
                // prompt was accepted when tested.
                const Text('no published limit', style: TextStyle(color: T.faint, fontSize: 10.5)),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: PrimaryButton(
                label: 'Done',
                icon: Icons.check_rounded,
                onTap: () => Navigator.pop(context, _c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedPromptsSheet extends StatefulWidget {
  const _SavedPromptsSheet();
  @override
  State<_SavedPromptsSheet> createState() => _SavedPromptsSheetState();
}

class _SavedPromptsSheetState extends State<_SavedPromptsSheet> {
  List<Map<String, Object?>> _rows = [];
  final _q = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Db.savedPrompts(search: _q.text);
    if (mounted) {
      setState(() {
        _rows = r;
        _loaded = true;
      });
    }
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
                Text('Saved prompts', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                Text('${_rows.length}', style: const TextStyle(color: T.faint, fontSize: 13)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              onChanged: (_) => _load(),
              style: const TextStyle(color: T.ink, fontSize: 14),
              cursorColor: T.ink,
              decoration: InputDecoration(
                hintText: 'Search saved prompts',
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
            child: !_loaded
                ? const Center(
                    child: SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6, color: T.faint)))
                : _rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Notice(
                          icon: Icons.bookmarks_outlined,
                          text: 'No saved prompts yet.\nWrite one and tap the bookmark to keep it.',
                        ),
                      )
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final text = r['text'] as String? ?? '';
                          final uses = (r['use_count'] as num?)?.toInt() ?? 0;
                          return Material(
                            color: T.surface,
                            borderRadius: BorderRadius.circular(T.rCard),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(T.rCard),
                              onTap: () async {
                                await Db.markPromptUsed(r['id'] as int);
                                if (context.mounted) Navigator.pop(context, text);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(T.rCard),
                                  border: Border.all(color: T.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(text,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: T.paragraph, fontSize: 13.5, height: 1.45)),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Text(
                                          '${PromptWeight.wordCount(text)} words'
                                          '${uses > 0 ? '  ·  used $uses×' : ''}',
                                          style: const TextStyle(color: T.faint, fontSize: 11),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: () async {
                                            await Db.deleteSavedPrompt(r['id'] as int);
                                            _load();
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Icon(Icons.delete_outline_rounded,
                                                size: 16, color: T.faint),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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
