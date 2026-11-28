import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';

class MarketVisibility extends InheritedWidget {
  const MarketVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarketVisibility>()?.visible ??
      true;

  @override
  bool updateShouldNotify(MarketVisibility oldWidget) =>
      visible != oldWidget.visible;
}

bool marketAccountMatches(BuildContext context, String firebaseUid) =>
    context.watch<AuthProvider>().user?.firebaseUid == firebaseUid &&
    context.watch<String?>() == firebaseUid;

bool marketNetworkAvailable(BuildContext context) =>
    context.watch<bool?>() != false;

Future<T?> showMarketDialog<T>(
  BuildContext context,
  String firebaseUid,
  WidgetBuilder builder,
) => showDialog<T>(
  context: context,
  builder: (context) => marketAccountMatches(context, firebaseUid)
      ? builder(context)
      : AlertDialog(
          content: const Text('Sign in with the same account to continue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
);

bool marketDataIsCurrent(
  AsyncSnapshot<Object?> snapshot,
  SnapshotMetadata? metadata,
) =>
    snapshot.connectionState == ConnectionState.active &&
    metadata != null &&
    !metadata.isFromCache &&
    !metadata.hasPendingWrites;

/// Stop listening when the tab or route is covered. On return, the last
/// snapshot stays visible while a fresh server snapshot is requested.
class MarketLiveBuilder<T> extends StatefulWidget {
  const MarketLiveBuilder({
    super.key,
    required this.firebaseUid,
    required this.stream,
    required this.builder,
  });

  final String firebaseUid;
  final Stream<T>? Function() stream;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<MarketLiveBuilder<T>> createState() => _MarketLiveBuilderState<T>();
}

class _MarketLiveBuilderState<T> extends State<MarketLiveBuilder<T>> {
  Stream<T>? _subscription;
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final matches = marketAccountMatches(context, widget.firebaseUid);
    final active =
        matches &&
        MarketVisibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (active != _active) {
      _active = active;
      _subscription = active ? widget.stream() : null;
    }
    if (!matches) {
      return const Center(
        child: Text('Sign in with the same account to view this page.'),
      );
    }
    return StreamBuilder<T>(stream: _subscription, builder: widget.builder);
  }
}
