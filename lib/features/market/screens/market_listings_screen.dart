import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../auth/providers/auth_provider.dart';
import '../../crops/services/crop_service.dart';
import '../models/listing_values.dart';
import '../services/market_draft_store.dart';
import '../services/market_firestore.dart';

const _listingDraft = MarketDraftType.listing;
const _newDraft = 'new';

class MarketListingsScreen extends StatefulWidget {
  const MarketListingsScreen({super.key, required this.market});

  final MarketFirestore market;

  @override
  State<MarketListingsScreen> createState() => _MarketListingsScreenState();
}

class _MarketListingsScreenState extends State<MarketListingsScreen> {
  late final _drafts = MarketDraftStore(widget.market.firebaseUid);
  late final _listings = widget.market.ownListings.snapshots(
    includeMetadataChanges: true,
  );
  String? _changing;

  Future<void> _edit({String? id, Map<String, dynamic>? listing}) async {
    final draftKey = id ?? _newDraft;
    final draft = _drafts.read(_listingDraft, draftKey);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ListingEditor(
          market: widget.market,
          drafts: _drafts,
          draftKey: draftKey,
          listingId: id ?? draft?['listingId'] as String? ?? const Uuid().v4(),
          draft: draft,
          listing: listing,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setPaused(String id, bool paused) async {
    setState(() => _changing = id);
    try {
      await widget.market.setListingPaused(id, paused);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update this offer. Check your connection and shop status.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _changing = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Produce listings')),
    body: StreamBuilder(
      stream: _listings,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs;
        final newDraft = _drafts.read(_listingDraft, _newDraft);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: _changing == null ? () => _edit() : null,
              icon: const Icon(Icons.add),
              label: Text(
                newDraft == null ? 'Add produce' : 'Continue new produce draft',
              ),
            ),
            if (snapshot.hasError)
              const Text(
                'Could not load your offers. You can still save a new draft.',
              )
            else if (docs == null)
              const LinearProgressIndicator()
            else ...[
              if (snapshot.data!.metadata.isFromCache)
                const Text('Showing last known offers.')
              else if (docs.isEmpty)
                const Text('You have no produce listings yet.'),
              for (final doc in docs)
                ListTile(
                  title: Text(
                    doc.data()['produceName'] as String? ?? 'Produce',
                  ),
                  subtitle: Text(
                    [
                      doc.data()['status'] == 'paused' ? 'Paused' : 'Active',
                      if (_drafts.read(_listingDraft, doc.id) != null)
                        'Draft edits',
                      listingSummary(doc.data()),
                    ].join('\n'),
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: _changing == null,
                    tooltip: 'Manage listing',
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (doc.data()['status'] == 'paused')
                        const PopupMenuItem(
                          value: 'resume',
                          child: Text('Resume'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'pause',
                          child: Text('Pause'),
                        ),
                    ],
                    onSelected: (action) {
                      if (action == 'edit') {
                        _edit(id: doc.id, listing: doc.data());
                      } else {
                        _setPaused(doc.id, action == 'pause');
                      }
                    },
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}

class _ListingEditor extends StatefulWidget {
  const _ListingEditor({
    required this.market,
    required this.drafts,
    required this.draftKey,
    required this.listingId,
    this.draft,
    this.listing,
  });

  final MarketFirestore market;
  final MarketDraftStore drafts;
  final String draftKey;
  final String listingId;
  final Map<String, dynamic>? draft;
  final Map<String, dynamic>? listing;

  @override
  State<_ListingEditor> createState() => _ListingEditorState();
}

class _ListingEditorState extends State<_ListingEditor> {
  final _form = GlobalKey<FormState>();
  late String _unit = _text('unit', 'kg');
  int get _quantityDecimals => _unit == 'kg' ? 3 : 0;
  late final _name = TextEditingController(text: _text('produceName'));
  late final _pickup = TextEditingController(text: _text('pickupWindow'));
  late final _price = TextEditingController(
    text: _number('pricePerUnitCents', 2),
  );
  late final _available = TextEditingController(
    text: _draftStockIsStale
        ? (_unit == widget.listing?['unit']
              ? listingInput(
                  widget.listing?['availableQuantity'],
                  _quantityDecimals,
                )
              : '')
        : _number('availableQuantity', _quantityDecimals),
  );
  late final _minimum = TextEditingController(
    text: _number('minimumQuantity', _quantityDecimals),
  );
  bool _busy = false;
  late String? _error = _draftStockIsStale
      ? 'Stock changed since this draft. Review the available quantity.'
      : null;

  bool get _draftStockIsStale =>
      widget.listing != null &&
      widget.draft != null &&
      widget.draft?['expectedStock'] != widget.listing?['availableQuantity'];

  int? _stock(String? text) => parseListingAmount(
    text ?? '',
    _quantityDecimals,
    allowZero: widget.listing != null,
  );

  String _text(String field, [String fallback = '']) =>
      (widget.draft?[field] ?? widget.listing?[field]) as String? ?? fallback;

  String _number(String field, int decimals) =>
      widget.draft?[field] as String? ??
      listingInput(widget.listing?[field], decimals);

  @override
  void dispose() {
    _name.dispose();
    _pickup.dispose();
    _price.dispose();
    _available.dispose();
    _minimum.dispose();
    super.dispose();
  }

  Future<void> _copyCropName(String userId) async {
    final names =
        (await CropService().getCrops(userId).first)
            .map((crop) => crop.name)
            .toSet()
            .toList()
          ..sort();
    if (!mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Copy a crop name'),
        children: [
          if (names.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No current crops. You can enter a produce name instead.',
              ),
            ),
          for (final name in names)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (mounted && name != null) _name.text = name;
  }

  Future<void> _save({Map<String, dynamic>? listing}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.drafts.save(_listingDraft, widget.draftKey, {
        'listingId': widget.listingId,
        'produceName': _name.text,
        'unit': _unit,
        'pricePerUnitCents': _price.text,
        'availableQuantity': _available.text,
        'expectedStock': widget.listing?['availableQuantity'],
        'minimumQuantity': _minimum.text,
        'pickupWindow': _pickup.text,
      });
      if (listing != null) {
        await widget.market.saveListing(
          widget.listingId,
          listing,
          expectedStock: widget.listing?['availableQuantity'],
        );
        await widget.drafts.delete(_listingDraft, widget.draftKey);
      }
      if (mounted) Navigator.pop(context);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = listing == null
              ? 'Could not save your draft on this device.'
              : 'Could not finish saving the offer. Check your connection and ensure your shop is published.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    if (!_form.currentState!.validate()) return;
    final listing = <String, dynamic>{
      'produceName': _name.text.trim(),
      'unit': _unit,
      'pricePerUnitCents': parseListingAmount(_price.text, 2)!,
      'availableQuantity': _stock(_available.text)!,
      'minimumQuantity': parseListingAmount(_minimum.text, _quantityDecimals)!,
      'pickupWindow': _pickup.text.trim(),
    };
    final isNew = widget.draftKey == _newDraft;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(listing['produceName'] as String),
        content: Text(listingSummary(listing)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isNew ? 'Publish offer' : 'Save changes'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _save(listing: listing);
  }

  String? _required(String? text, int maxLength) =>
      text == null || text.trim().isEmpty || text.trim().length > maxLength
      ? 'Enter text up to $maxLength characters.'
      : null;

  String? _positive(String? text, int decimals) =>
      parseListingAmount(text ?? '', decimals) != null
      ? null
      : decimals == 0
      ? 'Enter a positive whole number.'
      : 'Enter a positive amount with up to $decimals decimal places.';

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().currentUserId;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.draftKey == _newDraft ? 'Add produce' : 'Edit produce',
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.draftKey == _newDraft && userId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : () => _copyCropName(userId),
                    child: const Text('Use a current crop name'),
                  ),
                ),
              TextFormField(
                controller: _name,
                enabled: !_busy,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Produce name'),
                validator: (text) => _required(text, 80),
              ),
              DropdownButtonFormField<String>(
                initialValue: marketUnits.contains(_unit) ? _unit : 'kg',
                decoration: const InputDecoration(labelText: 'Selling unit'),
                items: [
                  for (final unit in marketUnits)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
                onChanged: _busy
                    ? null
                    : (unit) {
                        if (unit == null || unit == _unit) return;
                        setState(() {
                          _unit = unit;
                          _price.clear();
                          _available.clear();
                          _minimum.clear();
                        });
                      },
              ),
              _amountField(
                _price,
                'Price per $_unit (LKR)',
                2,
                (text) => _positive(text, 2),
              ),
              _amountField(
                _available,
                'Available quantity ($_unit)',
                _quantityDecimals,
                (text) => _stock(text) == null
                    ? 'Enter a valid available quantity.'
                    : null,
              ),
              _amountField(
                _minimum,
                'Minimum order ($_unit)',
                _quantityDecimals,
                (text) {
                  final error = _positive(text, _quantityDecimals);
                  if (error != null) return error;
                  final stock = _stock(_available.text);
                  final minimum = parseListingAmount(text!, _quantityDecimals)!;
                  if (stock == widget.listing?['availableQuantity'] &&
                      minimum == widget.listing?['minimumQuantity']) {
                    return null;
                  }
                  return stock != null && minimum > stock
                      ? 'Minimum order cannot exceed available quantity.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pickup,
                enabled: !_busy,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Public pickup window',
                  hintText: 'Saturday, 8–10 AM',
                ),
                validator: (text) => _required(text, 120),
              ),
              if (_error case final message?)
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _preview,
                child: const Text('Preview offer'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _save(),
                child: Text(_busy ? 'Saving…' : 'Save draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String label,
    int decimals,
    String? Function(String?) validate,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals != 0),
      decoration: InputDecoration(labelText: label),
      validator: validate,
    ),
  );
}
