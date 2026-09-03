import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/core/prompt_weight.dart';

void main() {
  group('brace emphasis (the Dreamina convention)', () {
    test('neutral text reads as level 0', () {
      expect(PromptWeight.levelOf('a red car'), 0);
      expect(PromptWeight.bareText('a red car'), 'a red car');
    });

    test('stepping up adds one brace pair per level', () {
      var t = 'castle';
      t = PromptWeight.bump(t, up: true);
      expect(t, '{castle}');
      t = PromptWeight.bump(t, up: true);
      expect(t, '{{castle}}');
      t = PromptWeight.bump(t, up: true);
      expect(t, '{{{castle}}}');
      expect(PromptWeight.levelOf(t), 3);
    });

    test('stepping down goes back through neutral into brackets', () {
      var t = '{{castle}}';
      t = PromptWeight.bump(t, up: false);
      expect(t, '{castle}');
      t = PromptWeight.bump(t, up: false);
      expect(t, 'castle', reason: 'neutral must leave clean words');
      t = PromptWeight.bump(t, up: false);
      expect(t, '[castle]');
      t = PromptWeight.bump(t, up: false);
      expect(t, '[[castle]]');
      expect(PromptWeight.levelOf(t), -2);
    });

    test('level is clamped at both ends, at whatever the bound currently is', () {
      var up = 'x';
      for (var i = 0; i < PromptWeight.maxLevel + 6; i++) {
        up = PromptWeight.bump(up, up: true);
      }
      expect(PromptWeight.levelOf(up), PromptWeight.maxLevel);
      expect(up, '${'{' * PromptWeight.maxLevel}x${'}' * PromptWeight.maxLevel}');

      var down = 'x';
      for (var i = 0; i < PromptWeight.maxLevel + 6; i++) {
        down = PromptWeight.bump(down, up: false);
      }
      expect(PromptWeight.levelOf(down), PromptWeight.minLevel);
      expect(down, '${'[' * PromptWeight.maxLevel}x${']' * PromptWeight.maxLevel}');
    });

    test('a string that merely starts and ends with a brace is not treated as wrapped', () {
      // "{a} and {b}" begins with { and ends with }, but is not one wrapper
      expect(PromptWeight.levelOf('{a} and {b}'), 0);
      expect(PromptWeight.bareText('{a} and {b}'), '{a} and {b}');
    });
  });

  group('numeric style (Stable Diffusion lineage)', () {
    test('emits the (text:weight) form', () {
      expect(PromptWeight.applyLevel('castle', 2, WeightStyle.numeric), '(castle:1.2)');
      expect(PromptWeight.applyLevel('castle', -2, WeightStyle.numeric), '(castle:0.8)');
    });

    test('neutral unwraps rather than writing 1.0', () {
      expect(PromptWeight.applyLevel('(castle:1.2)', 0, WeightStyle.numeric), 'castle');
    });

    test('a numeric weight is read back onto the same level scale', () {
      expect(PromptWeight.levelOf('(castle:1.3)'), 3);
      expect(PromptWeight.bareText('(castle:1.3)'), 'castle');
    });

    test('styles convert between each other through the level', () {
      final numeric = PromptWeight.applyLevel('{{castle}}', 2, WeightStyle.numeric);
      expect(numeric, '(castle:1.2)');
      final braces = PromptWeight.applyLevel(numeric, PromptWeight.levelOf(numeric), WeightStyle.braces);
      expect(braces, '{{castle}}');
    });
  });

  group('stripping', () {
    test('removes both conventions from a whole prompt', () {
      const p = 'a {{red}} car near a [tall] tree with (blue:1.4) sky';
      expect(PromptWeight.stripAll(p), 'a red car near a tall tree with blue sky');
    });

    test('leaves ordinary parentheses alone', () {
      const p = 'a car (parked) near a tree';
      expect(PromptWeight.stripAll(p), p);
    });

    test('hasMarkup detects each form', () {
      expect(PromptWeight.hasMarkup('a {red} car'), isTrue);
      expect(PromptWeight.hasMarkup('a [red] car'), isTrue);
      expect(PromptWeight.hasMarkup('a (red:1.2) car'), isTrue);
      expect(PromptWeight.hasMarkup('a plain car'), isFalse);
    });
  });

  group('plain language emphasis', () {
    test('appends a clause any model can read', () {
      expect(PromptWeight.emphasise('a red car', 'red', strong: true),
          'a red car. Put strong emphasis on red.');
    });

    test('does not stack the same clause twice', () {
      final once = PromptWeight.emphasise('a red car', 'red', strong: true);
      expect(PromptWeight.emphasise(once, 'red', strong: true), once);
    });

    test('uses the bare word when the selection is already braced', () {
      final out = PromptWeight.emphasise('a {{red}} car', '{{red}}', strong: true);
      expect(out, contains('emphasis on red.'));
      expect(out, isNot(contains('{{red}}.')));
    });
  });

  group('labels and counting', () {
    test('level label reads the way a user expects', () {
      expect(PromptWeight.levelLabel(0), 'neutral');
      expect(PromptWeight.levelLabel(2), '+2');
      expect(PromptWeight.levelLabel(-1), '-1');
    });

    test('word count collapses whitespace', () {
      expect(PromptWeight.wordCount('  a  red   car '), 3);
      expect(PromptWeight.wordCount('   '), 0);
    });
  });
}
