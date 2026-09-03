import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Monochrome design tokens. No colour anywhere except pure black/white and
/// the greys between them. Every surface, border and text tone comes from here.
class T {
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF0C0C0C);
  static const surfaceHi = Color(0xFF161616);
  static const border = Color(0xFF242424);
  static const borderHi = Color(0xFF3A3A3A);

  static const ink = Color(0xFFFFFFFF);
  static const paragraph = Color(0xFFC9C9C9);
  static const muted = Color(0xFF8A8A8A);
  static const faint = Color(0xFF5C5C5C);

  // radii
  static const rField = 10.0;
  static const rCard = 14.0;
  static const rTight = 8.0;
  static const rPill = 999.0;

  static const pad = 16.0;

  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: ink,
      onPrimary: bg,
      secondary: ink,
      onSecondary: bg,
      surface: surface,
      onSurface: ink,
      error: ink,
      onError: bg,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      splashFactory: InkRipple.splashFactory,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        displaySmall: TextStyle(color: ink, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        titleLarge: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: paragraph, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(color: paragraph, fontSize: 13.5, height: 1.45),
        bodySmall: TextStyle(color: muted, fontSize: 12, height: 1.4),
        labelLarge: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: faint, fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w600),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: ink, size: 20),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHi,
        contentTextStyle: TextStyle(color: ink, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// White-on-black primary button (the one strong element in the UI).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.busy = false,
    this.subtitle,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool busy;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: T.ink,
        borderRadius: BorderRadius.circular(T.rField),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rField),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: T.bg),
                  )
                else if (icon != null)
                  Icon(icon, color: T.bg, size: 18),
                if (busy || icon != null) const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        color: T.bg, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Text(subtitle!,
                      style: TextStyle(
                          color: T.bg.withValues(alpha: 0.55),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary button.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.icon, this.onTap, this.dense = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(T.rField),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.rField),
        onTap: onTap,
        child: Container(
          height: dense ? 38 : 46,
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
          decoration: BoxDecoration(
            border: Border.all(color: T.border),
            borderRadius: BorderRadius.circular(T.rField),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: dense ? 15 : 17, color: T.ink), const SizedBox(width: 8)],
              Text(label,
                  style: TextStyle(
                      color: T.ink, fontSize: dense ? 13 : 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small all-caps section label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Selectable pill used for every enum parameter in the studio.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, this.onTap, this.leading});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? T.ink : T.surface,
      borderRadius: BorderRadius.circular(T.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.rPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rPill),
            border: Border.all(color: selected ? T.ink : T.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 7)],
              Text(
                label,
                style: TextStyle(
                  color: selected ? T.bg : T.paragraph,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bordered container used for grouped controls.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rCard),
          border: Border.all(color: T.border),
        ),
        child: child,
      );
}
