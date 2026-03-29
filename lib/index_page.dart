import 'package:phone_java/page/family_page.dart';
import 'package:phone_java/page/health_page.dart';
import 'package:phone_java/page/home_content.dart';
import 'package:phone_java/app_fonts.dart'; // 💡 必须引入含有 FontManager 和 UserProfileManager 的文件
import 'package:phone_java/page/settings_page.dart';
import 'package:flutter/material.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key});

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> {
  int _currentIndex = 0;

  // 颜色定义
  final Color gray800 = const Color(0xFF1F2937);
  final Color gray500 = const Color(0xFF6B7280);
  final Color gray100 = const Color(0xFFF3F4F6);
  final Color blue600 = const Color(0xFF2563EB);
  final Color blue50 = const Color(0xFFEFF6FF);

  late final List<Map<String, dynamic>> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      {
        'title': '帮帮',
        'subtitle': '您的智能助手',
        'icon': Icons.home_outlined,
        'activeIcon': Icons.home_rounded,
        'label': '主页',
        'page': const HomeContent(),
      },
      {
        'title': '健康管家',
        'subtitle': '让帮帮助您管理健康',
        'icon': Icons.favorite_border_rounded,
        'activeIcon': Icons.favorite_rounded,
        'label': '健康',
        'page': const HealthPage(),
      },
      {
        'title': '家人互联',
        'subtitle': '一键联系家人',
        'icon': Icons.people_outline_rounded,
        'activeIcon': Icons.people_rounded,
        'label': '家人',
        'page': const FamilyPage(),
      },
      {
        'title': '设置',
        'subtitle': '一次设置，永久省心',
        'icon': Icons.settings_outlined,
        'activeIcon': Icons.settings_rounded,
        'label': '设置',
        'page': const SettingsPage(),
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs[_currentIndex];

    // 💡 关键：同时监听字体缩放和用户信息（头像）的变化
    return ListenableBuilder(
      listenable: Listenable.merge([FontManager(), UserProfileManager()]),
      builder: (context, child) {
        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.white,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: gray100, width: 1)),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    // 💡 左侧：固定宽度 90，确保不挤压标题
                    SizedBox(
                      width: 90,
                      child: _currentIndex == 0
                          ? Center(
                        child: CircleAvatar(
                          radius: 28, // 放大后的背景圈
                          backgroundColor: blue50,
                          child: Icon(
                            // 💡 从全局管理器获取当前选中的图标
                            UserProfileManager().currentAvatarIcon,
                            color: Colors.blueAccent,
                            size: 38, // 放大后的图标大小
                          ),
                        ),
                      )
                          : null,
                    ),

                    // 中间：标题区域
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentTab['title'],
                            style: TextStyle(
                                fontSize: AppFonts.titleLarge,
                                fontWeight: FontWeight.bold,
                                color: gray800
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentTab['subtitle'],
                            style: TextStyle(
                                fontSize: AppFonts.bodySmall,
                                color: gray500
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 💡 右侧：固定宽度 90 的透明占位，实现标题绝对居中
                    const SizedBox(width: 90),
                  ],
                ),
              ),
            ),
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
          bottomNavigationBar: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 34),
            height: 90, // 稍微增高以适配大字体
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(44),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 25,
                    offset: const Offset(0, 10)
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (index) {
                return _buildNavItem(index, _tabs[index]);
              }),
            ),
          ),
        );
      },
    );
  }

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
                size: 30,
                color: isActive ? blue600 : gray500
            ),
            const SizedBox(height: 2),
            Text(
              tab['label'],
              style: TextStyle(
                fontSize: AppFonts.caption,
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