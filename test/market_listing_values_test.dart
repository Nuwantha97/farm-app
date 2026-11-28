import 'package:farm_app/features/market/models/listing_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'market amounts preserve cents and grams and enforce unit precision',
    () {
      expect(parseListingAmount('300.05', 2), 30005);
      expect(parseListingAmount('0.5', 3), 500);
      expect(parseListingAmount('1.005', 3), 1005);
      expect(parseListingAmount('5', 0), 5);
      expect(parseListingAmount('0.005', 2), isNull);
      expect(parseListingAmount('0.5', 0), isNull);
      expect(parseListingAmount('0', 0), isNull);
      expect(parseListingAmount('1e3', 2), isNull);
      expect(parseListingAmount('1000000001', 0), isNull);
      expect(listingInput(500, 3), '0.5');
      expect(listingInput(30005, 2), '300.05');
    },
  );
}
