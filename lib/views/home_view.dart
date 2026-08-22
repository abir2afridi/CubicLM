import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/home_controller.dart';
import '../core/colors.dart';
import 'chat_view.dart';
import 'model_view.dart';
import 'server_view.dart';
import 'settings_view.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  static const _tabs = [
    _NavItem(
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        label: 'Chat'),
    _NavItem(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: 'Explore'),
    _NavItem(
        icon: Icons.lan_outlined,
        activeIcon: Icons.lan_rounded,
        label: 'Nodes'),
    _NavItem(
        icon: Icons.tune_rounded,
        activeIcon: Icons.tune_rounded,
        label: 'Config'),
  ];

  bool get _isWide {
    if (kIsWeb) return true;
    return Get.width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.checkResumeModel(context);
    });
    return Scaffold(
      backgroundColor: isDark ? AppColors.bg : AppColors.bgLight,
      body: Obx(() {
        final content = IndexedStack(
          index: controller.currentTab.value,
          children: const [
            ChatView(),
            ModelView(),
            ServerView(),
            SettingsView()
          ],
        );
        if (_isWide) {
          return Row(children: [
            _buildSidebar(context, isDark),
            VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? AppColors.border : AppColors.borderLightMode),
            Expanded(child: content),
          ]);
        }
        return content;
      }),
      bottomNavigationBar:
          _isWide ? null : Obx(() => _buildBottomNav(context, isDark)),
    );
  }

  Widget _buildBottomNav(BuildContext context, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.bg : AppColors.bgLight,
      ),
      child: BottomNavigationBar(
        currentIndex: controller.currentTab.value,
        onTap: controller.changeTab,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 10),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 10),
        items: [
          for (final tab in _tabs)
            BottomNavigationBarItem(
              icon: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Icon(tab.icon, size: 22),
              ),
              activeIcon: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Icon(tab.activeIcon, size: 22),
              ),
              label: tab.label,
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool isDark) {
    const accent = AppColors.primary;
    final muted = Theme.of(context).hintColor;

    return Container(
      width: 84,
      color: isDark ? AppColors.bg : AppColors.bgLight,
      child: Column(children: [
        const SizedBox(height: 24),
        Image.asset(
          'assets/icons/CubicLM.png',
          width: 40,
          height: 40,
        ),
        const SizedBox(height: 32),
        Expanded(child: Obx(() {
          final current = controller.currentTab.value;
          return ListView.builder(
            itemCount: _tabs.length,
            itemBuilder: (_, i) {
              final tab = _tabs[i];
              final sel = current == i;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => controller.changeTab(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 64,
                    decoration: BoxDecoration(
                      color: sel ? accent.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(sel ? tab.activeIcon : tab.icon,
                              color: sel ? accent : muted, size: 22),
                          const SizedBox(height: 6),
                          Text(tab.label,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight:
                                      sel ? FontWeight.w800 : FontWeight.w600,
                                  color: sel ? accent : muted)),
                        ]),
                  ),
                ),
              );
            },
          );
        })),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(
      {required this.icon, required this.activeIcon, required this.label});
}
