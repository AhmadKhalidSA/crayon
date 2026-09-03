import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/library_state.dart';
import 'characters_page.dart';
import 'gallery_page.dart';
import 'settings_page.dart';
import 'spend_page.dart';
import 'studio_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int _index = 0;
  final _pageController = PageController();

  /// Lets any screen jump the shell to another tab (Studio -> Gallery etc).
  static ShellState? of(BuildContext c) => c.findAncestorStateOfType<ShellState>();

  void go(int i) {
    setState(() => _index = i);
    _pageController.jumpToPage(i);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = context.select<LibraryState, int>((l) => l.runningCount);
    return Scaffold(
      backgroundColor: T.bg,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          StudioPage(),
          GalleryPage(),
          CharactersPage(),
          SpendPage(),
          SettingsPage()
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: T.bg,
          border: Border(top: BorderSide(color: T.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _tab(0, Icons.tune_rounded, 'Studio'),
                _tab(1, Icons.grid_view_rounded, 'Gallery', badge: running),
                _tab(2, Icons.people_alt_outlined, 'Characters'),
                _tab(3, Icons.pie_chart_outline_rounded, 'Spend'),
                _tab(4, Icons.settings_outlined, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int i, IconData icon, String label, {int badge = 0}) {
    final sel = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => go(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 21, color: sel ? T.ink : T.faint),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: T.ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$badge',
                          style: const TextStyle(
                              color: T.bg, fontSize: 9, fontWeight: FontWeight.w800, height: 1.3)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: sel ? T.ink : T.faint,
                    fontSize: 10.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
