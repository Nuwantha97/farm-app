import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class MarketMapPin {
  const MarketMapPin({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final double latitude;
  final double longitude;
  final String label;
  final int count;
  final VoidCallback onTap;
}

class SriLankaMap extends StatefulWidget {
  const SriLankaMap({super.key, required this.pins});

  final List<MarketMapPin> pins;

  @override
  State<SriLankaMap> createState() => _SriLankaMapState();
}

class _SriLankaMapState extends State<SriLankaMap> {
  final _transform = TransformationController();
  // Longitude and latitude bounds include the offshore islands.
  static const _west = 79.35, _east = 82.12, _south = 5.78, _north = 9.98;
  static final _outline = rootBundle
      .loadString('assets/maps/sri_lanka.json')
      .then(
        (json) => (jsonDecode(json) as List)
            .map(
              (ring) => (ring as List).map((point) {
                final coordinate = point as List;
                return Offset(
                  (coordinate[0] as num).toDouble(),
                  (coordinate[1] as num).toDouble(),
                );
              }).toList(),
            )
            .toList(),
      );

  static Offset _project(Size size, double longitude, double latitude) {
    final width = (_east - _west) * 0.99;
    final height = _north - _south;
    final scale = math.max(
      0.0,
      math.min((size.width - 48) / width, (size.height - 48) / height),
    );
    return Offset(
      size.width / 2 + (longitude - (_east + _west) / 2) * scale * 0.99,
      size.height / 2 - (latitude - (_north + _south) / 2) * scale,
    );
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.secondaryContainer.withValues(alpha: 0.35),
      child: FutureBuilder(
        future: _outline,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Map unavailable. Switch to List to browse.'),
            );
          }
          final outline = snapshot.data;
          if (outline == null) {
            return const SizedBox.expand();
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    transformationController: _transform,
                    maxScale: 4,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _Coastline(outline, colors),
                          ),
                        ),
                        for (final pin in widget.pins)
                          if (pin.longitude >= _west &&
                              pin.longitude <= _east &&
                              pin.latitude >= _south &&
                              pin.latitude <= _north)
                            _buildPin(
                              pin,
                              _project(size, pin.longitude, pin.latitude),
                            ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 6,
                    child: IgnorePointer(
                      child: Text(
                        'Natural Earth',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPin(MarketMapPin pin, Offset point) => Positioned(
    left: point.dx - 24,
    top: point.dy - 24,
    child: ValueListenableBuilder(
      valueListenable: _transform,
      builder: (context, matrix, child) =>
          Transform.scale(scale: 1 / matrix.getMaxScaleOnAxis(), child: child),
      child: IconButton.filled(
        tooltip:
            '${pin.label} · ${pin.count} ${pin.count == 1 ? 'farmer' : 'farmers'}',
        onPressed: pin.onTap,
        icon: pin.count == 1
            ? const Icon(Icons.location_on_outlined)
            : Text(
                '${pin.count}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
      ),
    ),
  );
}

class _Coastline extends CustomPainter {
  const _Coastline(this.outline, this.colors);

  final List<List<Offset>> outline;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final coast = Path()..fillType = PathFillType.evenOdd;
    for (final ring in outline) {
      coast.addPolygon([
        for (final point in ring)
          _SriLankaMapState._project(size, point.dx, point.dy),
      ], true);
    }
    canvas.drawPath(coast, Paint()..color = colors.primaryContainer);
    canvas.drawPath(
      coast,
      Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_Coastline oldDelegate) =>
      outline != oldDelegate.outline || colors != oldDelegate.colors;
}
