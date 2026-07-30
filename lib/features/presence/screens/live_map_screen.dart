import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/core/navigation/hub_shell_scope.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/features/presence/application/live_map_providers.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/presence/widgets/live_map_overlays.dart';
import 'package:scheduling/features/presence/widgets/staff_info_card.dart';
import 'package:scheduling/features/presence/widgets/staff_marker_icon.dart';
import 'package:scheduling/features/presence/widgets/staff_roster_sheet.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';
import 'package:scheduling/shared/widgets/feedback/centered_error_text.dart';

/// Everything the map body needs, so a test can inject a stub via
/// [LiveMapScreen.mapBuilder] instead of the real platform-view [GoogleMap]
/// (which can't render in `flutter_test`).
class LiveMapConfig {
  const LiveMapConfig({
    required this.initialCameraPosition,
    required this.markers,
    required this.trafficEnabled,
    required this.mapType,
    required this.onMapCreated,
    required this.onTap,
  });

  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final bool trafficEnabled;
  final MapType mapType;
  final void Function(GoogleMapController controller) onMapCreated;
  final void Function(LatLng position) onTap;
}

/// Admin-only live staff-location map — a colored avatar marker per active
/// staff member, with per-person freshness and a tap-to-open info card. Sits
/// as the hub tab between History and Settings, modeled on `HistoryScreen`
/// for its chrome.
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({
    required this.isAdmin,
    required this.employeeId,
    super.key,
    @visibleForTesting this.mapBuilder,
  });

  final bool isAdmin;
  final String employeeId;

  /// Test seam mirroring `HubShell.screenBuilder`: replaces the real
  /// [GoogleMap] with a stub that records the [LiveMapConfig].
  final Widget Function(LiveMapConfig config)? mapBuilder;

  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  // Roughly Montréal — the business's home region — until the first fit.
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(45.5017, -73.5673),
    zoom: 9,
  );

  final StaffMarkerIconRenderer _renderer = StaffMarkerIconRenderer();

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  List<StaffMapPoint> _lastPoints = const [];
  String? _selectedDocId;
  bool _traffic = false;
  bool _satellite = false;
  bool _didInitialFit = false;

  // Guards the async marker assembly: only the newest run may commit its set.
  int _assembleToken = 0;
  String? _lastSignature;

  // True once the map body (which hosts the tour's FAB targets) is rendered;
  // gates the tour so it isn't auto-marked-seen against a body with no
  // targets yet.
  bool _mapTargetsRendered = false;

  late final List<TourStepId> _tourSteps = tourStepsFor(
    HubTab.liveMap,
    isAdmin: widget.isAdmin,
  );
  late final Map<TourStepId, GlobalKey> _tourKeys = {
    for (final id in _tourSteps) id: GlobalKey(),
  };

  Widget _tourStep(
    TourStepId id, {
    required Widget child,
    BorderRadius? targetBorderRadius,
  }) => TourShowcase(
    showcaseKey: _tourKeys[id]!,
    destination: HubTab.liveMap,
    id: id,
    index: _tourSteps.indexOf(id),
    count: _tourSteps.length,
    targetBorderRadius: targetBorderRadius,
    child: child,
  );

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _backToCalendar() => navigateToDestination(
    context,
    HubTab.calendar,
    isAdmin: widget.isAdmin,
    employeeId: widget.employeeId,
  );

  @override
  Widget build(BuildContext context) {
    // Mirrors the hub's TickerMode — false when the tab is hidden or an
    // opaque route covers the hub. Defaults to true outside the shell
    // (standalone / tests).
    final visible = TickerMode.valuesOf(context).enabled;

    // Paused (tab hidden) — render the kept-alive map with the last-known
    // markers, and don't watch the data providers, so autoDispose can tear
    // down the presence listener and ticker.
    final Widget body;
    if (visible) {
      body = _liveBody(context);
    } else {
      // Paused branch renders the kept-alive map stack, so the FAB targets
      // exist.
      _mapTargetsRendered = true;
      body = _mapStack(context, _lastPoints, selectedPoint: null, paused: true);
    }

    return FeatureTourHost(
      destination: HubTab.liveMap,
      isAdmin: widget.isAdmin,
      ready: _mapTargetsRendered,
      stepKeys: _tourKeys,
      child: Scaffold(
        appBar: AppTopBar(
          title: context.l10n.liveMap_title,
          compact: context.isLandscape,
          onBack: _backToCalendar,
        ),
        endDrawer: SettingsDrawer.endDrawerFor(
          context,
          isAdmin: widget.isAdmin,
          employeeId: widget.employeeId,
        ),
        body: body,
      ),
    );
  }

  Widget _liveBody(BuildContext context) {
    final pointsAsync = ref.watch(liveMapPointsProvider);
    ref.listen<AsyncValue<List<StaffMapPoint>>>(
      liveMapPointsProvider,
      _onPointsChanged,
    );

    if (pointsAsync.hasValue) _lastPoints = pointsAsync.value!;
    final points = pointsAsync.value ?? _lastPoints;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final selected = _effectiveSelected(points);

    _scheduleMarkerAssembly(context, points, selected, dpr);
    _maybeFitCamera(points);

    final hasShownMap = _markers.isNotEmpty || _lastPoints.isNotEmpty;
    if (pointsAsync.hasError && !hasShownMap) {
      _mapTargetsRendered = false;
      return CenteredErrorText(message: context.l10n.error_introLoadLiveMap);
    }
    if (pointsAsync.isLoading && !hasShownMap) {
      _mapTargetsRendered = false;
      return const LiveMapLoadingBody();
    }

    _mapTargetsRendered = true;
    final selectedPoint = selected == null
        ? null
        : points.where((p) => p.userDocId == selected).firstOrNull;
    return _mapStack(
      context,
      points,
      selectedPoint: selectedPoint,
      paused: false,
    );
  }

  void _onPointsChanged(
    AsyncValue<List<StaffMapPoint>>? previous,
    AsyncValue<List<StaffMapPoint>> next,
  ) {
    if (!next.hasError || (previous?.hasError ?? false)) return;
    ref
        .read(loggerProvider)
        .warn('LIVEMAP-LOAD live map failed', next.error, next.stackTrace);
    ref
        .read(noticeServiceProvider)
        .error(
          composeErrorNotice(
            context,
            intro: context.l10n.error_introLoadLiveMap,
            tag: 'LIVEMAP-LOAD',
            error: next.error!,
          ),
        );
  }

  /// The stored selection, or null once that person has left the current
  /// points. Clears post-frame so a stale card doesn't render over vanished data.
  String? _effectiveSelected(List<StaffMapPoint> points) {
    final id = _selectedDocId;
    if (id == null) return null;
    if (points.any((p) => p.userDocId == id)) return id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedDocId == id && !_lastPoints.any((p) => p.userDocId == id)) {
        setState(() => _selectedDocId = null);
      }
    });
    return null;
  }

  void _scheduleMarkerAssembly(
    BuildContext context,
    List<StaffMapPoint> points,
    String? selected,
    double dpr,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = scheme.surface;
    final haloColor = scheme.primary;
    final signature = _signatureOf(
      points,
      selected,
      dpr,
      ringColor,
      haloColor,
    );
    if (signature == _lastSignature) return;

    final token = ++_assembleToken;
    unawaited(
      _assembleMarkers(
        points,
        selected,
        dpr,
        ringColor,
        haloColor,
        signature,
        token,
      ),
    );
  }

  String _signatureOf(
    List<StaffMapPoint> points,
    String? selected,
    double dpr,
    Color ringColor,
    Color haloColor,
  ) {
    final buffer = StringBuffer()
      ..write(dpr)
      ..write('|')
      ..write(selected ?? '')
      ..write('|')
      ..write(ringColor.toARGB32())
      ..write(',')
      ..write(haloColor.toARGB32());
    for (final p in points) {
      buffer
        ..write(';')
        ..write(p.userDocId)
        ..write(',')
        ..write(p.lat)
        ..write(',')
        ..write(p.lng)
        ..write(',')
        ..write(p.color.toARGB32())
        ..write(',')
        ..write(p.name);
    }
    return buffer.toString();
  }

  Future<void> _assembleMarkers(
    List<StaffMapPoint> points,
    String? selected,
    double dpr,
    Color ringColor,
    Color haloColor,
    String signature,
    int token,
  ) async {
    try {
      // Render every icon in parallel. The renderer caches per key, so
      // repeated or superseded batches are near-free, but one failure aborts
      // the whole batch.
      final icons = await Future.wait(
        points.map(
          (point) => _renderer.resolve(
            name: point.name,
            color: point.color,
            selected: point.userDocId == selected,
            ringColor: ringColor,
            haloColor: haloColor,
            devicePixelRatio: dpr,
          ),
        ),
      );
      if (!mounted || token != _assembleToken) return;
      final markers = <Marker>{};
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        markers.add(
          Marker(
            markerId: MarkerId(point.userDocId),
            position: LatLng(point.lat, point.lng),
            icon: icons[i],
            onTap: () => _selectMarker(point.userDocId),
          ),
        );
      }
      // Commit the signature only now, so a failed render leaves the previous
      // markers + signature in place and the next data/theme change retries.
      _lastSignature = signature;
      setState(() => _markers = markers);
    } catch (e, st) {
      if (!mounted || token != _assembleToken) return;
      ref.read(loggerProvider).warn('LIVEMAP-MARKERS assemble failed', e, st);
    }
  }

  void _selectMarker(String docId) {
    if (_selectedDocId == docId) return;
    setState(() => _selectedDocId = docId);
  }

  void _clearSelection() {
    if (_selectedDocId == null) return;
    setState(() => _selectedDocId = null);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _maybeFitCamera(_lastPoints);
  }

  Future<void> _openRoster() async {
    final selected = await showStaffRosterSheet(
      context,
      selfDocId: widget.employeeId,
    );
    if (!mounted || selected == null) return;
    _focusOn(selected);
  }

  /// Selects a staff member (opens their info card) and eases the camera to
  /// them — the roster row → map bridge.
  void _focusOn(StaffMapPoint point) {
    _selectMarker(point.userDocId);
    _animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(point.lat, point.lng), 15),
    );
  }

  void _maybeFitCamera(List<StaffMapPoint> points) {
    if (_didInitialFit || _mapController == null || points.isEmpty) return;
    _didInitialFit = true;
    _applyFit(points);
  }

  void _applyFit(List<StaffMapPoint> points) {
    if (_mapController == null || points.isEmpty) return;
    if (points.length == 1) {
      _animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(points.first.lat, points.first.lng),
          14,
        ),
      );
      return;
    }
    _animateCamera(CameraUpdate.newLatLngBounds(_boundsOf(points), 48));
  }

  /// The map controller can outlive its platform view — a shell swap
  /// recreates the GoogleMap subtree — so `animateCamera` can throw "used
  /// after disposed" on a stale controller.
  void _animateCamera(CameraUpdate update) {
    final controller = _mapController;
    if (controller == null) return;
    try {
      controller.animateCamera(update);
      // google_maps_flutter throws a bare StateError from a disposed
      // controller; there is no public API to test for that first, so the
      // catch is intentional.
      // ignore: avoid_catching_errors
    } on StateError {
      _mapController = null;
      _didInitialFit = false;
    }
  }

  LatLngBounds _boundsOf(List<StaffMapPoint> points) {
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;
    for (final p in points) {
      minLat = min(minLat, p.lat);
      maxLat = max(maxLat, p.lat);
      minLng = min(minLng, p.lng);
      maxLng = max(maxLng, p.lng);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Widget _mapStack(
    BuildContext context,
    List<StaffMapPoint> points, {
    required StaffMapPoint? selectedPoint,
    required bool paused,
  }) {
    final builder = widget.mapBuilder ?? _defaultMap;
    final config = LiveMapConfig(
      initialCameraPosition: _initialCamera,
      markers: _markers,
      trafficEnabled: _traffic,
      mapType: _satellite ? MapType.hybrid : MapType.normal,
      onMapCreated: _onMapCreated,
      onTap: (_) => _clearSelection(),
    );

    return Stack(
      children: [
        Positioned.fill(child: builder(config)),
        Positioned(
          top: AppSpacing.sp12,
          right: AppSpacing.sp12,
          child: SafeArea(
            child: MapToggles(
              traffic: _traffic,
              satellite: _satellite,
              onTrafficToggle: () => setState(() => _traffic = !_traffic),
              onSatelliteToggle: () => setState(() => _satellite = !_satellite),
            ),
          ),
        ),
        Positioned(
          bottom: AppSpacing.sp16,
          right: AppSpacing.sp16,
          child: _MapFabColumn(
            paused: paused,
            onOpenRoster: _openRoster,
            onRecenter: () => _applyFit(_lastPoints),
            rosterTourWrap: _tourSteps.contains(TourStepId.liveMapRoster)
                ? (child) => _tourStep(
                    TourStepId.liveMapRoster,
                    targetBorderRadius: BorderRadius.circular(AppRadius.r16),
                    child: child,
                  )
                : null,
            recenterTourWrap: _tourSteps.contains(TourStepId.liveMapRecenter)
                ? (child) => _tourStep(
                    TourStepId.liveMapRecenter,
                    targetBorderRadius: BorderRadius.circular(AppRadius.r16),
                    child: child,
                  )
                : null,
          ),
        ),
        if (!paused && points.isEmpty) const EmptyMapCard(),
        if (!paused)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDuration.normal,
              child: selectedPoint == null
                  ? const SizedBox.shrink()
                  : StaffInfoCard(
                      key: ValueKey(selectedPoint.userDocId),
                      point: selectedPoint,
                      onClose: _clearSelection,
                    ),
            ),
          ),
      ],
    );
  }

  Widget _defaultMap(LiveMapConfig config) => GoogleMap(
    initialCameraPosition: config.initialCameraPosition,
    markers: config.markers,
    trafficEnabled: config.trafficEnabled,
    mapType: config.mapType,
    myLocationButtonEnabled: false,
    onMapCreated: config.onMapCreated,
    onTap: config.onTap,
    // The map is a platform view nested inside a Stack/shell; without an
    // eager recognizer the Flutter gesture arena swallows pan/zoom drags
    // (taps still reach the map), so the map appears frozen on iOS.
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    },
  );
}

/// Bottom-right FAB stack: open the staff roster, and recenter the camera on
/// the last-known points.
class _MapFabColumn extends StatelessWidget {
  const _MapFabColumn({
    required this.paused,
    required this.onOpenRoster,
    required this.onRecenter,
    this.rosterTourWrap,
    this.recenterTourWrap,
  });

  final bool paused;
  final VoidCallback onOpenRoster;
  final VoidCallback onRecenter;
  final Widget Function(Widget child)? rosterTourWrap;
  final Widget Function(Widget child)? recenterTourWrap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          (rosterTourWrap ?? (w) => w)(
            FloatingActionButton.small(
              heroTag: 'liveMapRosterFab',
              tooltip: context.l10n.liveMap_rosterButton,
              onPressed: paused ? null : onOpenRoster,
              child: const Icon(Icons.groups_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.sp12),
          (recenterTourWrap ?? (w) => w)(
            FloatingActionButton.small(
              heroTag: 'liveMapRecenterFab',
              tooltip: context.l10n.liveMap_recenter,
              onPressed: onRecenter,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
