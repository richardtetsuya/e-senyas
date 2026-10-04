import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/esenyas_app_bar.dart';

/// Settings screen with grouped toggle/navigation rows.
///
/// Recreates SettingsScreen.tsx with profile card, notification
/// settings, appearance toggles, language, and about links.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _vibration = true;
  bool _sound = false;
  bool _highContrast = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final dm = provider.darkMode;
    final headerBg =
        dm ? ESenyasColors.primaryBlueDark : ESenyasColors.primaryBlue;
    final bodyBg =
        dm ? ESenyasColors.backgroundDark : ESenyasColors.backgroundLight;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ESenyasAppBar(title: 'Settings', showBack: false),
            Expanded(
              child: Container(
                color: bodyBg,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Profile card
                      Container(
                        color: headerBg,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.smartphone, size: 26, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'e-Senyas',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'v1.0 Beta · Academic Prototype',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Rounded cutout
                      Container(
                        height: 20,
                        color: headerBg,
                        child: Container(
                          decoration: BoxDecoration(
                            color: bodyBg,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Notifications group
                            _GroupLabel(text: 'Notifications', darkMode: dm),
                            _SettingsGroup(
                              darkMode: dm,
                              children: [
                                _SettingRow(
                                  icon: Icons.notifications_outlined,
                                  iconBg: ESenyasColors.primaryBlue,
                                  label: 'Push Notifications',
                                  subtitle: 'Alerts for new updates',
                                  toggle: true,
                                  toggleValue: _notifications,
                                  onToggle: (v) => setState(() => _notifications = v),
                                  darkMode: dm,
                                ),
                                _SettingRow(
                                  icon: Icons.vibration,
                                  iconBg: Colors.purple,
                                  label: 'Vibration',
                                  subtitle: 'Haptic feedback on gestures',
                                  toggle: true,
                                  toggleValue: _vibration,
                                  onToggle: (v) => setState(() => _vibration = v),
                                  darkMode: dm,
                                ),
                                _SettingRow(
                                  icon: Icons.volume_up_outlined,
                                  iconBg: Colors.orange,
                                  label: 'Sound Effects',
                                  subtitle: 'Audio cues on detection',
                                  toggle: true,
                                  toggleValue: _sound,
                                  onToggle: (v) => setState(() => _sound = v),
                                  darkMode: dm,
                                  isLast: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Appearance group
                            _GroupLabel(text: 'Appearance', darkMode: dm),
                            _SettingsGroup(
                              darkMode: dm,
                              children: [
                                _SettingRow(
                                  icon: Icons.dark_mode_outlined,
                                  iconBg: ESenyasColors.gray700,
                                  label: 'Dark Mode (Applies to entire app)',
                                  subtitle: 'Switch to dark theme',
                                  toggle: true,
                                  toggleValue: dm,
                                  onToggle: (v) => provider.setDarkMode(v),
                                  darkMode: dm,
                                ),
                                _SettingRow(
                                  icon: Icons.visibility_outlined,
                                  iconBg: ESenyasColors.accentGreen,
                                  label: 'High Contrast',
                                  subtitle: 'Improved visibility',
                                  toggle: true,
                                  toggleValue: _highContrast,
                                  onToggle: (v) => setState(() => _highContrast = v),
                                  darkMode: dm,
                                  isLast: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // AI & Landmark Detection group
                            _GroupLabel(text: 'AI & Landmark Detection', darkMode: dm),
                            _SettingsGroup(
                              darkMode: dm,
                              children: [
                                _SettingRow(
                                  icon: Icons.front_hand_outlined,
                                  iconBg: const Color(0xFF00B0FF),
                                  label: 'Hand Skeleton & Landmarks',
                                  subtitle: 'Ipakita ang 21 points & skeleton sa camera',
                                  toggle: true,
                                  toggleValue: provider.showHandLandmarks,
                                  onToggle: (v) => provider.setShowHandLandmarks(v),
                                  darkMode: dm,
                                  isLast: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Language group
                            _GroupLabel(text: 'Language & Region', darkMode: dm),
                            _SettingsGroup(
                              darkMode: dm,
                              children: [
                                _SettingRow(
                                  icon: Icons.language,
                                  iconBg: Colors.lightBlue,
                                  label: 'Display Language',
                                  subtitle: 'Filipino / English',
                                  darkMode: dm,
                                  onTap: () {},
                                  isLast: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // About group
                            _GroupLabel(text: 'About', darkMode: dm),
                            _SettingsGroup(
                              darkMode: dm,
                              children: [
                                _SettingRow(
                                  icon: Icons.shield_outlined,
                                  iconBg: ESenyasColors.accentGreen,
                                  label: 'Privacy Policy',
                                  subtitle: 'How we handle your data',
                                  darkMode: dm,
                                  onTap: () => Navigator.of(context)
                                      .pushNamed('/privacy-policy'),
                                ),
                                _SettingRow(
                                  icon: Icons.info_outline,
                                  iconBg: ESenyasColors.primaryBlue,
                                  label: 'App Information',
                                  subtitle: 'Licenses, open source',
                                  darkMode: dm,
                                  onTap: () => Navigator.of(context)
                                      .pushNamed('/app-info'),
                                  isLast: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Version
                            Center(
                              child: Text(
                                'e-Senyas v1.0.0 · Build 2024.001',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: dm
                                      ? ESenyasColors.gray500
                                      : ESenyasColors.gray400,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const ESenyasBottomNavBar(currentIndex: 3),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final bool darkMode;

  const _GroupLabel({required this.text, required this.darkMode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.55,
          color: darkMode ? ESenyasColors.lightBlueText : ESenyasColors.primaryBlue,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final bool darkMode;
  final List<Widget> children;

  const _SettingsGroup({required this.darkMode, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: darkMode ? ESenyasColors.cardDark : Colors.white,
        borderRadius:
            BorderRadius.circular(ESenyasDimens.borderRadiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final bool toggle;
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final bool darkMode;
  final bool isLast;

  const _SettingRow({
    required this.icon,
    required this.iconBg,
    required this.label,
    this.subtitle,
    this.toggle = false,
    this.toggleValue,
    this.onToggle,
    this.onTap,
    required this.darkMode,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: darkMode
                      ? ESenyasColors.gray700
                      : const Color(0xFFF5F5F5),
                ),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: ESenyasDimens.iconContainerSizeSm,
            height: ESenyasDimens.iconContainerSizeSm,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius:
                  BorderRadius.circular(ESenyasDimens.borderRadiusMd),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: darkMode ? Colors.white : ESenyasColors.gray900,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: darkMode
                          ? ESenyasColors.gray500
                          : ESenyasColors.gray400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (toggle && onToggle != null)
            Switch(
              value: toggleValue ?? false,
              onChanged: onToggle,
              activeTrackColor: ESenyasColors.primaryBlue,
            )
          else
            Icon(
              Icons.chevron_right,
              size: 16,
              color: darkMode ? ESenyasColors.gray600 : ESenyasColors.gray300,
            ),
        ],
      ),
    );

    if (toggle) return content;

    return InkWell(onTap: onTap, child: content);
  }
}
