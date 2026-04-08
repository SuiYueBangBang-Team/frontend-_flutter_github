import 'package:flutter/material.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(30),
        width: double.infinity,
        decoration: const BoxDecoration(color: Color(0xFFEFF6FF)), // blue50
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("欢迎使用帮帮助手", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("请选择您的身份", style: TextStyle(fontSize: 18, color: Colors.black54)),
            const SizedBox(height: 50),

            // 角色按钮：父母
            _buildRoleCard(context, "我是长辈", Icons.elderly, Colors.blue, () {
              //  核心修改：带上 ELDER 参数
              Navigator.pushNamed(context, '/login', arguments: 'ELDER');
            }),

            const SizedBox(height: 20),

            // 角色按钮：子女
            _buildRoleCard(context, "我是子女", Icons.family_restroom, Colors.green, () {
              //  核心修改：带上 CHILD 参数
              Navigator.pushNamed(context, '/login', arguments: 'CHILD');
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 20)],
        ),
        child: Column(
          children: [
            Icon(icon, size: 60, color: color),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}