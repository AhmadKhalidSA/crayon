/// Build-time default key.
///
/// The key is injected with `--dart-define-from-file=env.json` (gitignored), so
/// it lives in the APK you build locally but never in the repo. If a build is
/// made without it the app simply starts with no key and asks for one.
///
/// Note this is a personal, sideloaded build: anyone holding the APK can pull
/// the string out of it. That is an accepted trade for not retyping the key.
class Secrets {
  static const openRouterKey = String.fromEnvironment('OPENROUTER_KEY');

  static bool get hasBuiltIn => openRouterKey.trim().isNotEmpty;
}
