import 'package:flutter/material.dart';

class AdminMenuDrawer extends StatelessWidget {
  const AdminMenuDrawer({super.key});

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
                '(Admin Name)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Divider(height: 1),
            _DrawerMenuItem(
              icon: Icons.person_outline,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
              },
            ),
            _DrawerMenuItem(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/calendar/light');
              },
            ),
            _DrawerMenuItem(
              icon: Icons.badge_outlined,
              title: 'Employees',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/employees/light');
              },
            ),
            _DrawerMenuItem(
              icon: Icons.group_outlined,
              title: 'Clients',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/clients/light');
              },
            ),
            _DrawerMenuItem(
              icon: Icons.event_note_outlined,
              title: 'Appointments',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/appointments/light');
              },
            ),
            _DrawerMenuItem(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/settings/light');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- RIGHT MENU DARK ---------------- */

class AdminMenuDrawerDark extends StatelessWidget {
  const AdminMenuDrawerDark({super.key});

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
                '(Admin Name)',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Divider(height: 1, color: Color(0xFF2E2E2E)),
            _DrawerMenuItemDark(
              icon: Icons.person_outline,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/calendar/dark');
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.badge_outlined,
              title: 'Employees',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/employees/dark');
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.group_outlined,
              title: 'Clients',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/clients/dark');
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.event_note_outlined,
              title: 'Appointments',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/appointments/dark');
              },
            ),
            _DrawerMenuItemDark(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/admin/settings/dark');
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
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
        ),
      ),
      onTap: onTap,
    );
  }
}



/* ---------------- EMPLOYEES LIGHT ---------------- */

