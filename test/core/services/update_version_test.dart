import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/services/update_service.dart';

void main() {
  final update = UpdateService.instance;

  test('compara versiones normales', () {
    expect(update.isVersionGreater('0.9.0', '0.8.1'), isTrue);
    expect(update.isVersionGreater('0.8.1', '0.9.0'), isFalse);
    expect(update.isVersionGreater('0.9.0', '0.9.0'), isFalse);
  });

  test('la final es más nueva que su versión previa', () {
    expect(update.isVersionGreater('0.9.0', '0.9.0-beta'), isTrue);
    expect(update.isVersionGreater('0.9.0-beta', '0.9.0'), isFalse);
    expect(update.isVersionGreater('0.9.0-beta', '0.8.1'), isTrue);
    expect(update.isVersionGreater('0.9.0-beta', '0.9.0-beta'), isFalse);
  });
}
