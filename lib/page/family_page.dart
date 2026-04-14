import 'package:flutter/material.dart';
import '../app_fonts.dart';       // 💡 使用相对路径
import '../utils/api_client.dart'; // 💡 引入请求客户端

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

  @override
  State<FamilyPage> createState() => FamilyPageState();
}

class FamilyPageState extends State<FamilyPage> {
  List<Map<String, dynamic>> familyMembers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchMembers();
  }

  Future<void> fetchMembers({bool isSilent = false}) async {
    if (!isSilent) setState(() => isLoading = true);
    try {
      var res = await ApiClient().get('/api/family/members');
      if (mounted) {
        setState(() {
          familyMembers = List<Map<String, dynamic>>.from(res ?? []);
        });
      }
    } catch (e) {
      if(mounted && !isSilent) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("数据加载失败")));
    } finally {
      if (mounted && !isSilent) setState(() => isLoading = false);
    }
  }

  // 乐观更新删除法
  Future<void> _deleteMember(int index) async {
    var member = familyMembers[index];
    setState(() => familyMembers.removeAt(index)); // 先移除UI

    try {
      await ApiClient().delete('/api/family/members/${member['id']}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已删除 ${member['name']}")));
    } catch (e) {
      if (mounted) {
        setState(() => familyMembers.insert(index, member)); // 失败则恢复
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败，请重试")));
      }
    }
  }

  void _showMemberDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("添加家人", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "称呼（如：儿子）")),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: "电话号码"), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || phoneController.text.isEmpty) return;
              try {
                await ApiClient().post('/api/family/members', data: {
                  "name": nameController.text,
                  "phone": phoneController.text,
                  "avatar": ""
                });
                if(mounted) Navigator.pop(context);
                fetchMembers(); // 插入成功后立刻刷新列表
              } catch (e) {
                if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("添加失败: $e")));
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: RefreshIndicator(
        onRefresh: fetchMembers,
        child: isLoading && familyMembers.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 150),
          itemCount: familyMembers.length + 2,
          itemBuilder: (context, index) {
            if (index < familyMembers.length) {
              return Dismissible(
                key: Key(familyMembers[index]['id'].toString()),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("确定要删除吗？"),
                      content: Text("删除后将无法快速联系 ${familyMembers[index]['name']}"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("删除", style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                },
                onDismissed: (direction) => _deleteMember(index),
                background: _buildDeleteBackground(),
                child: _buildFamilyCard(index, familyMembers[index]),
              );
            } else if (index == familyMembers.length) {
              return _buildHintBox();
            } else {
              return Padding(padding: const EdgeInsets.only(top: 30), child: _buildAddButton());
            }
          },
        ),
      ),
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(30)),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.delete_forever, color: Colors.white, size: 36), Text("删除", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
    );
  }

  // 💡 已清理：移除了底部的拨打电话 Row
  Widget _buildFamilyCard(int index, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 10))]
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 40, backgroundColor: Color(0xFFE2E8F0), child: Icon(Icons.person, size: 50, color: Colors.orange)),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['name'] ?? "", style: const TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 4),
              Text(data['phone'] ?? "", style: const TextStyle(fontSize: AppFonts.bodyLarge, color: Color(0xFF64748B))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHintBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20)),
      child: const Row(children: [Text("💡", style: TextStyle(fontSize: 24)), SizedBox(width: 10), Expanded(child: Text("提示：向左滑动卡片可以删除联系人", style: TextStyle(fontSize: AppFonts.bodySmall, color: Color(0xFF1E40AF))))]),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: () => _showMemberDialog(),
      child: Column(
        children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2)), child: const Icon(Icons.add_rounded, color: Colors.blueAccent, size: 50)),
          const SizedBox(height: 10),
          const Text("添加新联系人", style: TextStyle(fontSize: AppFonts.bodyMedium, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}