import 'package:flutter/material.dart';

import '../../widgets/admin_drawers.dart';
import '../../main.dart';


class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
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
                    'Settings',
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
                      leading: Icon(Icons.description_outlined),
                      title: Text('Change Font Size'),
                      onTap: () {
                        _showFontSizeDialog(context, isDark: false);
                      },
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text('Change to Dark Mode'),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSettingsDarkPage(),
                          ),
                        );
                      },
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

/* ---------------- SETTINGS DARK ---------------- */

class AdminSettingsDarkPage extends StatelessWidget {
  const AdminSettingsDarkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
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
                    'Settings',
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
                      leading: Icon(Icons.description_outlined, color: Colors.white70),
                      title: Text('Change Font Size', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        _showFontSizeDialog(context, isDark: true);
                      },
                    ),
                    Divider(height: 1, color: Color(0xFF2A2A2A)),
                    ListTile(
                      leading: Icon(Icons.light_mode_outlined, color: Colors.white70),
                      title: Text('Change to Light Mode', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminSettingsPage(),
                          ),
                        );
                      },
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

void _showFontSizeDialog(BuildContext context, {required bool isDark}) {
  double tempScale = MyApp.of(context).fontScale;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
            title: Text(
              'Change Font Size',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Size: ${(tempScale * 100).round()}%',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                Slider(
                  value: tempScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  label: '${(tempScale * 100).round()}%',
                  onChanged: (value) {
                    setState(() {
                      tempScale = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  MyApp.of(context).setFontScale(1.0);
                  Navigator.pop(dialogContext);
                },
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  MyApp.of(context).setFontScale(tempScale);
                  Navigator.pop(dialogContext);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
}
