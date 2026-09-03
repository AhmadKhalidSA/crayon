import '../api/or_model.dart';

/// Ordering for the studio's horizontal model rail.
///
/// Pinned favourites come first in the order they were pinned, then everything
/// else alphabetically by brand then name. Crucially the SELECTED model is not
/// moved: re-sorting on every tap made the rail jump under the finger, so
/// selection is shown by highlight and by scrolling the item into view.
class RailOrder {
  static List<ORModel> sort(List<ORModel> list, List<String> favourites) {
    final byId = {for (final e in list) e.id: e};
    final pinned = <ORModel>[];
    final seen = <String>{};
    for (final id in favourites) {
      final e = byId[id];
      if (e != null && seen.add(id)) pinned.add(e);
    }
    final rest = list.where((e) => !seen.contains(e.id)).toList()
      ..sort((a, b) {
        final c = a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
        return c != 0 ? c : a.shortName.toLowerCase().compareTo(b.shortName.toLowerCase());
      });
    return [...pinned, ...rest];
  }
}
