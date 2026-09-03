import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/gen_backend.dart';
import '../api/openrouter.dart';
import '../api/enhance.dart';
import '../core/prompt_weight.dart';
import '../core/secrets.dart';

/// App settings. The OpenRouter API key lives in the platform keystore;
/// everything else is plain prefs.
class SettingsState extends ChangeNotifier {
  static const _ks = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _storeKey = 'or_key';

  String _key = '';

  bool _autoSaveToGallery = false;
  String _lastImageModel = '';
  String _lastVideoModel = '';
  List<String> _favourites = [];
  String _enhanceModel = PromptEnhancer.defaultModel;
  WeightStyle _weightStyle = WeightStyle.braces;
  int _refMaxSide = 2048;
  bool _showAllParams = false;
  String _sheetPrompt = defaultSheetPrompt;
  bool _loaded = false;

  /// Default prompt for baking a character model sheet. Bakes a 360 turnaround
  /// in plain, neutral, form-fitting clothing so no outfit colour or style ever
  /// leaks into later generations, reconstructs one consistent identity from
  /// mixed-quality references, and puts accessories in side callouts. Editable
  /// and savable by the user.
  static const defaultSheetPrompt =
      'Create ONE professional character reference sheet (model sheet) of a SINGLE '
      'consistent person, reconstructed from the provided reference photos. Study every '
      'reference together and infer the person\'s TRUE, consistent identity: same face, '
      'bone structure, eyes, nose, lips, skin tone, natural hair and body proportions in '
      'every panel. The references vary in quality, lighting, makeup, hairstyle and '
      'clothing - treat all of that as noise: take the face from the CLEAREST shots, '
      'ignore compression, blur, filters and heavy makeup, and do NOT copy any single '
      'outfit or pose.\n\n'
      'Render the BASE character in plain, neutral, form-fitting clothing (a plain '
      'light-grey fitted top and leggings) in a neutral A-pose on a plain light-grey '
      'studio background with even, soft lighting, so the true body shape and proportions '
      '(shoulders, chest, waist, hips, legs) read clearly and are never tinted or hidden '
      'by a busy outfit. This plain neutral base is what keeps future generations from '
      'inheriting an outfit\'s colour or style.\n\n'
      'Make the figure REALISTIC and true to life: reproduce the person\'s actual build, '
      'weight, height and proportions as inferred from the photos. Do NOT idealise, slim, '
      'enlarge or beautify the figure - it must plausibly be the SAME real person, not a '
      'fashion model.\n\n'
      'Layout in one wide image: a full-body 360 turnaround row - front, 3/4, left side '
      'profile, right side profile, and back view. Below it a face study row - front, 3/4 '
      'and profile, with neutral and smiling expressions. In a SEPARATE side panel, show the '
      'character\'s accessories seen across the references (hats, glasses, earrings, jewellery, '
      'distinctive hairstyles, etc.) as individual labelled callout items, plus one small '
      'variant of the character wearing them. The natural, accessory-free look is the base. '
      'Keep ONE identical identity across every panel. Clean, evenly lit, labelled, consistent.';

  /// The saved OpenRouter API key.
  String get apiKey => _key;
  bool get hasKey => _key.trim().isNotEmpty;

  /// Alias kept for prompt enhancement, which always runs on an OpenRouter chat
  /// model.
  String get openRouterKey => _key;

  bool get autoSaveToGallery => _autoSaveToGallery;
  String get lastImageModel => _lastImageModel;
  String get lastVideoModel => _lastVideoModel;
  bool get loaded => _loaded;
  String get enhanceModel => _enhanceModel;
  WeightStyle get weightStyle => _weightStyle;
  int get refMaxSide => _refMaxSide;
  bool get showAllParams => _showAllParams;
  String get characterSheetPrompt => _sheetPrompt;
  bool get sheetPromptIsDefault => _sheetPrompt == defaultSheetPrompt;

  List<String> get favourites => List.unmodifiable(_favourites);
  bool isFavourite(String id) => _favourites.contains(id);

  bool get usingBuiltInKey =>
      Secrets.openRouterKey.trim().isNotEmpty && _key == Secrets.openRouterKey;
  bool get canRestoreBuiltIn =>
      Secrets.openRouterKey.trim().isNotEmpty && _key != Secrets.openRouterKey;

  String get maskedKey {
    final k = _key;
    if (k.length < 14) return k.isEmpty ? '' : '••••';
    return '${k.substring(0, 10)}••••${k.substring(k.length - 4)}';
  }

  /// A fresh OpenRouter backend. Callers create one, use it, and close it;
  /// nothing about a backend is shared between generations.
  GenBackend backend() => OpenRouter(_key);

