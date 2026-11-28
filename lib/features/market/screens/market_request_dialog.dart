import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../models/listing_values.dart';
import '../services/market_draft_store.dart';
import '../services/market_firestore.dart';

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
  String? _message;

  String get _unit => _offer['unit'] as String;
  int get _decimals => _unit == 'kg' ? 3 : 0;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _send(int quantity) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _drafts.save(_type, _key, {
        'requestId': _requestId,
        'quantity': _quantity.text,
      });
      final latest = await widget.market.requestOrder(
        requestId: _requestId,
        sellerUid: widget.sellerUid,
        listingId: widget.listingId,
        reviewed: _offer,
        quantity: quantity,
      );
      if (latest == null) {
        await _drafts.delete(_type, _key);
        if (mounted) Navigator.pop(context, true);
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
          FilledButton(
            onPressed: _busy || !valid ? null : () => _send(quantity),
            child: Text(_busy ? 'Sending…' : 'Request to buy'),
          ),
        ],
      ),
    );
  }
}
