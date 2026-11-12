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

    final isDark = HomeThemeTokens.isDark(context);
    final navBg = isDark
        ? HomeThemeTokens.darkCardSurface.withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.94);
    final borderCol = HomeThemeTokens.border(context);
    final activeColor = HomeThemeTokens.teal(context);
    final activePillBg = HomeThemeTokens.softTeal(context);
    final inactiveColor = HomeThemeTokens.textSecondary(context);
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animDuration = disableAnim ? Duration.zero : const Duration(milliseconds: 220);

    final items = const [
      (
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home',
        route: '/home',
      ),
      (
        icon: Icons.credit_card_outlined,
        activeIcon: Icons.credit_card_rounded,
        label: 'Payments',
        route: '/payments',
      ),
      (
        icon: Icons.restaurant_outlined,
        activeIcon: Icons.restaurant_rounded,
        label: 'Food',
        route: '/food-menu',
      ),
      (
        icon: Icons.menu_rounded,
        activeIcon: Icons.menu_rounded,
        label: 'Menu',
        route: '/menu',
      ),
    ];

    return Scaffold(
      backgroundColor: HomeThemeTokens.bg(context),
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(
            top: BorderSide(color: borderCol, width: 1.0),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? const Color(0x33000000)
                  : const Color(0x0A0E1A1F),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = index == currentIndex;
                return Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.go(item.route),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: animDuration,
                              curve: Curves.easeOutCubic,
                              width: 56,
                              height: 30,
                              decoration: BoxDecoration(
                                color: isSelected ? activePillBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Center(
                                child: AnimatedScale(
                                  duration: animDuration,
                                  curve: Curves.easeOutBack,
                                  scale: isSelected ? 1.05 : 1.0,
                                  child: Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    size: 22,
                                    color: isSelected ? activeColor : inactiveColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedDefaultTextStyle(
                              duration: animDuration,
                              curve: Curves.easeOutCubic,
                              style: HomeThemeTokens.manrope(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? activeColor : inactiveColor,
                              ),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
