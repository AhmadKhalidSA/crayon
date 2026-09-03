import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/enhance.dart';
import '../core/secrets.dart';
import '../core/theme.dart';
import '../data/files.dart';
import '../state/catalog_state.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import '../state/studio_state.dart';
import 'widgets/controls.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _key = TextEditingController();
  final _enhance = TextEditingController();
  bool _editingKey = false;
  bool _checking = false;
  String? _keyStatus;
  int _storage = 0;

  @override
  void initState() {
    super.initState();
    _measure();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enhance.text = context.read<SettingsState>().enhanceModel;
    });
  }

  @override
  void dispose() {
    _enhance.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final s = await Files.folderSize();
    if (mounted) setState(() => _storage = s);
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _saveKey() async {
    final settings = context.read<SettingsState>();
    final raw = _key.text.trim();
    if (raw.isEmpty) {
      await settings.setApiKey('');
      setState(() {
        _editingKey = false;
        _keyStatus = null;
      });
      return;
    }
    setState(() {
      _checking = true;
      _keyStatus = null;
    });
    final b = settings.backendWithKey(raw);
    final ok = await b.validate();
    b.close();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _keyStatus = 'That key was rejected by OpenRouter.';
      });
      return;
    }
    await settings.setApiKey(raw);
    setState(() {
      _checking = false;
      _editingKey = false;
      _keyStatus = null;
    });
    _key.clear();
    _toast('Key saved');
    if (!mounted) return;
    final lib = context.read<LibraryState>();
    final catalog = context.read<CatalogState>();
    final studio = context.read<StudioState>();
    await lib.refreshCredits(settings.backend());
    // Refresh just the keyed provider's models and merge them in.
    await catalog.refresh(settings.backend(), force: true);
    if (!mounted) return;
    final cur = studio.model;
    if (cur != null) {
      final fresh = catalog.byId(cur.id);
      if (fresh != null) studio.setModel(fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final catalog = context.watch<CatalogState>();
    const keyHint = 'sk-or-v1-...';
    const keyHost = 'openrouter.ai';
    const keyUrl = 'https://openrouter.ai/settings/keys';

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 28),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),

            const SectionLabel('OpenRouter key'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_editingKey && settings.hasKey) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: T.ink),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(settings.maskedKey,
                              style: const TextStyle(
                                  color: T.paragraph, fontSize: 13, fontFamily: 'monospace')),
                        ),
                        GhostButton(
                          label: 'Change',
                          dense: true,
                          onTap: () => setState(() => _editingKey = true),
                        ),
                      ],
                    ),
                    if (settings.usingBuiltInKey) ...[
                      const SizedBox(height: 10),
                      const Text('Using the key built into this build. Change it any time.',
                          style: TextStyle(color: T.faint, fontSize: 11.5)),
                    ],
                    if (settings.canRestoreBuiltIn) ...[
                      const SizedBox(height: 10),
                      GhostButton(
                        label: 'Reset to the built-in key',
                        dense: true,
                        icon: Icons.settings_backup_restore_rounded,
                        onTap: () async {
                          await settings.restoreBuiltInKey();
                          if (!context.mounted) return;
                          _toast('Back to the built-in key');
                        },
                      ),
                    ],
                  ] else ...[
                    TextBox(
                      controller: _key,
                      hint: keyHint,
                      maxLines: 2,
                      minLines: 1,
                    ),
                    if (_keyStatus != null) ...[
                      const SizedBox(height: 8),
                      Text(_keyStatus!, style: const TextStyle(color: T.paragraph, fontSize: 12)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'Save key',
                            busy: _checking,
                            onTap: _checking ? null : _saveKey,
                          ),
                        ),
                        if (settings.hasKey) ...[
                          const SizedBox(width: 10),
                          GhostButton(
                            label: 'Cancel',
                            onTap: () => setState(() {
                              _editingKey = false;
                              _key.clear();
                              _keyStatus = null;
                            }),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    Secrets.hasBuiltIn
                        ? 'Stored in the device keystore and only ever sent to $keyHost. '
                            'This build ships with a default key, so it survives reinstalls and reboots.'
                        : 'Stored in the device keystore and only ever sent to $keyHost.',
                    style: const TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(keyUrl),
                        mode: LaunchMode.externalApplication),
                    child: const Row(
                      children: [
                        Text('Get a key',
                            style: TextStyle(color: T.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                        SizedBox(width: 4),
                        Icon(Icons.open_in_new_rounded, size: 12, color: T.ink),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),
            const SectionLabel('Models'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${catalog.images.length} image, ${catalog.videos.length} video',
                                style: const TextStyle(
                                    color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(
                              catalog.refreshing
                                  ? 'Refreshing ${catalog.progress}/${catalog.progressTotal}'
                                  : catalog.lastRefresh == null
                                      ? 'Using the list bundled with the app'
                                      : 'Updated ${_ago(catalog.lastRefresh!)}',
                              style: const TextStyle(color: T.faint, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      GhostButton(
                        label: 'Refresh',
                        dense: true,
                        onTap: catalog.refreshing || !settings.hasKey
                            ? null
                            : () async {
                                // grab the notifier before awaiting so no
                                // BuildContext is used after the gap
                                final studio = context.read<StudioState>();
                                await catalog.refresh(settings.backend(), force: true);
                                if (!mounted) return;
                                final cur = studio.model;
                                if (cur != null) {
                                  final fresh = catalog.byId(cur.id);
                                  if (fresh != null) studio.setModel(fresh);
                                }
                                _toast(catalog.error == null
                                    ? 'Model list updated'
                                    : 'Refresh failed: ${catalog.error}');
                              },
                      ),
                    ],
                  ),
                  if (catalog.refreshing) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: catalog.progressTotal == 0
                            ? null
                            : catalog.progress / catalog.progressTotal,
                        minHeight: 3,
                        backgroundColor: T.border,
                        valueColor: const AlwaysStoppedAnimation(T.ink),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Every control in the studio is built from what each model reports it supports, so a refresh picks up new models and new options automatically.',
                    style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),
            const SectionLabel('Prompt enhancement'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rewriter model',
                      style: TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextBox(
                    controller: _enhance,
                    hint: PromptEnhancer.defaultModel,
                    onChanged: settings.setEnhanceModel,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Any chat model id on OpenRouter. The Enhance button in the prompt editor '
                    'rewrites your text with it before you generate, which is what the big apps '
                    'do behind the scenes. A rewrite costs a small fraction of a cent, and you '
                    'always see the result before it is used.',
                    style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),
            const SectionLabel('Advanced'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reference image size',
                      style: TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  PillWrap(
                    values: const ['1024', '2048', '4096', '0'],
                    selected: '${settings.refMaxSide}',
                    labelBuilder: (v) => v == '0' ? 'Original' : '${v}px',
                    onSelect: (v) => settings.setRefMaxSide(int.parse(v)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Longest edge a source image is resized to before it is uploaded. '
                    'Original sends the file untouched, which preserves every detail but '
                    'makes the request much larger on mobile data.',
                    style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
                  ),
                  const Divider(height: 28),
                  SwitchRow(
                    label: 'Show every provider parameter',
                    hint: 'Nothing hidden in Advanced, including options the app normally sets for you',
                    value: settings.showAllParams,
                    onChange: settings.setShowAllParams,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crayon sends your prompt exactly as written and applies no content filter '
                    'of its own. Anything refused was refused by OpenRouter or the model vendor, '
                    'and cannot be changed from this app.',
                    style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),
            const SectionLabel('Output'),
            Panel(
              child: SwitchRow(
                label: 'Save to phone gallery automatically',
                hint: 'Off keeps results inside the app until you tap Save',
                value: settings.autoSaveToGallery,
                onChange: settings.setAutoSave,
              ),
            ),

            const SizedBox(height: 22),
            const SectionLabel('Storage'),
            Panel(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_size(_storage),
                            style: const TextStyle(color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        const Text('Generated files and reference images on this device',
                            style: TextStyle(color: T.faint, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  GhostButton(label: 'Recheck', dense: true, onTap: _measure),
                ],
              ),
            ),

            const SizedBox(height: 22),
            const SectionLabel('About'),
            const Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Crayon',
                      style: TextStyle(color: T.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text(
                    'A personal studio for OpenRouter’s image and video models. '
                    'Generations run straight from this device to OpenRouter, and everything you make stays here.',
                    style: TextStyle(color: T.faint, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
