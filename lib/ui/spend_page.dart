import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/openrouter.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import 'shell.dart';
import 'widgets/controls.dart';

class SpendPage extends StatefulWidget {
  const SpendPage({super.key});
  @override
  State<SpendPage> createState() => _SpendPageState();
}

class _SpendPageState extends State<SpendPage> {
  List<Map<String, Object?>> _byModel = [];
  List<Map<String, Object?>> _byDay = [];
  double _local = 0;
  int _count = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final byModel = await Db.spendByModel();
    final byDay = await Db.spendByDay();
    final local = await Db.totalSpend();
    final count = await Db.count();
    if (!mounted) return;
    setState(() {
      _byModel = byModel;
      _byDay = byDay;
      _local = local;
      _count = count;
      _loaded = true;
    });
    // Show the live OpenRouter balance for the saved key.
    final s = context.read<SettingsState>();
    if (s.hasKey) {
      await context.read<LibraryState>().refreshCredits(s.backend());
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryState>();
    final settings = context.watch<SettingsState>();
    final c = lib.credits;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: T.ink,
          backgroundColor: T.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 28),
            children: [
              Row(
                children: [
                  Text('Spend', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 19, color: T.muted),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (!settings.hasKey)
                Notice(
                  icon: Icons.key_outlined,
                  text: 'Add your OpenRouter key to see your balance.',
                  action: GhostButton(
                    label: 'Open settings',
                    dense: true,
                    onTap: () => ShellState.of(context)?.go(4),
                  ),
                )
              else
                _balanceCard(c, lib.creditsError),

              const SizedBox(height: 20),
              const SectionLabel('This app'),
              Panel(
                child: Row(
                  children: [
                    _stat('Generations', '$_count'),
                    Container(width: 1, height: 34, color: T.border),
                    _stat('Billed here', '\$${_local.toStringAsFixed(3)}'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Billed here counts only what this app generated. Your OpenRouter total also includes anything else using the same key.',
                style: TextStyle(color: T.faint, fontSize: 11.5, height: 1.45),
              ),

              if (_count > 0) ...[
                const SizedBox(height: 22),
                const SectionLabel('Last 30 days'),
                Panel(child: _bars()),
              ],

              if (_byModel.isNotEmpty) ...[
                const SizedBox(height: 22),
                const SectionLabel('By model'),
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (final r in _byModel) _modelRow(r),
                    ],
                  ),
                ),
              ],

              if (_loaded && _count == 0) ...[
                const SizedBox(height: 22),
                const Notice(
                  icon: Icons.receipt_long_outlined,
                  text: 'No generations yet, so nothing has been billed through this app.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceCard(Credits? c, String? err) {
    // OpenRouter reports a used/total split; show what's left plus the split.
    String money(double v) => '\$${v.toStringAsFixed(2)}';
    final remaining = c?.remaining;
    final pct = (c != null && c.total > 0) ? (c.used / c.total).clamp(0.0, 1.0) : 0.0;
    const topUpUrl = 'https://openrouter.ai/settings/credits';
    const activityUrl = 'https://openrouter.ai/activity';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                remaining == null ? '—' : money(remaining),
                style: const TextStyle(
                    color: T.ink, fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -1.4, height: 1),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text('left', style: TextStyle(color: T.faint, fontSize: 13)),
              ),
              const Spacer(),
              if (c != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('of ${money(c.total)}',
                      style: const TextStyle(color: T.faint, fontSize: 12)),
                ),
            ],
          ),
          if (c != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 5,
                backgroundColor: T.border,
                valueColor: const AlwaysStoppedAnimation(T.ink),
              ),
            ),
            const SizedBox(height: 8),
            Text('${money(c.used)} used on this key',
                style: const TextStyle(color: T.faint, fontSize: 11.5)),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              err ?? 'Could not read your balance',
              style: const TextStyle(color: T.faint, fontSize: 11.5),
            ),
          ],
          if (remaining != null && remaining < 1) ...[
            const SizedBox(height: 12),
            const Text('Running low. Most video models cost more than this per clip.',
                style: TextStyle(color: T.paragraph, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Add credit',
                  icon: Icons.add_rounded,
                  dense: true,
                  onTap: () => _open(topUpUrl),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'Activity',
                  icon: Icons.open_in_new_rounded,
                  dense: true,
                  onTap: () => _open(activityUrl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'OpenRouter has no API for topping up, so this opens their page in your browser.',
            style: TextStyle(color: T.faint, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the browser')));
    }
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: T.ink, fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: T.faint, fontSize: 11.5)),
          ],
        ),
      );

  /// Always draws a full 30 day window. Rendering only the days that have data
  /// turned a single generation into one full-width slab that read as a bug.
  Widget _bars() {
    const days = 30;
    final byDay = <String, double>{
      for (final d in _byDay) (d['day'] as String? ?? ''): (d['total'] as num?)?.toDouble() ?? 0,
    };
    final today = DateTime.now();
    final series = <MapEntry<DateTime, double>>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      series.add(MapEntry(day, byDay[key] ?? 0));
    }
    final max = series.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    final total = series.fold<double>(0, (a, b) => a + b.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('\$${total.toStringAsFixed(3)}',
                style: const TextStyle(color: T.ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text('in the last 30 days', style: TextStyle(color: T.faint, fontSize: 11.5)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 74,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final e in series)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: max <= 0 ? 2 : ((e.value / max) * 68).clamp(2.0, 68.0),
                      decoration: BoxDecoration(
                        // days with no spend stay as a faint baseline tick
                        color: e.value > 0 ? T.ink : T.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_dayLabel(series.first.key), style: const TextStyle(color: T.faint, fontSize: 10)),
            const Text('today', style: TextStyle(color: T.faint, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dayLabel(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  Widget _modelRow(Map<String, Object?> r) {
    final total = (r['total'] as num?)?.toDouble() ?? 0;
    final n = (r['n'] as num?)?.toInt() ?? 0;
    final biggest = (_byModel.first['total'] as num?)?.toDouble() ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${r['model_name'] ?? r['model_id']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: T.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text('$n', style: const TextStyle(color: T.faint, fontSize: 11.5)),
              const SizedBox(width: 12),
              SizedBox(
                width: 62,
                child: Text('\$${total.toStringAsFixed(3)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: T.paragraph, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: biggest <= 0 ? 0 : (total / biggest).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: T.border,
              valueColor: const AlwaysStoppedAnimation(T.borderHi),
            ),
          ),
        ],
      ),
    );
  }
}
