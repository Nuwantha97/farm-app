import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../services/market_draft_store.dart';
import '../services/market_firestore.dart';
import 'market_listings_screen.dart';

const _draftId = 'shop';
const _draftType = MarketDraftType.profile;

class MyShopScreen extends StatefulWidget {
  const MyShopScreen({super.key, required this.firebaseUid});

  final String firebaseUid;

  @override
  State<MyShopScreen> createState() => _MyShopScreenState();
}

class _MyShopScreenState extends State<MyShopScreen> {
  late final _market = MarketFirestore(widget.firebaseUid);
  late final _drafts = MarketDraftStore(widget.firebaseUid);
  late final _profile = _market
      .profile(widget.firebaseUid)
      .snapshots(includeMetadataChanges: true);
  bool _hiding = false;

  Future<void> _hide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hide shop?'),
        content: const Text(
          'Your shop will disappear from Market discovery. Buyers can still open existing orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hide shop'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _hiding) return;
    setState(() => _hiding = true);
    try {
      await _market.hideProfile();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not hide your shop. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _hiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        if (profile?['status'] == 'closed') {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Your shop is closed. Go to Settings to finish deleting this account.',
              ),
            ),
          );
        }
        final draft = _drafts.read(_draftType, _draftId);
        final published = profile?['status'] == 'published';
        final status = snapshot.hasError
            ? 'Could not load your shop.'
            : !snapshot.hasData
            ? 'Checking your shop status…'
            : snapshot.data!.metadata.isFromCache
            ? 'Showing last known shop details.'
            : published
            ? 'Published'
            : profile == null
            ? 'Create a seller profile to appear in Market.'
            : 'Hidden';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (profile != null)
              Text(
                profile['displayName'] as String? ?? 'My Shop',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            Text(status),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _hiding
                  ? null
                  : () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ShopEditor(
                            market: _market,
                            drafts: _drafts,
                            initial: draft ?? profile,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
              child: Text(
                draft != null
                    ? 'Continue draft'
                    : profile == null
                    ? 'Create seller profile'
                    : 'Edit profile',
              ),
            ),
            if (published)
              OutlinedButton(
                onPressed: _hiding ? null : _hide,
                child: Text(_hiding ? 'Hiding…' : 'Hide shop'),
              ),
            OutlinedButton.icon(
              onPressed: _hiding
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MarketListingsScreen(market: _market),
                      ),
                    ),
              icon: const Icon(Icons.eco_outlined),
              label: const Text('Produce listings'),
            ),
          ],
        );
      },
    );
  }
}

class _ShopEditor extends StatefulWidget {
  const _ShopEditor({required this.market, required this.drafts, this.initial});

  final MarketFirestore market;
  final MarketDraftStore drafts;
  final Map<String, dynamic>? initial;

  @override
  State<_ShopEditor> createState() => _ShopEditorState();
}

class _ShopEditorState extends State<_ShopEditor> {
  final _form = GlobalKey<FormState>();
  late final _displayName = TextEditingController(
    text: widget.initial?['displayName'] as String?,
  );
  late final _farmName = TextEditingController(
    text: widget.initial?['farmName'] as String?,
  );
  late final _introduction = TextEditingController(
    text: widget.initial?['introduction'] as String?,
  );
  late String? _district = widget.initial?['districtId'] as String?;
  late String? _placeId = widget.initial?['placeId'] as String?;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _places = widget
      .market
      .places
      .snapshots();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _farmName.dispose();
    _introduction.dispose();
    super.dispose();
  }

  Future<void> _save({bool publish = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final fields = {
      'displayName': _displayName.text.trim(),
      'farmName': _farmName.text.trim(),
      'introduction': _introduction.text.trim(),
      'districtId': _district,
      'placeId': _placeId,
    };
    try {
      await widget.drafts.save(_draftType, _draftId, fields);
      if (publish) {
        await widget.market.publishProfile(
          displayName: fields['displayName']!,
          farmName: fields['farmName']!,
          introduction: fields['introduction']!,
          districtId: _district!,
          placeId: _placeId!,
        );
        await widget.drafts.delete(_draftType, _draftId);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = publish
              ? 'Could not finish publishing. Check your connection and pickup location, then try again.'
              : 'Could not save your draft on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(
    QueryDocumentSnapshot<Map<String, dynamic>> place,
  ) async {
    if (!_form.currentState!.validate()) return;
    final farm = _farmName.text.trim();
    final intro = _introduction.text.trim();
    final location = place.data()['location'] as GeoPoint;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview my shop'),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              Text(
                _displayName.text.trim(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (farm.isNotEmpty) Text(farm),
              if (intro.isNotEmpty) Text(intro),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(place.data()['name'] as String),
                subtitle: Text(
                  '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
                ),
              ),
              const Text(
                'Signed-in Market users can see these details when you publish.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish profile'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _save(publish: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Seller profile')),
        body: StreamBuilder(
          stream: _places,
          builder: (context, snapshot) {
            final places =
                (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data();
                  return data['districtId'] is String &&
                      data['name'] is String &&
                      data['location'] is GeoPoint;
                }).toList()..sort(
                  (a, b) => (a.data()['name'] as String).compareTo(
                    b.data()['name'] as String,
                  ),
                );
            final districts =
                places
                    .map((doc) => doc.data()['districtId'] as String)
                    .toSet()
                    .toList()
                  ..sort();
            final choices = places.where(
              (doc) => doc.data()['districtId'] == _district,
            );
            final selected = choices
                .where((doc) => doc.id == _placeId)
                .firstOrNull;
            return Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: _displayName,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a display name.'
                        : null,
                  ),
                  TextFormField(
                    controller: _farmName,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Farm name (optional)',
                    ),
                  ),
                  TextFormField(
                    controller: _introduction,
                    enabled: !_busy,
                    maxLength: 400,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Short introduction (optional)',
                    ),
                  ),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'District'),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: districts.contains(_district) ? _district : null,
                      items: [
                        for (final district in districts)
                          DropdownMenuItem(
                            value: district,
                            child: Text(district),
                          ),
                      ],
                      onChanged: _busy || districts.isEmpty
                          ? null
                          : (district) => setState(() {
                              _district = district;
                              _placeId = null;
                            }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Town or public pickup market',
                    ),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selected?.id,
                      items: [
                        for (final place in choices)
                          DropdownMenuItem(
                            value: place.id,
                            child: Text(place.data()['name'] as String),
                          ),
                      ],
                      onChanged: _busy || choices.isEmpty
                          ? null
                          : (placeId) => setState(() => _placeId = placeId),
                    ),
                  ),
                  if (snapshot.hasError)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _places = widget.market.places.snapshots(),
                            ),
                      child: const Text('Retry loading pickup locations'),
                    )
                  else if (places.isEmpty)
                    Text(
                      snapshot.hasData
                          ? 'No pickup locations are available. You can save a draft.'
                          : 'Loading pickup locations…',
                    ),
                  if (_error case final message?)
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: selected == null || _busy
                        ? null
                        : () => _preview(selected),
                    child: const Text('Preview my shop'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _save(),
                    child: Text(_busy ? 'Saving…' : 'Save draft'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
