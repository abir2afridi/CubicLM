import 'dart:ui';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../controllers/chat_controller.dart';
import '../controllers/home_controller.dart';
import '../core/colors.dart';
import '../services/hive_service.dart';
import '../theme/design_tokens.dart';
import '../utils/app_snackbar.dart';
import 'chat_view.dart';
import 'model_view.dart';
import 'server_view.dart';
import 'app_settings_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeController controller;

  Future<void> _handleOnboardingDeepLink() async {
    try {
      if (!Get.isRegistered<HiveService>()) return;
      final hive = Get.find<HiveService>();
      final shouldOpen =
          hive.getSetting<bool>('onboarding_open_hub', defaultValue: false) ??
              false;
      if (!shouldOpen) return;
      await hive.deleteSetting('onboarding_open_hub');
      controller.changeTab(1);
      Future.delayed(const Duration(milliseconds: 400), () {
        AppSnackbar.showTop(
          'Explore → Local for recommended model',
          'Check the Local tab for your recommended model',
          icon: LucideIcons.compass,
          iconName: 'compass',
          duration: const Duration(seconds: 3),
          logHistory: false,
        );
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    controller = Get.find<HomeController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.checkResumeModel(context);
      if (mounted) _handleOnboardingDeepLink();
    });
  }

  List<_NavItem> get _tabs => [
        _NavItem(
            icon: LucideIcons.messageSquare,
            activeIcon: LucideIcons.messageSquare,
            label: 'nav_chat'.tr),
        _NavItem(
            icon: LucideIcons.compass,
            activeIcon: LucideIcons.compass,
            label: 'nav_explore'.tr),
        _NavItem(
            icon: LucideIcons.server,
            activeIcon: LucideIcons.server,
            label: 'nav_nodes'.tr),
        _NavItem(
            icon: LucideIcons.settings,
            activeIcon: LucideIcons.settings,
            label: 'nav_settings'.tr),
      ];

  bool get _isWide {
    if (kIsWeb) return true;
    return Get.width >= 800;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffold = Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      body: Obx(() {
        final content = IndexedStack(
          index: controller.currentTab.value,
          children: [
            ChatView(),
            const ModelView(),
            const ServerView(),
            const AppSettingsView()
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
    // Desktop keyboard shortcuts: Ctrl+N new chat, Ctrl+F history search,
    // Ctrl+, settings, Ctrl+1..4 switch tabs. Invisible, zero visual risk.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _shortcutNewChat,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _shortcutHistorySearch,
          const SingleActivator(LogicalKeyboardKey.comma, control: true):
              _shortcutSettings,
          const SingleActivator(LogicalKeyboardKey.digit1, control: true):
              _shortcutTab0,
          const SingleActivator(LogicalKeyboardKey.digit2, control: true):
              _shortcutTab1,
          const SingleActivator(LogicalKeyboardKey.digit3, control: true):
              _shortcutTab2,
          const SingleActivator(LogicalKeyboardKey.digit4, control: true):
              _shortcutTab3,
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  void _shortcutNewChat() {
    try {
      Get.find<ChatController>().createNewChat();
    } catch (_) {}
  }

  void _shortcutHistorySearch() {
    try {
      Get.find<ChatController>().openHistorySearch();
    } catch (_) {}
  }

  void _shortcutSettings() => controller.changeTab(3);
  void _shortcutTab0() => controller.changeTab(0);
  void _shortcutTab1() => controller.changeTab(1);
  void _shortcutTab2() => controller.changeTab(2);
  void _shortcutTab3() => controller.changeTab(3);

  Widget _buildBottomNav(BuildContext context, bool isDark) {
    return Container(
      height: 72 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: (isDark ? Dt.canvasDark : Dt.canvas).withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: BottomNavigationBar(
            currentIndex: controller.currentTab.value,
            onTap: controller.changeTab,
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.2),
            unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 0.2),
            items: [
              for (final tab in _tabs)
                BottomNavigationBarItem(
                  icon: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Icon(tab.icon, size: 22),
                  ),
                  activeIcon: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Icon(tab.activeIcon, size: 22),
                  ),
                  label: tab.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool isDark) {
    const accent = AppColors.primary;
    final muted = Theme.of(context).hintColor;

    return Container(
      width: 84,
      color: isDark ? Dt.canvasDark : Dt.canvas,
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
                      border: Border.all(
                        color: sel ? accent.withValues(alpha: 0.1) : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (sel)
                          Positioned(
                            left: 0,
                            top: 20,
                            bottom: 20,
                            width: 3,
                            child: Container(
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        Center(
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
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        })),
        const SizedBox(height: 20),
        IconButton(
          onPressed: () => Get.find<ChatController>().createNewChat(),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add_rounded, color: AppColors.primary, size: 22),
          ),
          tooltip: 'New Chat',
        ),
        const SizedBox(height: 24),
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
