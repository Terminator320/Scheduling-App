import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/employee_record.dart';
import '../screens/auth/auth_screens.dart';
import '../services/user_service.dart';
import '../utils/app_text.dart';
import '../utils/app_theme_mode.dart';

class AdminMenuDrawer extends StatelessWidget {
  const AdminMenuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AdminDrawerLoader(isDark: false);
  }
}

class _AdminDrawerLoader extends StatelessWidget {
  const _AdminDrawerLoader({
    required this.isDark,
  });

  final bool isDark;

  Future<EmployeeRecord?> _loadCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return null;

    final userDoc = await UserService.findUserByUid(uid);
    if (userDoc == null) return null;

    return EmployeeRecord.fromMap(userDoc.id, userDoc.data());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmployeeRecord?>(
      future: _loadCurrentUser(),
      builder: (context, snapshot) {
        final currentUser = snapshot.data;

        return _AdminDrawerShell(
          isDark: isDark,
          currentUser: currentUser,
          name: currentUser?.name.isNotEmpty == true
              ? currentUser!.name
              : tr(context, 'Admin name'),
        );
      },
    );
  }
}

class _AdminDrawerShell extends StatelessWidget {
  const _AdminDrawerShell({
    required this.isDark,
    required this.name,
    required this.currentUser,
  });

  final bool isDark;
  final String name;
  final EmployeeRecord? currentUser;

  @override
  Widget build(BuildContext context) {
    final suffix = themePathSuffix(context);

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
                name,
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
              onTap: () async {
                await FirebaseAuth.instance.signOut();

                if (!context.mounted) return;

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppThemeModeScope.of(context).isDark
                        ? const LoginDarkScreen()
                        : const LoginLightScreen(),
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
                Navigator.pop(context);
                Navigator.pushReplacementNamed(
                  context,
                  '/admin/calendar/$suffix',
                );
              },
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.badge_outlined,
              title: tr(context, 'Employees'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(
                  context,
                  '/admin/employees/$suffix',
                );
              },
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.group_outlined,
              title: tr(context, 'Clients'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(
                  context,
                  '/admin/clients/$suffix',
                );
              },
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.event_note_outlined,
              title: tr(context, 'Appointments'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(
                  context,
                  '/admin/appointments/$suffix',
                );
              },
            ),
            _DrawerMenuItem(
              isDark: isDark,
              icon: Icons.settings_outlined,
              title: tr(context, 'Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(
                  context,
                  '/admin/settings/$suffix',
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