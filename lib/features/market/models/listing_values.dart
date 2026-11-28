import 'package:intl/intl.dart';

const marketUnits = ['kg', 'bunch', 'piece'];

String formatMarketMoney(int cents) =>
    'LKR ${NumberFormat('#,##0.00', 'en').format(cents / 100)}';

int? marketOrderTotal(int priceCents, int quantity, String unit) {
  final product = BigInt.from(priceCents) * BigInt.from(quantity);
  final cents = unit == 'kg'
      ? (product + BigInt.from(500)) ~/ BigInt.from(1000)
      : product;
  return cents > BigInt.zero && cents <= BigInt.from(1000000000000)
      ? cents.toInt()
      : null;
}

/// Parses decimal input exactly so money and weights stay integers.
int? parseListingAmount(String input, int decimalPlaces) {
  final value = input.trim();
  final pattern = decimalPlaces == 0
      ? RegExp(r'^[0-9]+$')
      : RegExp('^[0-9]+(\\.[0-9]{1,$decimalPlaces})?\$');
  if (!pattern.hasMatch(value)) return null;
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  final amount = int.tryParse(
    parts.first + fraction.padRight(decimalPlaces, '0'),
  );
  return amount != null && amount > 0 && amount <= 1000000000 ? amount : null;
}

String listingInput(Object? value, int decimalPlaces) {
  if (value is! int) return '';
  if (decimalPlaces == 0) return '$value';
  final digits = value.toString().padLeft(decimalPlaces + 1, '0');
  final split = digits.length - decimalPlaces;
  final fraction = digits.substring(split).replaceFirst(RegExp(r'0+$'), '');
  final whole = digits.substring(0, split);
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

String listingSummary(Map<String, dynamic> listing) {
  final unit = listing['unit'];
  final price = listing['pricePerUnitCents'];
  final stock = listing['availableQuantity'];
  final minimum = listing['minimumQuantity'];
  if (unit is! String || price is! int || stock is! int || minimum is! int) {
    return '';
  }
  final decimals = unit == 'kg' ? 3 : 0;
  final money = NumberFormat('#,##0.00', 'en').format(price / 100);
  return 'LKR $money/$unit · ${listingInput(stock, decimals)} $unit available\n'
      'Minimum ${listingInput(minimum, decimals)} $unit · ${listing['pickupWindow'] ?? ''}';
}
