import 'package:flutter/material.dart';

class EmployeeMenu extends StatelessWidget {
  final String employeeName;

  const EmployeeMenu({
    super.key,
    required this.employeeName,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 260,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Text(
                employeeName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Divider(height: 1),
            _DrawerMenuItem(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/employee/calendar/light');
              },
            ),
            _DrawerMenuItem(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/employee/settings/light');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- RIGHT MENU DARK ---------------- */

class EmployeeMenuDark extends StatelessWidget {
  final String employeeName;

  const EmployeeMenuDark({
    super.key,
    required this.employeeName,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 260,
      backgroundColor: Color(0xFF111111),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Text(
                employeeName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Divider(height: 1, color: Color(0xFF2E2E2E)),
            _DrawerMenuItemDark(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/employee/calendar/dark');
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/employee/settings/dark');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.black54),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _DrawerMenuItemDark extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerMenuItemDark({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
        ),
      ),
      onTap: onTap,
    );
  }
}