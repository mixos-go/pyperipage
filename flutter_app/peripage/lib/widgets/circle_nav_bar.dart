import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Navigasi bawah custom -- 3 slot, dengan tombol CIRCLE besar di tengah
/// (terangkat/elevated, gradient brand) yang memisahkan 2 tombol biasa di
/// kiri & kanan. Terinspirasi pola navigasi modern (thumb-friendly, center
/// action button) -- lihat referensi UI/UX yang diberikan user.
///
/// Urutan: [kiri: Settings] [tengah: Print (circle, primary action)] [kanan: Workspace/Home]
class CircleNavBar extends StatelessWidget {
  final int selectedIndex; // 0 = home/workspace, 1 = print, 2 = settings
  final ValueChanged<int> onTap;

  const CircleNavBar({super.key, required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.surface;
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Bar dasar dengan lekukan di tengah buat "dudukan" circle button.
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: barColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _NavIconButton(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: 'Settings',
                    selected: selectedIndex == 2,
                    onTap: () => onTap(2),
                  ),
                ),
                const SizedBox(width: 72), // ruang buat circle button di tengah
                Expanded(
                  child: _NavIconButton(
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard,
                    label: 'Workspace',
                    selected: selectedIndex == 0,
                    onTap: () => onTap(0),
                  ),
                ),
              ],
            ),
          ),
          // Circle button tengah -- primary action (Print), terangkat di atas bar.
          Positioned(
            bottom: 28,
            child: GestureDetector(
              onTap: () => onTap(1),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: barColor, width: 4),
                ),
                child: Icon(
                  Icons.print,
                  color: Colors.white,
                  size: selectedIndex == 1 ? 28 : 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavIconButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? selectedIcon : icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ],
      ),
    );
  }
}
