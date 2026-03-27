import 'package:flutter/material.dart';

import '../../utils/app_language.dart';
import '../../utils/app_theme_mode.dart';
import '../../utils/app_text.dart';
import '../../widgets/employee_drawers.dart';
import '../admin/settings_screens.dart' show showFontSizePopup, showLanguagePopup;

class EmployeeSettingsPage extends StatelessWidget {
  const EmployeeSettingsPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  final String employeeId;
  final String employeeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: EmployeeMenu(
        employeeName: employeeName,
        employeeId: employeeId,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    tr(context, 'Settings'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE1E1E1)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.language_outlined),
                      title: Text(tr(context, 'Language')),
                      subtitle: Text(
                        AppLanguageScope.of(context).isFrench
                            ? tr(context, 'Français')
                            : tr(context, 'English'),
                      ),
                      onTap: () => showLanguagePopup(context, isDark: false),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text(tr(context, 'Change Font Size')),
                      onTap: () => showFontSizePopup(context, isDark: false),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text(tr(context, 'Change to Dark Mode')),
                      onTap: () {
                        AppThemeModeController.instance.setDark(true);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmployeeSettingsDarkPage(
                              employeeId: employeeId,
                              employeeName: employeeName,
                            ),
                          ),
                        );                      },
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
}

class EmployeeSettingsDarkPage extends StatelessWidget {
  const EmployeeSettingsDarkPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  final String employeeId;
  final String employeeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: EmployeeMenuDark(
        employeeName: employeeName,
        employeeId: employeeId,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    tr(context, 'Settings'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.language_outlined, color: Colors.white70),
                      title: Text(
                        tr(context, 'Language'),
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        AppLanguageScope.of(context).isFrench
                            ? tr(context, 'Français')
                            : tr(context, 'English'),
                        style: TextStyle(color: Colors.white54),
                      ),
                      onTap: () => showLanguagePopup(context, isDark: true),
                    ),
                    Divider(height: 1, color: Color(0xFF2A2A2A)),
                    ListTile(
                      leading: Icon(Icons.description_outlined, color: Colors.white70),
                      title: Text(
                        tr(context, 'Change Font Size'),
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: () => showFontSizePopup(context, isDark: true),
                    ),
                    Divider(height: 1, color: Color(0xFF2A2A2A)),
                    ListTile(
                      leading: Icon(Icons.light_mode_outlined, color: Colors.white70),
                      title: Text(
                        tr(context, 'Change to Light Mode'),
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        AppThemeModeController.instance.setDark(false);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmployeeSettingsPage(
                              employeeId: employeeId,
                              employeeName: employeeName,
                            ),
                          ),
                        );                      },
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
}
