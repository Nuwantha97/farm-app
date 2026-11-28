import 'package:material_ui/material_ui.dart';

import '../models/listing_values.dart';
import '../services/market_firestore.dart';

class MarketFarmerScreen extends StatefulWidget {
  const MarketFarmerScreen({
    super.key,
    required this.market,
    required this.sellerUid,
    required this.pickupLabel,
  });

  final MarketFirestore market;
  final String sellerUid;
  final String Function(String?) pickupLabel;

  @override
  State<MarketFarmerScreen> createState() => _MarketFarmerScreenState();
}

class _MarketFarmerScreenState extends State<MarketFarmerScreen> {
  late final _profile = widget.market
      .profile(widget.sellerUid)
      .snapshots(includeMetadataChanges: true);
  late final _listings = widget.market
      .activeListings(widget.sellerUid)
      .snapshots(includeMetadataChanges: true);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Farmer profile')),
    body: StreamBuilder(
      stream: _profile,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (snapshot.hasError ||
            (snapshot.hasData && data?['status'] != 'published')) {
          return const Center(child: Text('This shop is unavailable.'));
        }
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final farm = data['farmName'] as String? ?? '';
        final introduction = data['introduction'] as String? ?? '';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (snapshot.data!.metadata.isFromCache)
              const Text('Showing last known shop details.'),
            Text(
              data['displayName'] as String? ?? 'Farmer',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (farm.isNotEmpty) Text(farm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on_outlined),
              title: Text(widget.pickupLabel(data['placeId'] as String?)),
            ),
            if (introduction.isNotEmpty) Text(introduction),
            const SizedBox(height: 24),
            Text(
              'Active offers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder(
              stream: _listings,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Offers are unavailable.');
                }
                final listings = snapshot.data?.docs;
                if (listings == null) return const LinearProgressIndicator();
                if (listings.isEmpty) return const Text('No active offers.');
                return Column(
                  children: [
                    for (final listing in listings)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.eco_outlined),
                        title: Text(
                          listing.data()['produceName'] as String? ?? 'Produce',
                        ),
                        subtitle: Text(listingSummary(listing.data())),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );
}
