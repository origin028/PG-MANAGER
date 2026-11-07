import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    String location = '/home';
    try {
      location = GoRouterState.of(context).uri.toString();
    } catch (_) {
      try {
        location = GoRouter.of(context).routeInformationProvider.value.uri.toString();
      } catch (_) {
        location = '/home';
      }
    }

    // Determine current active index based on route
    int currentIndex = 0;
    if (location.startsWith('/payments')) currentIndex = 1;
    if (location.startsWith('/food-menu')) currentIndex = 2;
    if (location.startsWith('/menu')) currentIndex = 3;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == 0) context.go('/home');
          if (index == 1) context.go('/payments');
          if (index == 2) context.go('/food-menu');
          if (index == 3) context.go('/menu');
        },
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        selectedItemColor: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
        unselectedItemColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.payment_outlined),
            activeIcon: Icon(Icons.payment),
            label: 'Payments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu_outlined),
            activeIcon: Icon(Icons.restaurant_menu),
            label: 'Food Menu',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            activeIcon: Icon(Icons.menu),
            label: 'Menu',
          ),
        ],
      ),
    );
  }
}
