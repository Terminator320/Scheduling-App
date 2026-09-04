import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/breakpoints.dart';
import 'package:scheduling/core/layout/primary_scroll_scope.dart';
import 'package:scheduling/features/navigation/widgets/app_nav_drawer.dart';
import 'package:scheduling/features/settings/widgets/views/location_sharing_view.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';
import 'package:scheduling/shared/widgets/app_bars/app_top_bar.dart';

class LocationSharingScreen extends StatelessWidget {
  const LocationSharingScreen({
    required this.isAdmin,
    required this.employeeId,
    super.key,
  });

  final bool isAdmin;
  final String employeeId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.settings_locationSharing,
        compact: context.isLandscape,
        onBack: () => Navigator.pop(context),
        actions: const [AppHeaderPair()],
      ),
      endDrawer: AppNavDrawer(isAdmin: isAdmin, employeeId: employeeId),
      body: const PrimaryScrollScope(child: LocationSharingView()),
    );
  }
}
