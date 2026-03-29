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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // --- 顶部区域：使用弹性间距 ---
                  const Spacer(flex: 2),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("您好，我是帮帮",
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                  ),
                  const Text("很高兴认识您！",
                      style: TextStyle(fontSize: 20, color: Colors.blueGrey)),

                  const Spacer(flex: 2),

                  // --- 形象选择标题 ---
                  const Text("请选择您喜欢的帮帮形象",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 15),

                  // --- 💡 核心修复：形象选择区域 (不使用 GridView) ---
                  Flexible(
                    flex: 12, // 占据主要空间
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

                  const Spacer(flex: 2),

                  // --- 语言选择部分 ---
                  const Text("选择您习惯的语言",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 12),

                  Flexible(
                    flex: 6,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: UserProfileManager.languages.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.2, // 保持语言框较扁
                      ),
                      itemBuilder: (context, index) {
                        bool selected = userManager.languageIndex == index;
                        return _buildLanguageItem(index, selected);
                      },
                    ),
                  ),

                  const Spacer(flex: 3),

                  // --- 底部开始按钮 ---
                  SizedBox(
                    width: double.infinity,
                    height: 65,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, "/home"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      child: const FittedBox(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 24),
                            SizedBox(width: 8),
                            Text("开始使用帮帮助手",
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
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
        );
      },
    );
  }

  // 💡 头像卡片：使用 LayoutBuilder 实现图标大小自适应压缩
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
            // 根据当前卡片可用的最大高度，动态计算图标大小
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
  Widget _buildLanguageItem(int index, bool selected) {
    return GestureDetector(
      onTap: () => userManager.setLanguage(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? Colors.blueAccent : Colors.grey.shade200,
              width: 1),
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(UserProfileManager.languages[index],
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.white : Colors.black87)),
          ),
        ),
      ),
    );
  }
}