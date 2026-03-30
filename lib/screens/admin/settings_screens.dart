import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_font_scale.dart';
import '../../utils/app_language.dart';
import '../../utils/app_text.dart';
import '../../utils/app_theme_mode.dart';
import '../../widgets/admin_drawers.dart';

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
                    tr(context, 'Settings'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
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
                        Navigator.pushReplacementNamed(
                          context,
                          '/admin/settings/${themePathSuffix(context)}',
                        );
                      },
                    ),
                    Divider(height: 1),
                    _AdminChangeEmailTile(isDark: false),
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


class _AdminChangeEmailTile extends StatelessWidget {
  final bool isDark;

  const _AdminChangeEmailTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('uid', isEqualTo: currentUid)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SizedBox.shrink();
        }

        final data = snapshot.data!.docs.first.data();
        final role = (data['role'] ?? '').toString().trim().toLowerCase();

        if (role != 'admin') {
          return SizedBox.shrink();
        }

        return ListTile(
          leading: Icon(
            Icons.email_outlined,
            color: isDark ? Colors.white70 : null,
          ),
          title: Text(
            tr(context, 'Change Email'),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          subtitle: Text(
            tr(context, 'Admin only'),
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          onTap: () => _showChangeEmailDialog(context, isDark: isDark),
        );
      },
    );
  }
}

Future<void> showFontSizePopup(
    BuildContext context, {
      required bool isDark,
    }) async {
  final controller = AppFontScaleController.instance;
  double tempValue = controller.value;

  await showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final percent = (tempValue * 100).round();

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: EdgeInsets.fromLTRB(22, 18, 22, 18),
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF121212) : Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: isDark
                    ? Border.all(color: Color(0xFF2A2A2A))
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(context, 'Change Font Size'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '${tr(context, 'Size')}: $percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                    ),
                    child: Slider(
                      min: 0.8,
                      max: 1.4,
                      divisions: 6,
                      value: tempValue,
                      onChanged: (value) {
                        setState(() => tempValue = value);
                      },
                    ),
                  ),
                  SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 320;

                      return Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: compact ? 8 : 0,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() => tempValue = 1.0);
                            },
                            child: Text(tr(context, 'Reset')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(tr(context, 'Cancel')),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Color(0xFFEDE7F6),
                              foregroundColor: Color(0xFF6A4BBC),
                              padding: EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () {
                              controller.setScale(tempValue);
                              Navigator.pop(dialogContext);
                            },
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(tr(context, 'Apply')),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showLanguagePopup(
    BuildContext context, {
      required bool isDark,
    }) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 22),
          decoration: BoxDecoration(
            color: isDark ? Color(0xFF121212) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: isDark
                ? Border.all(color: Color(0xFF2A2A2A))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark
                      ? Color(0xFF3A3A3A)
                      : Color(0xFFD0D0D0),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              SizedBox(height: 18),
              Text(
                tr(context, 'Choose Language'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              SizedBox(height: 18),
              _languageOptionTile(
                context,
                label: tr(context, 'English'),
                isDark: isDark,
                isSelected: AppLanguageScope.of(context).value == 'en',
                onTap: () {
                  AppLanguageController.instance.setLanguage('en');
                  Navigator.pop(context);
                },
              ),
              SizedBox(height: 10),
              _languageOptionTile(
                context,
                label: tr(context, 'Français'),
                isDark: isDark,
                isSelected: AppLanguageScope.of(context).value == 'fr',
                onTap: () {
                  AppLanguageController.instance.setLanguage('fr');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _languageOptionTile(
    BuildContext context, {
      required String label,
      required bool isDark,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Color(0xFF171717) : Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Color(0xCC6D29F6)
                : (isDark
                ? Color(0xFF2D2D2D)
                : Color(0xFFE1E1E1)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, color: Color(0xCC6D29F6)),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showChangeEmailDialog(
    BuildContext context, {
      required bool isDark,
    }) async {
  final controller = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return;

  await showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: isDark ? Color(0xFF121212) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: isDark
              ? BorderSide(color: Color(0xFF2A2A2A))
              : BorderSide.none,
        ),
        title: Text(
          tr(dialogContext, 'Change Email'),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            labelText: tr(dialogContext, 'New email'),
            labelStyle: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? Color(0xFF2A2A2A)
                    : Color(0xFFE1E1E1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Color(0xCC6D29F6),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(dialogContext, 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final newEmail = controller.text.trim().toLowerCase();
              if (newEmail.isEmpty) return;

              try {
                await user.verifyBeforeUpdateEmail(newEmail);

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        tr(
                          context,
                          'Verification email sent. Please confirm the new email address.',
                        ),
                      ),
                    ),
                  );
                }
              } on FirebaseAuthException catch (e) {
                String message = tr(context, 'Error updating email');

                if (e.code == 'requires-recent-login') {
                  message = tr(
                    context,
                    'Please log in again before changing email',
                  );
                } else if (e.code == 'email-already-in-use') {
                  message = tr(context, 'Email already in use');
                } else if (e.code == 'invalid-email') {
                  message = tr(context, 'Invalid email');
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              }
            },
            child: Text(tr(dialogContext, 'Save')),
          ),
        ],
      );
    },
  );
}