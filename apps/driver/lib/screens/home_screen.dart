// ignore_for_file: unused_element, unused_field

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../core/app_routes.dart';
import '../data/mock_data.dart';
import '../services/route_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'destination_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const ll.LatLng _currentLocation = ll.LatLng(21.1702, 72.8311);
  static const String _currentLocationLabel = 'Surat Yard';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MapController _mapController = MapController();

  Future<List<ll.LatLng>>? _routeFuture;
  DestinationPickResult? _destination;
  bool _isSearchExpanded = false;
  bool _isDestinationExpanded = false;
  bool _isOnline = true;
  bool _isRefreshingLocation = false;
  String? _currentLocationText = _currentLocationLabel;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _expandSearchBar() {
    if (_isSearchExpanded) return;
    setState(() => _isSearchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _collapseSearchBar() {
    if (!_isSearchExpanded) return;
    setState(() => _isSearchExpanded = false);
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isRefreshingLocation = true;
    });

    final resolvedLocation = await _resolveCurrentLocationAddress();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentLocationText = resolvedLocation;
      _isRefreshingLocation = false;
    });
  }

  Future<String> _resolveCurrentLocationAddress() async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      <String, String>{
        'lat': _currentLocation.latitude.toStringAsFixed(6),
        'lon': _currentLocation.longitude.toStringAsFixed(6),
        'format': 'jsonv2',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: const <String, String>{'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        return _currentLocationLabel;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final displayName = (decoded['display_name'] as String?)?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          return displayName;
        }
      }
    } catch (_) {
      return _currentLocationLabel;
    }

    return _currentLocationLabel;
  }

  void _centerMapOnCurrentLocation() {
    _mapController.move(_currentLocation, _mapController.camera.zoom);
  }

  void _toggleOnlineState() {
    setState(() {
      _isOnline = !_isOnline;
    });
  }

  void _onMapTap(ll.LatLng point) {
    if (!_isDestinationExpanded) return;
    setState(() {
      _destination = DestinationPickResult(address: 'Pinned location', point: point);
      _searchController.text = _destination!.address;
      _isDestinationExpanded = false;
      final routePoints = <ll.LatLng>[_currentLocation, point];
      _routeFuture = RouteService.fetchRouteGeoJson(routePoints).onError(
        (_, __) => routePoints,
      );
    });
  }

  Future<void> _openDestinationPicker() async {
    final query = _searchController.text.trim();
    final result = await Navigator.of(context, rootNavigator: true).pushNamed(
      AppRoutes.destinationPicker,
      arguments: DestinationPickerArgs(
        title: 'Where are you going?',
        initialQuery: query.isNotEmpty ? query : _destination?.address,
        initialPoint: _destination?.point,
      ),
    );

    if (!mounted) return;

    if (result is DestinationPickResult) {
      setState(() {
        _destination = result;
        _searchController.text = result.address;
        _isSearchExpanded = false;
        final routePoints = <ll.LatLng>[_currentLocation, result.point];
        _routeFuture = RouteService.fetchRouteGeoJson(routePoints).onError(
          (_, __) => routePoints,
        );
      });
    }
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _routeFuture = null;
      _isSearchExpanded = false;
      _searchController.clear();
    });
  }

  void _completeRide() {
    _clearDestination();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride marked as completed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildMapBody(
                context,
                showDestinationChip: _destination != null,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: SafeArea(
                bottom: false,
                child: _buildSearchCard(context),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'driver-home-recenter',
                onPressed: _centerMapOnCurrentLocation,
                backgroundColor: TruxifyColors.white,
                foregroundColor: TruxifyColors.accent,
                elevation: 4,
                shape: const CircleBorder(),
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
            if (_destination == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _buildBottomSheet(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimeSinceLastTrip() {
    DateTime? latest;
    for (final record in tripHistory) {
      if (!record.completed) continue;
      final parsed = _parseTripHistoryDate(record.date);
      if (parsed == null) continue;
      if (latest == null || parsed.isAfter(latest)) {
        latest = parsed;
      }
    }

    if (latest == null) return '-';

    final now = DateTime.now();
    var diff = now.difference(latest);
    if (diff.isNegative) diff = diff * -1;

    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  DateTime? _parseTripHistoryDate(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return null;

    final day = int.tryParse(parts[0]);
    final year = int.tryParse(parts[2]);
    if (day == null || year == null) return null;

    final monthMap = <String, int>{
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = monthMap[parts[1].toLowerCase()];
    if (month == null) return null;

    return DateTime(year, month, day);
  }

  Widget _buildMapBody(BuildContext context,
      {required bool showDestinationChip}) {
    if (_destination == null) {
      return FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentLocation,
          initialZoom: 5.7,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
          onTap: (tap, point) => _onMapTap(point),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.truxify.driver',
          ),
        ],
      );
    }

    return FutureBuilder<List<ll.LatLng>>(
      future: _routeFuture ??
          Future.value(<ll.LatLng>[_currentLocation, _destination!.point]),
      builder: (context, snap) {
        final routePoints = (snap.connectionState == ConnectionState.done &&
                snap.hasData &&
                snap.data!.length >= 2)
            ? snap.data!
            : <ll.LatLng>[_currentLocation, _destination!.point];

        final center = _routeCenter(routePoints);
        final zoom = _routeZoom(routePoints);
        final checkpoints = _buildCheckpointPoints(routePoints);

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              key: ValueKey(_destination!.address),
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.truxify.driver',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 5.0,
                      color: TruxifyColors.accentDark,
                      borderStrokeWidth: 2.0,
                      borderColor: Colors.white.withValues(alpha: 0.8),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation,
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      child: const _RouteMarker(
                        icon: Icons.my_location_rounded,
                        fillColor: TruxifyColors.success,
                        shadowColor: TruxifyColors.success,
                      ),
                    ),
                    ...checkpoints.asMap().entries.map(
                          (entry) => Marker(
                            point: entry.value,
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            child: _RouteCheckpointMarker(
                                label: '${entry.key + 1}'),
                          ),
                        ),
                    Marker(
                      point: _destination!.point,
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      child: const _RouteMarker(
                        icon: Icons.location_on_rounded,
                        fillColor: TruxifyColors.error,
                        shadowColor: TruxifyColors.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_destination != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: SizedBox(
                      width: 140,
                      height: 48,
                      child: Material(
                        color: TruxifyColors.success,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: _completeRide,
                          child: const Center(
                            child: Text(
                              'Start',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  ll.LatLng _routeCenter(List<ll.LatLng> points) {
    final lats = points.map((p) => p.latitude).toList(growable: false);
    final lngs = points.map((p) => p.longitude).toList(growable: false);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);
    return ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  double _routeZoom(List<ll.LatLng> points) {
    final lats = points.map((p) => p.latitude).toList(growable: false);
    final lngs = points.map((p) => p.longitude).toList(growable: false);
    final latSpan = lats.reduce(math.max) - lats.reduce(math.min);
    final lngSpan = lngs.reduce(math.max) - lngs.reduce(math.min);
    final span = math.max(latSpan, lngSpan);

    if (span < 0.05) return 13.5;
    if (span < 0.15) return 12.0;
    if (span < 0.35) return 10.4;
    if (span < 0.9) return 8.8;
    if (span < 2.5) return 7.4;
    return 6.2;
  }

  List<ll.LatLng> _buildCheckpointPoints(List<ll.LatLng> routePoints) {
    if (routePoints.length < 4) return const <ll.LatLng>[];

    final totalSegments = routePoints.length - 1;
    final indexes = <int>{};
    for (var step = 1; step <= 3; step++) {
      final index =
          ((totalSegments * step) / 4).round().clamp(1, totalSegments - 1);
      indexes.add(index);
    }

    return indexes.map((index) => routePoints[index]).toList(growable: false);
  }

  Widget _buildSearchCard(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const _PulsingLocationDot(),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 28,
                      child: CustomPaint(
                        painter: _DashedLinePainter(color: TruxifyColors.border),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: TruxifyColors.error.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.location_pin,
                          size: 10,
                          color: TruxifyColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    _SearchFieldPill(
                      backgroundColor: Colors.grey.shade100,
                      onTap: _fetchCurrentLocation,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _currentLocationText ?? _currentLocationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Material(
                              color: TruxifyColors.white,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _centerMapOnCurrentLocation,
                                child: _isRefreshingLocation
                                    ? const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: TruxifyColors.accent,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.my_location_rounded,
                                        size: 18,
                                        color: TruxifyColors.accent,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _isDestinationExpanded
                          ? _SearchFieldPill(
                              key: const ValueKey('destination-expanded'),
                              backgroundColor: Colors.grey.shade100,
                              onTap: _searchFocusNode.requestFocus,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: TruxifyColors.error,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      textInputAction: TextInputAction.search,
                                      onSubmitted: (_) => _openDestinationPicker(),
                                      decoration: InputDecoration(
                                        hintText: 'Where to?',
                                        border: InputBorder.none,
                                        isDense: true,
                                        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: TruxifyColors.tertiaryText,
                                            ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      _isDestinationExpanded = false;
                                      _searchController.clear();
                                    }),
                                    icon: const Icon(
                                      Icons.expand_less_rounded,
                                      color: TruxifyColors.tertiaryText,
                                    ),
                                    splashRadius: 18,
                                  ),
                                ],
                              ),
                            )
                          : _SearchFieldPill(
                              key: const ValueKey('destination-collapsed'),
                              backgroundColor: Colors.grey.shade100,
                              onTap: _openDestinationPicker,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: TruxifyColors.error,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _destination?.address ?? 'Where to?',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _isDestinationExpanded = true;
                                      });
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted) {
                                          _searchFocusNode.requestFocus();
                                        }
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      color: TruxifyColors.tertiaryText,
                                    ),
                                    splashRadius: 18,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: TruxifyColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(metric: _driverMetricCards()[0]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(metric: _driverMetricCards()[1]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(metric: _driverMetricCards()[2]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(metric: _driverMetricCards()[3]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(metric: _driverMetricCards()[4]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_DriverMetric> _driverMetricCards() {
    return <_DriverMetric>[
      const _DriverMetric(
        label: 'Earnings today',
        value: driverEarningsMonth,
        subtitle: 'Today\'s earnings',
        icon: Icons.account_balance_wallet_rounded,
        iconColor: TruxifyColors.accent,
      ),
      _DriverMetric(
        label: 'Last trip',
        value: _formatTimeSinceLastTrip(),
        subtitle: 'Since last trip',
        icon: Icons.schedule_rounded,
        iconColor: TruxifyColors.accent,
      ),
      const _DriverMetric(
        label: 'Active jobs',
        value: '--',
        subtitle: 'Active jobs',
        icon: Icons.work_outline_rounded,
        iconColor: TruxifyColors.accent,
      ),
      const _DriverMetric(
        label: 'Rating',
        value: driverRating,
        subtitle: 'Your rating',
        icon: Icons.star_rounded,
        iconColor: TruxifyColors.accent,
      ),
      const _DriverMetric(
        label: 'Online hours',
        value: '--',
        subtitle: 'Hours online',
        icon: Icons.timer_outlined,
        iconColor: TruxifyColors.accent,
      ),
    ];
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({
    required this.icon,
    required this.fillColor,
    required this.shadowColor,
  });

  final IconData icon;
  final Color fillColor;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _RouteCheckpointMarker extends StatelessWidget {
  const _RouteCheckpointMarker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: TruxifyColors.accentDark, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: TruxifyColors.accentDark,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _OverviewStatCard extends StatelessWidget {
  const _OverviewStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Colors.white,
      border: Border.all(color: TruxifyColors.border),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: TruxifyColors.accentLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: TruxifyColors.accentDark, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TruxifyColors.adaptiveSecondaryText(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _DriverMetric {
  const _DriverMetric({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _DriverMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: metric.iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(metric.icon, color: metric.iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TruxifyColors.adaptiveSecondaryText(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _SearchFieldPill extends StatelessWidget {
  const _SearchFieldPill({
    super.key,
    required this.child,
    required this.onTap,
    required this.backgroundColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

class _PulsingLocationDot extends StatefulWidget {
  const _PulsingLocationDot();

  @override
  State<_PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<_PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final pulseScale = 1.0 + (_controller.value * 0.18);
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: pulseScale,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: TruxifyColors.success.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: TruxifyColors.success,
                shape: BoxShape.circle,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashHeight = 4.0;
    const gapHeight = 4.0;
    var currentY = 0.0;

    while (currentY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, currentY),
        Offset(size.width / 2, math.min(currentY + dashHeight, size.height)),
        paint,
      );
      currentY += dashHeight + gapHeight;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
