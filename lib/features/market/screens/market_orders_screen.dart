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
                for (final order in orders) _orderTile(order.data()),
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _orderTile(Map<String, dynamic> data) {
    final unit = data['unit'] as String? ?? '';
    final total = data['totalCents'];
    final status = data['status'] as String?;
    return ListTile(
      title: Text(data['produceName'] as String? ?? 'Produce request'),
      subtitle: Text(
        [
          if (total is int)
            '${listingInput(data['quantity'], unit == 'kg' ? 3 : 0)} $unit · ${formatMarketMoney(total)}',
          status == 'requested' ? 'Awaiting seller confirmation' : status ?? '',
        ].join('\n'),
      ),
    );
  }
}
