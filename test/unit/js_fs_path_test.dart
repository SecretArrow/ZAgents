import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/js_runtime.dart';

void main() {
  group('zResolveFsPath (module fs bridge, v1.29.0)', () {
    const String state = '/docs/sessions/s1/modules/counter/state';

    test('relative paths anchor to the working dir (first sandbox root)', () {
      expect(zResolveFsPath('data.json', <String>[state]), '$state/data.json');
      expect(
        zResolveFsPath('sub/data.json', <String>[state]),
        '$state/sub/data.json',
      );
      // The documented readdir('.') usage resolves to the state dir itself.
      expect(zResolveFsPath('.', <String>[state]), state);
      expect(zResolveFsPath('', <String>[state]), state);
    });

    test('dot segments normalize so the sandbox check sees the truth', () {
      expect(
        zResolveFsPath('./sub/../data.json', <String>[state]),
        '$state/data.json',
      );
    });

    test('traversal normalizes — and then lands outside, where the '
        'sandbox check rejects it', () {
      expect(
        zResolveFsPath('../../steal.json', <String>[state]),
        '/docs/sessions/s1/modules/steal.json',
      );
      // Deeper escape: the result is NOT under [state] anymore.
      final String resolved = zResolveFsPath('../../../../etc.json', <String>[
        state,
      ]);
      expect(resolved.startsWith('$state/'), isFalse);
    });

    test('absolute paths pass through (normalized)', () {
      expect(zResolveFsPath('/etc/passwd', <String>[state]), '/etc/passwd');
      expect(
        zResolveFsPath('$state/inner/../x.json', <String>[state]),
        '$state/x.json',
      );
    });

    test('without sandbox roots it falls back to the process CWD', () {
      final String cwd = Directory.current.path;
      expect(zResolveFsPath('x.txt', const <String>[]), '$cwd/x.txt');
    });
  });
}
