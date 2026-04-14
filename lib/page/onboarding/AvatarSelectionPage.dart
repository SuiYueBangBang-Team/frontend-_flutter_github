import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart'; // 💡 保持你的全局管理器

class AvatarSelectionPage extends StatefulWidget {
  const AvatarSelectionPage({super.key});

  @override
  State<AvatarSelectionPage> createState() => _AvatarSelectionPageState();
}

class _AvatarSelectionPageState extends State<AvatarSelectionPage> {
  final userManager = UserProfileManager();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: userManager,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SafeArea(
            child: SingleChildScrollView( // 💡 新增：包裹一个可滚动组件，防止小屏幕溢出
              child: ConstrainedBox(
                // 确保内容最少占满整个屏幕高度，如果内容过多则可以滚动
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 改用 spaceEvenly 让元素均匀分布
                    children: [
                      // --- 顶部区域 ---
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text("您好，我是帮帮",
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B))),
                      ),
                      const SizedBox(height: 8),
                      const Text("很高兴认识您！",
                          style: TextStyle(fontSize: 20, color: Colors.blueGrey)),

                      const SizedBox(height: 30),

                      // --- 形象选择标题 ---
                      const Text("请选择您喜欢的帮帮形象",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      const SizedBox(height: 15),

                      // --- 形象选择区域 ---
                      // 去掉了 Flexible/Expanded，因为在 ScrollView 里它们需要明确的高度
                      SizedBox(
                        height: 220, // 💡 给定一个固定高度
                        child: Column(
                          children: [
                            // 第一行
                            Expanded(
                              child: Row(
                                children: [
                                  _buildAvatarItem(0),
                                  const SizedBox(width: 12),
                                  _buildAvatarItem(1),
                                  const SizedBox(width: 12),
                                  _buildAvatarItem(2),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 第二行
                            Expanded(
                              child: Row(
                                children: [
                                  _buildAvatarItem(3),
                                  const SizedBox(width: 12),
                                  _buildAvatarItem(4),
                                  const SizedBox(width: 12),
                                  _buildAvatarItem(5),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // --- 语言选择部分 ---
                      const Text("选择您习惯的语言",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 12),

                      // 💡 修改点：将 GridView 替换为 Row 布局
                      Row(
                        children: [
                          Expanded(child: _buildLanguageItem(0)),
                          const SizedBox(width: 15),
                          Expanded(child: _buildLanguageItem(1)),
                        ],
                      ),

                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 65,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pushNamed(context, "/home"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 0,
                          ),
                          child: const FittedBox(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
                                SizedBox(width: 8),
                                Text("开始使用帮帮助手", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  // 头像卡片
  Widget _buildAvatarItem(int index) {
    bool selected = userManager.avatarIndex == index;
    final avatar = UserProfileManager.avatars[index];

    return Expanded(
      child: GestureDetector(
        onTap: () => userManager.setAvatar(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? Colors.blueAccent : Colors.grey.shade200,
                width: selected ? 2.5 : 1),
            boxShadow: [
              if (selected)
                BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
            ],
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            double iconBoxSize = constraints.maxHeight * 0.5;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: iconBoxSize / 2,
                  backgroundColor:
                  selected ? Colors.blueAccent : Colors.blueGrey.shade50,
                  child: Icon(avatar["icon"] as IconData,
                      color: selected ? Colors.white : Colors.blueGrey,
                      size: iconBoxSize * 0.6),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(avatar["name"] as String,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                            color: selected ? Colors.blueAccent : Colors.black87)),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // 语言选择项
  Widget _buildLanguageItem(int index) {
    bool selected = userManager.languageIndex == index;
    return GestureDetector(
      onTap: () => userManager.setLanguage(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 55, // 给定固定高度，方便点击
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.blueAccent : Colors.grey.shade200, width: selected ? 2 : 1),
        ),
        child: Text(UserProfileManager.languages[index],
            style: TextStyle(fontSize: 18, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? Colors.white : Colors.black87)),
      ),
    );
  }
}