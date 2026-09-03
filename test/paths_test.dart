import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/data/files.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

/// Fakes the documents directory the way iOS moves it: the container UUID
/// changes between runs, which is exactly what broke the gallery.
class _FakePP extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePP(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory containerA;
  late Directory containerB;

  setUp(() {
    containerA = Directory.systemTemp.createTempSync('containerA');
    containerB = Directory.systemTemp.createTempSync('containerB');
  });
  tearDown(() {
    containerA.deleteSync(recursive: true);
    containerB.deleteSync(recursive: true);
    Files.debugReset();
  });

  test('a path saved under one container still resolves under another', () async {
    PathProviderPlatform.instance = _FakePP(containerA.path);
    final root = await Files.root;
    final out = File('${root.path}/out/pic.png')..writeAsStringSync('x');

    // what goes into the database
    final stored = Files.rel(out.path);
    expect(stored, 'out/pic.png', reason: 'must be relative, not absolute');

    // app is reinstalled: iOS hands out a new container
    Files.debugReset();
    PathProviderPlatform.instance = _FakePP(containerB.path);
    final root2 = await Files.root;
    File('${root2.path}/out/pic.png')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    final resolved = Files.resolve(stored);
    expect(resolved, '${root2.path}/out/pic.png');
    expect(File(resolved).existsSync(), isTrue, reason: 'this is the bug: it used to point at the dead container');
  });

  test('a legacy absolute path from an old container is re-rooted', () async {
    PathProviderPlatform.instance = _FakePP(containerB.path);
    final root = await Files.root;
    File('${root.path}/out/legacy.png')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    // a row written before the fix, pointing at a container that is now gone
    const old = '/var/mobile/Containers/Data/Application/DEAD-UUID/Documents/crayon/out/legacy.png';
    final resolved = Files.resolve(old);
    expect(File(resolved).existsSync(), isTrue, reason: 'old rows must keep working with no migration');
  });

  test('an absolute path that is still valid is left alone', () async {
    PathProviderPlatform.instance = _FakePP(containerA.path);
    final root = await Files.root;
    final f = File('${root.path}/out/here.png')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    expect(Files.resolve(f.path), f.path);
  });

  test('empty and unknown paths do not throw', () async {
    PathProviderPlatform.instance = _FakePP(containerA.path);
    await Files.root;
    expect(Files.resolve(''), '');
    expect(Files.fileFor(null), isNull);
    expect(Files.fileFor(''), isNull);
    expect(() => Files.resolve('/somewhere/else/x.png'), returnsNormally);
  });
}
