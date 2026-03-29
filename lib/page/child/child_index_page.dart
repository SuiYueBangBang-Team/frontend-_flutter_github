import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';

import 'child_community_page.dart';
import 'child_health_page.dart';
import 'child_location_page.dart';
import 'child_settings_page.dart'; // 引入字体管理

class ChildIndexPage extends StatefulWidget {
  const ChildIndexPage({super.key});

  @override
  State<ChildIndexPage> createState() => _ChildIndexPageState();
}

class _ChildIndexPageState extends State<ChildIndexPage> {
  int _currentIndex = 0;

  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);

  final List<Map<String, dynamic>> _tabs = [
    {
      'title': '',
      'subtitle': '',
      'icon': Icons.location_on_outlined,
      'activeIcon': Icons.location_on_rounded,
      'label': '定位',
      'page': const ChildLocationPage(),
    },
    {
      'title': '健康督促',
      'subtitle': '随时督促长辈保持身体健康',
      'icon': Icons.favorite_border_rounded,
      'activeIcon': Icons.favorite_rounded,
      'label': '健康',
      'page': const ChildHealthPage(),
    },
    {
      'title': '子女社区',
      'subtitle': '交流守护心得',
      'icon': Icons.forum_outlined,
      'activeIcon': Icons.forum_rounded,
      'label': '社区',
      'page': const ChildCommunityPage(),
    },
    {
      'title': '系统设置',
      'subtitle': '账号隐私与功能管理',
      'icon': Icons.settings_outlined,
      'activeIcon': Icons.settings_rounded,
      'label': '设置',
      'page': const ChildSettingsPage(),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs[_currentIndex];

    return ListenableBuilder(
      listenable: FontManager(),
      builder: (context, child) {
        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.white,
          appBar: _currentIndex == 0
              ? null
              : PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: _buildCustomAppBar(currentTab),
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [blue50, blue50.withOpacity(0.4), Colors.white],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: IndexedStack(
              index: _currentIndex,
              children: _tabs.map((tab) => tab['page'] as Widget).toList(),
            ),
          ),
          bottomNavigationBar: _buildFloatingNavigationBar(), // 使用新样式
        );
      },
    );
  }

  // 自定义 AppBar（与 IndexPage 一致）
  Widget _buildCustomAppBar(Map<String, dynamic> tab) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: gray100, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const SizedBox(width: 90),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tab['title'] ?? '',
                    style: TextStyle(
                      fontSize: AppFonts.titleLarge,
                      fontWeight: FontWeight.bold,
                      color: gray800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab['subtitle'] ?? '',
                    style: TextStyle(
                      fontSize: AppFonts.bodySmall,
                      color: gray500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 90),
          ],
        ),
      ),
    );
  }

  // 底部导航栏：完全参考 IndexPage 的样式
  Widget _buildFloatingNavigationBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 34),
      height: 90, // 与 IndexPage 一致
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(44), // 与 IndexPage 一致
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_tabs.length, (index) {
          return _buildNavItem(index, _tabs[index]);
        }),
      ),
    );
  }

  // 导航项构建（与 IndexPage 的 _buildNavItem 完全一致）
  Widget _buildNavItem(int index, Map<String, dynamic> tab) {
    bool isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? blue50 : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? tab['activeIcon'] : tab['icon'],
              size: 30, // 与 IndexPage 一致
              color: isActive ? blue600 : gray500,
            ),
            const SizedBox(height: 2),
            Text(
              tab['label'],
              style: TextStyle(
                fontSize: AppFonts.caption, // 使用 AppFonts
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? blue600 : gray500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}