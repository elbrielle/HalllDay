import 'package:flutter/material.dart';

class AppNavDrawer extends StatelessWidget {
  final String currentRoute;

  const AppNavDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/brand/logo.png',
                    height: 48,
                    color: theme.colorScheme.primary,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "IDK Can You?",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _DrawerItem(
                  icon: Icons.home_rounded,
                  label: "Home",
                  isSelected: currentRoute == '/',
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    if (currentRoute != '/') {
                      Navigator.of(context).pushReplacementNamed('/');
                    }
                  },
                ),
                _DrawerItem(
                  icon: Icons.dashboard_rounded,
                  label: "Dashboard",
                  isSelected: currentRoute == '/admin',
                  onTap: () {
                    Navigator.pop(context);
                    if (currentRoute != '/admin') {
                      Navigator.of(context).pushReplacementNamed('/admin');
                    }
                  },
                ),
              ],
            ),
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "v1.0.0 Beta",
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material 3 Navigation Drawer styling
    final color = isSelected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final backgroundColor = isSelected
        ? theme.colorScheme.secondaryContainer
        : Colors.transparent;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        selected: isSelected,
        tileColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        onTap: onTap,
      ),
    );
  }
}
