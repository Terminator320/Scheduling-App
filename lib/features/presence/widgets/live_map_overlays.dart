import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Stacked traffic and satellite toggles. A filled background signals which
/// one is active.
class MapToggles extends StatelessWidget {
  const MapToggles({
    required this.traffic,
    required this.satellite,
    required this.onTrafficToggle,
    required this.onSatelliteToggle,
    super.key,
  });

  final bool traffic;
  final bool satellite;
  final VoidCallback onTrafficToggle;
  final VoidCallback onSatelliteToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sp4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleButton(
              icon: Icons.traffic_outlined,
              active: traffic,
              tooltip: context.l10n.liveMap_trafficToggle,
              onTap: onTrafficToggle,
            ),
            const SizedBox(height: AppSpacing.sp4),
            _ToggleButton(
              icon: Icons.layers_outlined,
              active: satellite,
              tooltip: context.l10n.liveMap_satelliteToggle,
              onTap: onSatelliteToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      toggled: active,
      child: active
          ? IconButton.filled(
              icon: Icon(icon),
              tooltip: tooltip,
              onPressed: onTap,
            )
          : IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onTap),
    );
  }
}

class EmptyMapCard extends StatelessWidget {
  const EmptyMapCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp16),
          child: Text(
            context.l10n.liveMap_emptyState,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class LiveMapLoadingBody extends StatelessWidget {
  const LiveMapLoadingBody({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: AdaptiveProgressIndicator(size: 32));
}
