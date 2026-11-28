import 'package:material_ui/material_ui.dart';

import '../models/listing_values.dart';
import '../services/market_firestore.dart';

class MarketOrdersScreen extends StatefulWidget {
  const MarketOrdersScreen({super.key, required this.firebaseUid});

  final String firebaseUid;

  @override
  State<MarketOrdersScreen> createState() => _MarketOrdersScreenState();
}

class _MarketOrdersScreenState extends State<MarketOrdersScreen> {
  late final _market = MarketFirestore(widget.firebaseUid);
  late var _orders = _market
      .orders(selling: false)
      .snapshots(includeMetadataChanges: true);
  bool _selling = false;
  final _busy = <String>{};

  void _select(bool selling) {
    setState(() {
      _selling = selling;
      _orders = _market
          .orders(selling: selling)
          .snapshots(includeMetadataChanges: true);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Buying')),
            ButtonSegment(value: true, label: Text('Selling')),
          ],
          selected: {_selling},
          onSelectionChanged: (selection) => _select(selection.single),
        ),
      ),
      Expanded(
        child: StreamBuilder(
          key: ValueKey(_selling),
          stream: _orders,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => _select(_selling),
                  child: const Text('Could not load requests. Retry'),
                ),
              );
            }
            final orders = snapshot.data?.docs;
            if (orders == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (snapshot.data!.metadata.isFromCache)
                  const Text('Showing last known requests.'),
                if (orders.isEmpty)
                  Text(
                    _selling
                        ? 'No purchase requests received.'
                        : 'No purchase requests sent.',
                  ),
                for (final order in orders)
                  _orderTile(
                    order.id,
                    order.data(),
                    !snapshot.data!.metadata.isFromCache,
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );

  Future<void> _run(String id, Future<void> Function() action) async {
    if (!_busy.add(id)) return;
    setState(() {});
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final message = error is StateError
            ? error.message.toString()
            : 'Could not update this order. Check your connection and the current order status.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _confirm(
    String id,
    String status,
    String next,
    String label,
    String message,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _run(id, () => _market.changeOrderStatus(id, status, next));
    }
  }

  Future<void> _editPickup(String id, String current) async {
    final instructions = await showDialog<String>(
      context: context,
      builder: (_) => _PickupDialog(current: current),
    );
    if (mounted && instructions != null) {
      await _run(id, () => _market.savePickupInstructions(id, instructions));
    }
  }

  Widget _orderTile(String id, Map<String, dynamic> data, bool online) {
    final unit = data['unit'] as String? ?? '';
    final total = data['totalCents'];
    final status = data['status'] as String?;
    final pickup = data['pickupInstructions'] as String? ?? '';
    final enabled = online && !_busy.contains(id);
    Widget action(String label, String next, String message) => TextButton(
      onPressed: enabled
          ? () => _confirm(id, status!, next, label, message)
          : null,
      child: Text(label),
    );
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(data['produceName'] as String? ?? 'Produce request'),
            subtitle: Text(
              [
                if (total is int)
                  '${listingInput(data['quantity'], unit == 'kg' ? 3 : 0)} $unit · ${formatMarketMoney(total)}',
                switch (status) {
                  'requested' => 'Awaiting seller confirmation',
                  'accepted' => 'Accepted · Pay at pickup',
                  'declined' => 'Declined',
                  'cancelled' => 'Cancelled',
                  'completed' => 'Completed',
                  _ => '',
                },
                if ((status == 'accepted' || status == 'completed') &&
                    pickup.isNotEmpty)
                  'Pickup instructions: $pickup',
              ].join('\n'),
            ),
          ),
          if (status == 'requested' || status == 'accepted')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                children: [
                  if (status == 'requested' && _selling) ...[
                    action(
                      'Accept',
                      'accepted',
                      'Reserve the requested quantity for this buyer?',
                    ),
                    action(
                      'Decline',
                      'declined',
                      'Decline this purchase request?',
                    ),
                  ],
                  if (status == 'accepted' || !_selling)
                    action(
                      'Cancel request',
                      'cancelled',
                      status == 'accepted'
                          ? 'Cancel pickup and return the reserved quantity to the listing?'
                          : 'Withdraw this purchase request?',
                    ),
                  if (status == 'accepted' && _selling) ...[
                    TextButton(
                      onPressed: enabled ? () => _editPickup(id, pickup) : null,
                      child: Text(
                        pickup.isEmpty
                            ? 'Add pickup instructions'
                            : 'Edit pickup instructions',
                      ),
                    ),
                    action(
                      'Confirm pickup',
                      'completed',
                      'Mark this order as collected?',
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PickupDialog extends StatefulWidget {
  const _PickupDialog({required this.current});

  final String current;

  @override
  State<_PickupDialog> createState() => _PickupDialogState();
}

class _PickupDialogState extends State<_PickupDialog> {
  late final _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pickup instructions'),
    content: TextField(
      controller: _text,
      maxLines: 3,
      maxLength: 500,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Shared with the buyer'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _text.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
