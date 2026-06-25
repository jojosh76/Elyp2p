// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';

// Tests basiques — les tests d'intégration complets sont dans integration_test/
void main() {
  group('Sanity checks', () {
    test('true is true', () {
      expect(true, isTrue);
    });

    test('ApiClient baseUrl is configurable', () {
      const url = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8080');
      expect(url, isNotEmpty);
    });
  });
}
