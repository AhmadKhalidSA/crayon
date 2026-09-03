import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/api/or_model.dart';
import 'package:crayon/ui/widgets/controls.dart';

void main() {
  group('aspect ratio ordering', () {
    test('square first, then landscape widening, then portrait tallening', () {
      // the raw order OpenRouter returns for Seedream
      final raw = ['1:1', '1:2', '2:1', '2:3', '3:2', '9:16', '16:9', 'auto'];
      final out = AspectPicker.order(raw);
      expect(out.first, 'auto');
      expect(out[1], '1:1');
      // everything after the square is landscape then portrait
      final rest = out.sublist(2);
      final landscape = ['3:2', '2:1', '16:9'];
      final portrait = ['2:3', '1:2', '9:16'];
      for (final l in landscape) {
        for (final p in portrait) {
          expect(rest.indexOf(l), lessThan(rest.indexOf(p)), reason: '$l should precede $p');
        }
      }
    });

    test('handles a list with no square and no auto', () {
      final out = AspectPicker.order(['9:16', '16:9']);
      expect(out, ['16:9', '9:16']);
    });
  });

  group('capability derivation', () {
    test('an image model with references offers edit tasks', () {
      final m = ORModel(
        id: 'x/y',
        name: 'X: Y',
        kind: Kind.image,
        params: {
          'input_references': ParamSpec(name: 'input_references', type: 'range', min: 0, max: 4),
          'aspect_ratio': ParamSpec(name: 'aspect_ratio', type: 'enum', values: ['1:1', '16:9']),
        },
      );
      expect(m.tasks, contains(Task.textToImage));
      expect(m.tasks, contains(Task.imageToImage));
      expect(m.tasks, contains(Task.edit));
      expect(m.tasks, contains(Task.outpaint));
      expect(m.maxRefs, 4);
    });

    test('an image model without references is text to image only', () {
      final m = ORModel(id: 'x/y', name: 'X: Y', kind: Kind.image);
      expect(m.tasks, [Task.textToImage]);
    });

    test('a video model offers frame tasks only for the frames it supports', () {
      final first = ORModel(
        id: 'v/1',
        name: 'V: One',
        kind: Kind.video,
        frameImages: ['first_frame'],
        durations: [5, 10],
      );
      expect(first.tasks, contains(Task.imageToVideo));
      expect(first.tasks, isNot(contains(Task.frames)));

      final both = ORModel(
        id: 'v/2',
        name: 'V: Two',
        kind: Kind.video,
        frameImages: ['first_frame', 'last_frame'],
      );
      expect(both.tasks, contains(Task.frames));
    });

    test('a model that mandates a reference cannot offer text to image', () {
      final m = ORModel(
        id: 'recraft/recraft-v4-styles',
        name: 'Recraft: V4 Styles',
        kind: Kind.image,
        params: {
          'input_references': ParamSpec(name: 'input_references', type: 'range', min: 1, max: 10),
        },
      );
      expect(m.requiresReference, isTrue);
      expect(m.tasks, isNot(contains(Task.textToImage)));
      expect(m.tasks.first, Task.imageToImage);
    });

    test('min 0 references still allows text to image', () {
      final m = ORModel(
        id: 'recraft/recraft-v4',
        name: 'Recraft: V4',
        kind: Kind.image,
        params: {
          'input_references': ParamSpec(name: 'input_references', type: 'range', min: 0, max: 1),
        },
      );
      expect(m.requiresReference, isFalse);
      expect(m.tasks, contains(Task.textToImage));
    });

    test('short name strips the vendor prefix', () {
      final m = ORModel(id: 'bytedance-seed/seedream-4.5', name: 'ByteDance Seed: Seedream 4.5', kind: Kind.image);
      expect(m.shortName, 'Seedream 4.5');
      expect(m.brand, 'ByteDance Seed');
    });

    test('round trips through the cache format', () {
      final m = ORModel(
        id: 'v/3',
        name: 'V: Three',
        kind: Kind.video,
        durations: [4, 8],
        resolutions: ['720p'],
        pricingSkus: {'duration_seconds': '0.1'},
        generateAudio: true,
      );
      final back = ORModel.decodeList(ORModel.encodeList([m])).single;
      expect(back.id, m.id);
      expect(back.durations, m.durations);
      expect(back.pricingSkus, m.pricingSkus);
      expect(back.generateAudio, isTrue);
    });
  });
}
