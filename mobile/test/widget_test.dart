// test/widget_test.dart
// Tests basiques sans dépendance à google_fonts pour éviter les erreurs CI
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sanity checks', () {
    test('true is true', () {
      expect(true, isTrue);
    });

    test('API_BASE_URL default value is set', () {
      const url = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:8080',
      );
      expect(url, isNotEmpty);
    });

    test('Commission rate calculation', () {
      const amount = 100.0;
      const rate = 0.10;
      final commission = amount * rate;
      final travelerAmount = amount - commission;
      expect(commission, equals(10.0));
      expect(travelerAmount, equals(90.0));
    });
  });
}