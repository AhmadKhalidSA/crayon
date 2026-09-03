import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/api/or_model.dart';
import 'package:crayon/core/rail_order.dart';

ORModel m(String id, String name) => ORModel(id: id, name: name, kind: Kind.image);

void main() {
  final all = [
    m('openai/gpt-image-2', 'OpenAI: GPT Image 2'),
    m('bytedance-seed/seedream-4.5', 'ByteDance Seed: Seedream 4.5'),
    m('meta/muse-image', 'Meta: Muse Image'),
    m('recraft/recraft-v4', 'Recraft: V4'),
  ];

  test('with no favourites the order is alphabetical by brand, and stable', () {
    final a = RailOrder.sort(all, const []);
    expect(a.map((e) => e.brand), ['ByteDance Seed', 'Meta', 'OpenAI', 'Recraft']);
    // calling it again must not shuffle anything
    expect(RailOrder.sort(all, const []).map((e) => e.id), a.map((e) => e.id));
  });

  test('selecting a model does not move it: order is independent of selection', () {
    final before = RailOrder.sort(all, const []).map((e) => e.id).toList();
    // there is no selection input at all, which is the point
    final after = RailOrder.sort(all, const []).map((e) => e.id).toList();
    expect(after, before);
  });

  test('favourites are pinned to the front in the order they were pinned', () {
    final a = RailOrder.sort(all, ['recraft/recraft-v4', 'meta/muse-image']);
    expect(a.first.id, 'recraft/recraft-v4');
    expect(a[1].id, 'meta/muse-image');
    expect(a.length, all.length);
  });

  test('a favourite id that is not in the list is skipped, not crashed on', () {
    final a = RailOrder.sort(all, ['gone/model', 'meta/muse-image']);
    expect(a.first.id, 'meta/muse-image');
    expect(a.length, all.length);
  });

  test('duplicate favourite ids do not duplicate the model', () {
    final a = RailOrder.sort(all, ['meta/muse-image', 'meta/muse-image']);
    expect(a.where((e) => e.id == 'meta/muse-image').length, 1);
    expect(a.length, all.length);
  });

  test('every model survives the sort', () {
    final a = RailOrder.sort(all, ['openai/gpt-image-2']);
    expect(a.map((e) => e.id).toSet(), all.map((e) => e.id).toSet());
  });
}