  /// A backend built with a specific key — used to validate a key the user just
  /// typed, before it is saved.
  GenBackend backendWithKey(String key) => OpenRouter(key);

  /// Backend for a model's `provider` id. Every model runs on OpenRouter, so the
  /// id is accepted for call-site compatibility but always yields the OpenRouter
  /// backend.
  GenBackend backendForId(String providerId) => OpenRouter(_key);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    try {
      _key = await _ks.read(key: _storeKey) ?? '';
    } catch (_) {
      _key = '';
    }
    // Seed from the key compiled into this build so the app is usable the
    // moment it opens. Only on an empty slot, and never after a deliberate
    // clear, so a deliberate removal is not undone on the next launch.
    const builtIn = Secrets.openRouterKey;
    final cleared = p.getBool('cleared_openrouter') ?? false;
    if (_key.isEmpty && builtIn.trim().isNotEmpty && !cleared) {
      _key = builtIn;
      try {
        await _ks.write(key: _storeKey, value: builtIn);
      } catch (_) {}
    }

    _autoSaveToGallery = p.getBool('auto_save') ?? false;
    _lastImageModel = p.getString('last_image_model') ?? '';
    _lastVideoModel = p.getString('last_video_model') ?? '';
    _favourites = p.getStringList('fav_models') ?? [];
    _enhanceModel = p.getString('enhance_model') ?? PromptEnhancer.defaultModel;
    _weightStyle = (p.getString('weight_style') ?? 'braces') == 'numeric'
        ? WeightStyle.numeric
        : WeightStyle.braces;
    _refMaxSide = p.getInt('ref_max_side') ?? 2048;
    _showAllParams = p.getBool('show_all_params') ?? false;
    _sheetPrompt = p.getString('char_sheet_prompt') ?? defaultSheetPrompt;
    _loaded = true;
    notifyListeners();
  }

  /// Saves the user's edited character-sheet prompt as the new default.
  Future<void> setCharacterSheetPrompt(String prompt) async {
    _sheetPrompt = prompt.trim().isEmpty ? defaultSheetPrompt : prompt;
    (await SharedPreferences.getInstance()).setString('char_sheet_prompt', _sheetPrompt);
    notifyListeners();
  }

  Future<void> resetSheetPrompt() async {
    _sheetPrompt = defaultSheetPrompt;
    (await SharedPreferences.getInstance()).remove('char_sheet_prompt');
    notifyListeners();
  }

  /// Sets the OpenRouter key (empty string clears it).
  Future<void> setApiKey(String k) async {
    final key = k.trim();
    _key = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cleared_openrouter', key.isEmpty);
    try {
      if (key.isEmpty) {
        await _ks.delete(key: _storeKey);
      } else {
        await _ks.write(key: _storeKey, value: key);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> restoreBuiltInKey() async {
    const b = Secrets.openRouterKey;
    if (b.trim().isEmpty) return;
    await setApiKey(b);
  }

  Future<void> setRefMaxSide(int v) async {
    _refMaxSide = v < 0 ? 0 : v;
    (await SharedPreferences.getInstance()).setInt('ref_max_side', _refMaxSide);
    notifyListeners();
  }

  Future<void> setShowAllParams(bool v) async {
    _showAllParams = v;
    (await SharedPreferences.getInstance()).setBool('show_all_params', v);
    notifyListeners();
  }

  Future<void> setWeightStyle(WeightStyle v) async {
    _weightStyle = v;
    (await SharedPreferences.getInstance()).setString('weight_style', v.name);
    notifyListeners();
  }

  Future<void> setEnhanceModel(String id) async {
    _enhanceModel = id.trim().isEmpty ? PromptEnhancer.defaultModel : id.trim();
    (await SharedPreferences.getInstance()).setString('enhance_model', _enhanceModel);
    notifyListeners();
  }

  Future<void> toggleFavourite(String id) async {
    if (_favourites.contains(id)) {
      _favourites.remove(id);
    } else {
      _favourites.add(id);
    }
    (await SharedPreferences.getInstance()).setStringList('fav_models', _favourites);
    notifyListeners();
  }

  Future<void> setAutoSave(bool v) async {
    _autoSaveToGallery = v;
    (await SharedPreferences.getInstance()).setBool('auto_save', v);
    notifyListeners();
  }

  Future<void> rememberModel(String id, bool isVideo) async {
    final p = await SharedPreferences.getInstance();
    if (isVideo) {
      _lastVideoModel = id;
      await p.setString('last_video_model', id);
    } else {
      _lastImageModel = id;
      await p.setString('last_image_model', id);
    }
  }
}
