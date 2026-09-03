import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/api/or_model.dart';
import 'package:crayon/state/studio_state.dart';

/// Reference ORDER is semantically meaningful: a prompt can say "the second
/// image" and the model resolves it positionally (verified live against
/// Seedream 4.5). So reordering must be exact.
void main() {
  late StudioState s;
  final a = File('a.png'), b = File('b.png'), c = File('c.png');

  ORModel model({int maxRefs = 4}) => ORModel(
        id: 'x/y',
        name: 'X: Y',
        kind: Kind.image,
        params: {
          'input_references': ParamSpec(name: 'input_references', type: 'range', min: 0, max: maxRefs),
        },
      );

  setUp(() {
    s = StudioState();
    s.setModel(model());
    s.setTask(Task.imageToImage);
    s..addRef(a)..addRef(b)..addRef(c);
  });

  test('references keep the order they were added', () {
    expect(s.refs.map((f) => f.path), ['a.png', 'b.png', 'c.png']);
  });

  test('moving to first promotes without losing the others', () {
    s.moveRef(2, 0);
    expect(s.refs.map((f) => f.path), ['c.png', 'a.png', 'b.png']);
  });

  test('moving one later swaps with its neighbour', () {
    s.moveRef(0, 1);
    expect(s.refs.map((f) => f.path), ['b.png', 'a.png', 'c.png']);
  });

  test('out of range moves are ignored rather than corrupting the list', () {
    s.moveRef(5, 0);
    s.moveRef(0, 9);
    s.moveRef(-1, 1);
    s.moveRef(1, 1);
    expect(s.refs.map((f) => f.path), ['a.png', 'b.png', 'c.png']);
  });

  test('replace swaps in place and keeps the position', () {
    s.replaceRefAt(1, File('z.png'));
    expect(s.refs.map((f) => f.path), ['a.png', 'z.png', 'c.png']);
  });

  test('removing shifts the rest up', () {
    s.removeRefAt(0);
    expect(s.refs.map((f) => f.path), ['b.png', 'c.png']);
  });

  group('per image masks', () {
    test('a mask belongs to one image, not to the whole generation', () {
      s.setTask(Task.imageToImage);
      s.setRefMask(1, File('m1.png'));
      expect(s.refMask(0), isNull);
      expect(s.refMask(1)?.path, 'm1.png');
      expect(s.refMask(2), isNull);
      expect(s.anyMask, isTrue);
    });

    test('masks follow their image when it is reordered', () {
      s.setTask(Task.imageToImage);
      s.setRefMask(2, File('mc.png'));
      s.moveRef(2, 0);
      expect(s.refs.first.path, 'c.png');
      expect(s.refMask(0)?.path, 'mc.png', reason: 'the mask must travel with its picture');
    });

    test('masks are dropped when their image is removed', () {
      s.setTask(Task.imageToImage);
      s.setRefMask(0, File('ma.png'));
      s.setRefMask(1, File('mb.png'));
      s.removeRefAt(0);
      expect(s.refs.first.path, 'b.png');
      expect(s.refMask(0)?.path, 'mb.png', reason: 'the remaining mask must not shift onto the wrong image');
    });

    test('replacing the picture clears its mask, which was drawn for the old one', () {
      s.setTask(Task.imageToImage);
      s.setRefMask(1, File('mb.png'));
      s.replaceRefAt(1, File('z.png'));
      expect(s.refMask(1), isNull);
    });

    test('single masked source is a true inpaint, several sources are not', () {
      s.setTask(Task.imageToImage);
      s.setRefMask(0, File('ma.png'));
      expect(s.isSingleImageInpaint, isFalse, reason: 'three sources, nothing to preserve against');

      s.removeRefAt(2);
      s.removeRefAt(1);
      expect(s.refs.length, 1);
      expect(s.isSingleImageInpaint, isTrue);
    });

    test('masks are submitted index aligned with the references', () {
      s.setTask(Task.imageToImage);
      s.setRefMask(1, File('mb.png'));
      final out = s.sourcesForSubmit;
      expect(out.refs.length, 3);
      expect(out.masks.length, 3);
      expect(out.masks[0], isNull);
      expect(out.masks[1]?.path, 'mb.png');
      expect(out.masks[2], isNull);
    });
  });

  test('the model cap is respected when adding', () {
    final fresh = StudioState()..setModel(model(maxRefs: 2));
    fresh.setTask(Task.imageToImage);
    fresh..addRef(a)..addRef(b)..addRef(c);
    expect(fresh.refs.length, 2);
  });

  test('switching to a model with a smaller cap drops the extra references', () {
    expect(s.refs.length, 3);
    s.setModel(model(maxRefs: 2));
    expect(s.refs.map((f) => f.path), ['a.png', 'b.png'],
        reason: 'extras must not survive, the API would reject them');
  });

  test('switching task KEEPS the picked images', () {
    // this is the bug Ahmed hit: bouncing to another task wiped the sources
    s.setTask(Task.textToImage);
    expect(s.refs.length, 3, reason: 'sources must survive a task change');
    s.setTask(Task.edit);
    expect(s.refs.map((f) => f.path), ['a.png', 'b.png', 'c.png']);
  });

  test('a task that uses no images simply does not send them', () {
    s.setTask(Task.textToImage);
    expect(s.refs.length, 3);
    expect(s.sourcesForSubmit.refs, isEmpty, reason: 'kept in the UI, not in the request');
  });

  test('outpaint sends only the first image', () {
    s.setTask(Task.outpaint);
    expect(s.refs.length, 3, reason: 'the others are still on screen');
    expect(s.sourcesForSubmit.refs.length, 1);
    expect(s.sourcesForSubmit.refs.single.path, 'a.png');
  });

  test('image to image sends every reference in order', () {
    s.setTask(Task.imageToImage);
    expect(s.sourcesForSubmit.refs.map((f) => f.path), ['a.png', 'b.png', 'c.png']);
  });
}

