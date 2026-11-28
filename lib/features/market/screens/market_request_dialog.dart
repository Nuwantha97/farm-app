import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../models/listing_values.dart';
import '../services/market_draft_store.dart';
import '../services/market_firestore.dart';
import '../widgets/market_live_builder.dart';

class MarketRequestDialog extends StatefulWidget {
  const MarketRequestDialog({
    super.key,
    required this.market,
    required this.sellerUid,
    required this.listingId,
    required this.offer,
  });

  final MarketFirestore market;
  final String sellerUid;
  final String listingId;
  final Map<String, dynamic> offer;

  @override
  State<MarketRequestDialog> createState() => _MarketRequestDialogState();
}

class _MarketRequestDialogState extends State<MarketRequestDialog> {
  static const _type = MarketDraftType.orderRequest;
  late final _drafts = MarketDraftStore(widget.market.firebaseUid);
  late final _key = '${widget.sellerUid}/${widget.listingId}';
  late final _pending = _drafts.read(_type, _key);
  late final _requestId =
      _pending?['requestId'] as String? ?? const Uuid().v4();
  late Map<String, dynamic> _offer = widget.offer;
  late final _quantity = TextEditingController(
    text:
        _pending?['quantity'] as String? ??
        listingInput(_offer['minimumQuantity'], _decimals),
  );
  bool _busy = false;
  bool _submissionStarted = false;
  String? _message;
  Map<String, dynamic>? _existingOrder;

  String get _unit => _offer['unit'] as String;
  int get _decimals => _unit == 'kg' ? 3 : 0;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _send(int? quantity) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (quantity != null) {
        await _drafts.save(_type, _key, {
          'requestId': _requestId,
          'quantity': _quantity.text,
        });
        _submissionStarted = true;
      }
      final result = await widget.market.requestOrder(
        requestId: _requestId,
        sellerUid: widget.sellerUid,
        listingId: widget.listingId,
        reviewed: _offer,
        quantity: quantity,
      );
      final latest = result.revisedOffer;
      if (latest == null) {
        await _drafts.delete(_type, _key);
        if (!mounted) return;
        if (result.existingOrder case final order?) {
          setState(() => _existingOrder = order);
        } else {
          Navigator.pop(context, true);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        final unitChanged = latest['unit'] != _unit;
        _offer = latest;
        if (unitChanged) _quantity.clear();
        _message = 'The offer changed. Review the updated details and total before sending.';
      });
    } on StateError catch (error) {
      if (mounted) setState(() => _message = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not confirm the request. Check your connection and whether the offer is still available, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!marketAccountMatches(context, widget.market.firebaseUid)) {
      return AlertDialog(
        content: const Text(
          'Sign in with the same account to view this request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final online = marketNetworkAvailable(context);
    if (_existingOrder case final order?) {
      final unit = order['unit'] as String;
      final quantity = listingInput(order['quantity'], unit == 'kg' ? 3 : 0);
      final price = formatMarketMoney(order['pricePerUnitCents'] as int);
      final total = formatMarketMoney(order['totalCents'] as int);
      return AlertDialog(
        title: const Text('Request already sent'),
        content: Text(
          '${order['produceName']}\n$quantity $unit · $price per $unit\n'
          'Total $total\n\nView the saved request in Market → Orders → Buying.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    }
    final quantity = parseListingAmount(_quantity.text, _decimals);
    final total = quantity == null
        ? null
        : marketOrderTotal(_offer['pricePerUnitCents'] as int, quantity, _unit);
    final valid =
        quantity != null &&
        quantity >= (_offer['minimumQuantity'] as int) &&
        quantity <= (_offer['availableQuantity'] as int) &&
        total != null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_offer['produceName'] as String),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(listingSummary(_offer)),
              const SizedBox(height: 12),
              TextField(
                controller: _quantity,
                enabled: !_busy,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: _decimals != 0,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity ($_unit)',
                  errorText: !valid && _quantity.text.isNotEmpty
                      ? 'Choose a quantity within the listed limits.'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (valid) Text('Total ${formatMarketMoney(total)}'),
              if (!online) const Text('Reconnect to send or check a request.'),
              const Text(
                'Awaiting seller confirmation after you send. Payment is at pickup.',
              ),
              if (_message case final message?) ...[
                const SizedBox(height: 8),
                Text(message),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (!valid && (_pending != null || _submissionStarted))
            TextButton(
              onPressed: _busy || !online ? null : () => _send(null),
              child: const Text('Check previous request'),
            ),
          FilledButton(
            onPressed: _busy || !online || !valid
                ? null
                : () => _send(quantity),
            child: Text(_busy ? 'Sending…' : 'Request to buy'),
          ),
        ],
      ),
    );
  }
}
