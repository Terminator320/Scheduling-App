import 'package:flutter/material.dart';

import '../screens/auth/auth_screens.dart';
import '../screens/employee/employee_calendar.dart';
import '../screens/employee/settings_screens.dart';
import '../utils/app_theme_mode.dart';
import '../utils/app_text.dart';

class EmployeeMenu extends StatelessWidget {
  const EmployeeMenu({
    super.key,
    required this.employeeName,
    required this.employeeId,
  });

  final String employeeName;
  final String employeeId;

  @override
  Widget build(BuildContext context) {
    return _EmployeeDrawerShell(
      isDark: false,
      employeeName: employeeName,
      employeeId: employeeId,
    );
  }
}

class EmployeeMenuDark extends StatelessWidget {
  const EmployeeMenuDark({
    super.key,
    required this.employeeName,
    required this.employeeId,
  });

  final String employeeName;
  final String employeeId;

  @override
  Widget build(BuildContext context) {
    return _EmployeeDrawerShell(
      isDark: true,
      employeeName: employeeName,
      employeeId: employeeId,
    );
  }
}

class _EmployeeDrawerShell extends StatelessWidget {
  const _EmployeeDrawerShell({
    required this.isDark,
    required this.employeeName,
    required this.employeeId,
  });

  final bool isDark;
  final String employeeName;
  final String employeeId;

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.pop(context);
    Future.microtask(() {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 260,
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Text(
                employeeName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? const Color(0xFF2E2E2E) : null,
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.logout,
              title: tr(context, 'Logout'),
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppThemeModeScope.of(context).isDark
                        ? LoginDarkScreen()
                        : LoginLightScreen(),
                  ),
                      (route) => false,
                );
              },
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.calendar_today_outlined,
              title: tr(context, 'Calendar'),
              onTap: () {
                _navigateTo(
                  context,
                  isDark
                      ? EmployeeCalendarDarkPage(
                    employeeId: employeeId,
                    employeeName: employeeName,
                  )
                      : EmployeeCalendarPage(
                    employeeId: employeeId,
                    employeeName: employeeName,
                  ),
                );
              },
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.settings_outlined,
              title: tr(context, 'Settings'),
              onTap: () {
                _navigateTo(
                  context,
                  isDark
                      ? EmployeeSettingsDarkPage(
                    employeeId: employeeId,
                    employeeName: employeeName,
                  )
                      : EmployeeSettingsPage(
                    employeeId: employeeId,
                    employeeName: employeeName,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  const _DrawerMenuItem({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      onTap: onTap,
    );
  }
}