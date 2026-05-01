import 'package:flutter/material.dart';

import 'package:scheduling/routes/app_routes.dart';


PreferredSizeWidget appScaffoldBar(BuildContext context, String title, String employeeId, bool isAdmin) {
    return AppBar(
      title: Text(title),
      centerTitle: true,
      leading: IconButton(
        onPressed: () => Navigator.pushReplacementNamed(
          context,
          AppRoutes.mainCalendar,
          arguments: MainCalendarArgs(
            isAdmin: isAdmin,
            employeeId: employeeId,
          ),
        ),
        icon: Icon(Icons.arrow_back_rounded),
      ),
    );
}

