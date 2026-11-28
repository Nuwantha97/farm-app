import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../services/market_firestore.dart';
import '../widgets/sri_lanka_map.dart';
import 'market_farmer_screen.dart';

typedef _MarketDocument = QueryDocumentSnapshot<Map<String, dynamic>>;

class MarketExploreScreen extends StatefulWidget {
  const MarketExploreScreen({super.key, required this.firebaseUid});

  final String firebaseUid;

  @override
  State<MarketExploreScreen> createState() => _MarketExploreScreenState();
}

class _MarketExploreScreenState extends State<MarketExploreScreen> {
  late final _market = MarketFirestore(widget.firebaseUid);
  String? _district;
  String? _selectedPlace;
  Map<String, _MarketDocument> _places = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _farmers;
  bool _showMap = true;

  Future<void> _chooseDistrict() async {
    final placesResult = Future.sync(() => _market.places.get());
    final selection =
        await showDialog<
          ({String district, Map<String, _MarketDocument> places})
        >(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Choose district'),
            content: SizedBox(
              width: 320,
              child: FutureBuilder(
                future: placesResult,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Could not load districts. Check your connection and try again.',
                    );
                  }
                  final docs = snapshot.data?.docs;
                  if (docs == null) return const LinearProgressIndicator();
                  final places = {
                    for (final place in docs)
                      if (place.data()['districtId'] is String &&
                          place.data()['name'] is String &&
                          place.data()['location'] is GeoPoint)
                        place.id: place,
                  };
                  final districts =
                      places.values
                          .map((place) => place.data()['districtId'] as String)
                          .toSet()
                          .toList()
                        ..sort();
                  if (districts.isEmpty) {
                    return const Text('No pickup locations are available yet.');
                  }
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final district in districts)
                          ListTile(
                            title: Text(district),
                            selected: district == _district,
                            onTap: () => Navigator.pop(context, (
                              district: district,
                              places: places,
                            )),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
    if (!mounted || selection == null) return;
    setState(() {
      _district = selection.district;
      _places = selection.places;
      _selectedPlace = null;
      _subscribe();
    });
  }

  void _subscribe() {
    _farmers = _market
        .publishedProfiles(_district!)
        .snapshots(includeMetadataChanges: true);
  }

  String _placeLabel(String? placeId) =>
      _places[placeId]?.data()['name'] as String? ?? 'Pickup area unavailable';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _chooseDistrict,
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(
                      _district ?? 'Choose district',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _showMap = !_showMap;
                  _selectedPlace = null;
                }),
                icon: Icon(_showMap ? Icons.list : Icons.map_outlined),
                label: Text(_showMap ? 'List' : 'Map'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder(
            key: ValueKey(_district),
            stream: _farmers,
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? const <_MarketDocument>[];
              final byPlace = <String, List<_MarketDocument>>{};
              for (final farmer in docs) {
                final placeId = farmer.data()['placeId'];
                if (placeId is String &&
                    _places[placeId]?.data()['districtId'] == _district) {
                  byPlace.putIfAbsent(placeId, () => []).add(farmer);
                }
              }
              final message = _district == null
                  ? 'Choose a district to find farmers.'
                  : snapshot.hasError
                  ? 'Could not load farmers in this district.'
                  : !snapshot.hasData
                  ? 'Loading farmers…'
                  : snapshot.data!.metadata.isFromCache
                  ? 'Showing last known results.'
                  : docs.isEmpty
                  ? 'No farmers have published in this district yet.'
                  : _showMap && byPlace.isEmpty
                  ? 'Pickup pins are unavailable. Switch to List to view farmers.'
                  : null;
              return Column(
                children: [
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(message, textAlign: TextAlign.center),
                    ),
                  if (snapshot.hasError)
                    TextButton(
                      onPressed: () => setState(_subscribe),
                      child: const Text('Retry'),
                    ),
                  Expanded(
                    child: _showMap
                        ? SriLankaMap(
                            pins: [
                              for (final entry in byPlace.entries)
                                _pin(entry.key, entry.value.length),
                            ],
                          )
                        : _farmerList(
                            _selectedPlace == null
                                ? docs
                                : byPlace[_selectedPlace] ?? const [],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  MarketMapPin _pin(String placeId, int count) {
    final point = _places[placeId]!.data()['location'] as GeoPoint;
    return MarketMapPin(
      latitude: point.latitude,
      longitude: point.longitude,
      label: _placeLabel(placeId),
      count: count,
      onTap: () => setState(() {
        _selectedPlace = placeId;
        _showMap = false;
      }),
    );
  }

  Widget _farmerList(List<_MarketDocument> farmers) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    children: [
      if (_selectedPlace case final place?)
        ListTile(
          title: Text(_placeLabel(place)),
          subtitle: Text(
            farmers.isEmpty
                ? 'No farmers at this pickup point.'
                : '${farmers.length} ${farmers.length == 1 ? 'farmer' : 'farmers'}',
          ),
          trailing: TextButton(
            onPressed: () => setState(() => _selectedPlace = null),
            child: const Text('All farmers'),
          ),
        ),
      for (final farmer in farmers)
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(farmer.data()['displayName'] as String? ?? 'Farmer'),
          subtitle: Text(_placeLabel(farmer.data()['placeId'] as String?)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => MarketFarmerScreen(
                market: _market,
                sellerUid: farmer.id,
                pickupLabel: _placeLabel,
              ),
            ),
          ),
        ),
    ],
  );
}
