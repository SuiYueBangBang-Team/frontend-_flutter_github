import 'package:flutter/material.dart';
import 'package:phone_java/app_fonts.dart';       // 确保相对路径正确
import 'package:phone_java/utils/api_client.dart'; // 引入请求客户端

class ChildHealthPage extends StatefulWidget {
  const ChildHealthPage({super.key});

  @override
  State<ChildHealthPage> createState() => _ChildHealthPageState();
}

class _ChildHealthPageState extends State<ChildHealthPage> {
  // 💡 已彻底移除 _isDebugMode 假数据拦截，强制走真实后端

  List<Map<String, dynamic>> parentMeds = []; // 长辈的用药数据
  List<Map<String, dynamic>> myReminders = []; // 子女自己的提醒数据
  bool isLoading = true;
  int remindCount = 0; // 今日已提醒次数

  @override
  void initState() {
    super.initState();
    _fetchHealthData();
  }

  // 💡 获取真实后端数据
  Future<void> _fetchHealthData() async {
    setState(() => isLoading = true);

    // ==========================================
    // 🌐 真实后端对接模式 (独立 try-catch 防止单个接口失败导致全盘崩溃)
    // ==========================================

    // 1. 获取长辈用药列表
    try {
      var medsData = await ApiClient().get('/api/family/medications/today');
      if (medsData != null) {
        parentMeds = List<Map<String, dynamic>>.from(medsData);
      }
    } catch (e) {
      debugPrint("拉取用药数据失败: $e");
    }

    // 2. 获取一键提醒次数
    try {
      var countData = await ApiClient().get('/api/family/medications/remind_count');
      if (countData != null) {
        remindCount = countData['count'] ?? 0;
      }
    } catch (e) {
      debugPrint("拉取提醒次数失败: $e");
    }

    // 3. 获取子女专属提醒 (如果后端还没有这个接口，报错也不会影响前面用药的显示)
    try {
      var remsData = await ApiClient().get('/api/child/reminders');
      if (remsData != null) {
        myReminders = List<Map<String, dynamic>>.from(remsData);
      }
    } catch (e) {
      debugPrint("拉取专属提醒失败 (可能后端暂未实现该接口): $e");
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  // 💡 一键提醒 (给长辈发推送)
  Future<void> _sendOneClickReminder() async {
    // 检查是否有未吃的药
    bool hasUntaken = parentMeds.any((med) => !(med['isTaken'] ?? false));
    if (!hasUntaken) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("长辈今日药物已全部吃完啦，无需提醒！")));
      return;
    }

    // 🌐 调用真实后端接口
    try {
      await ApiClient().post('/api/family/medications/remind_un_taken');
      setState(() => remindCount++);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已成功发送用药提醒给长辈！")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("提醒发送失败: $e")));
    }
  }

  // 💡 子女帮长辈删除用药
  Future<void> _deleteParentMed(int index) async {
    var med = parentMeds[index];
    setState(() => parentMeds.removeAt(index));

    try {
      await ApiClient().delete('/api/family/medications/${med['id']}');
    } catch (e) {
      // 失败则回滚 UI
      setState(() => parentMeds.insert(index, med));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败，请检查网络")));
    }
  }

  // 💡 子女删除自己的提醒
  Future<void> _deleteMyReminder(int index) async {
    var rem = myReminders[index];
    setState(() => myReminders.removeAt(index));

    try {
      await ApiClient().delete('/api/child/reminders/${rem['id']}');
    } catch (e) {
      setState(() => myReminders.insert(index, rem));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败")));
    }
  }

  // 💡 子女帮长辈添加用药
  void _showAddParentMedDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController doseController = TextEditingController();
    TextEditingController timeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("帮长辈添加用药", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "药品名称 (如：降压药)")),
            const SizedBox(height: 10),
            TextField(controller: doseController, decoration: const InputDecoration(labelText: "用量 (如：1粒)")),
            const SizedBox(height: 10),
            TextField(
              controller: timeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "提醒时间", hintText: "点击选择时间",
                suffixIcon: Icon(Icons.access_time_rounded, color: Colors.blueAccent),
              ),
              onTap: () async {
                TimeOfDay? picked = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now(),
                  builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
                );
                if (picked != null) {
                  timeController.text = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || doseController.text.isEmpty || timeController.text.isEmpty) return;

              try {
                // 传给后端的 JSON 字段需与 MedicationRecord 对应 (timeStr)
                await ApiClient().post('/api/family/medications', data: {
                  "name": nameController.text,
                  "dose": doseController.text,
                  "timeStr": timeController.text,
                });
                if(mounted) Navigator.pop(context);
                _fetchHealthData(); // 重新拉取刷新列表
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

  // 💡 添加子女专属提醒
  void _showAddMyReminderDialog() {
    TextEditingController contentController = TextEditingController();
    TextEditingController timeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("添加我的提醒", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: contentController, decoration: const InputDecoration(labelText: "提醒内容 (如：带父母体检)")),
            const SizedBox(height: 10),
            TextField(
              controller: timeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "提醒时间", hintText: "点击选择时间",
                suffixIcon: Icon(Icons.access_time_rounded, color: Colors.blueAccent),
              ),
              onTap: () async {
                TimeOfDay? picked = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now(),
                  builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
                );
                if (picked != null) {
                  timeController.text = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              if (contentController.text.isEmpty || timeController.text.isEmpty) return;

              try {
                await ApiClient().post('/api/child/reminders', data: {
                  "content": contentController.text, "timeStr": timeController.text,
                });
                if(mounted) Navigator.pop(context);
                _fetchHealthData();
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
        onRefresh: _fetchHealthData,
        child: isLoading && parentMeds.isEmpty && myReminders.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 150),
          children: [
            // ==========================================
            // 1. 长辈今日用药 (数据互通)
            // ==========================================
            const SizedBox(height: 10),
            _buildSectionHeader("长辈今日用药", Icons.medical_services_rounded, Colors.green, _showAddParentMedDialog),
            if (parentMeds.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("今日暂无用药安排", style: TextStyle(color: Colors.grey)))),
            ...parentMeds.asMap().entries.map((entry) {
              int index = entry.key;
              return Dismissible(
                key: Key('med_${entry.value['id']}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) => _showConfirmDialog("确定删除长辈的该用药记录吗？"),
                onDismissed: (_) => _deleteParentMed(index),
                background: _buildDeleteBackground(),
                child: _buildParentMedItem(entry.value),
              );
            }),

            // ==========================================
            // 2. 一键提醒按钮区域 (只要有未吃的药就会显示)
            // ==========================================
            if (parentMeds.isNotEmpty) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _sendOneClickReminder,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Colors.orangeAccent, Colors.deepOrangeAccent]),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.campaign_rounded, color: Colors.white, size: 32),
                      SizedBox(width: 10),
                      Text("一键提醒长辈吃药", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  "今日已提醒 $remindCount 次",
                  style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            const SizedBox(height: 40),

            // ==========================================
            // 3. 子女专属提醒事项 (隔离数据)
            // ==========================================
            _buildSectionHeader("我的提醒事项", Icons.event_note_rounded, Colors.blueAccent, _showAddMyReminderDialog),
            if (myReminders.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("暂无提醒事项", style: TextStyle(color: Colors.grey)))),
            ...myReminders.asMap().entries.map((entry) {
              int index = entry.key;
              return Dismissible(
                key: Key('rem_${entry.value['id']}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) => _showConfirmDialog("确定删除该提醒吗？"),
                onDismissed: (_) => _deleteMyReminder(index),
                background: _buildDeleteBackground(),
                child: _buildMyReminderItem(entry.value),
              );
            }),
          ],
        ),
      ),
    );
  }

  // --- UI 组件封装 ---
  Widget _buildParentMedItem(Map<String, dynamic> data) {
    bool isTaken = data['isTaken'] ?? false;

    // 💡 修复：后端返回的字段叫 timeStr，如果为空则兜底显示未知时间
    String timeDisplay = data['timeStr'] ?? data['time'] ?? '未知时间';

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isTaken ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: isTaken ? Colors.green.withOpacity(0.5) : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(timeDisplay, style: const TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("${data['name']} · ${data['dose']}", style: const TextStyle(fontSize: AppFonts.bodyLarge, color: Colors.black54)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
            decoration: BoxDecoration(color: isTaken ? Colors.green : Colors.grey.shade300, borderRadius: BorderRadius.circular(15)),
            child: Text(isTaken ? "长辈已吃" : "长辈未吃", style: TextStyle(color: isTaken ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: AppFonts.bodyLarge)),
          ),
        ],
      ),
    );
  }

  Widget _buildMyReminderItem(Map<String, dynamic> data) {
    String timeDisplay = data['timeStr'] ?? data['time'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(25)),
      child: Row(children: [
        const Icon(Icons.alarm_rounded, color: Colors.blueAccent, size: 32),
        const SizedBox(width: 15),
        Expanded(child: Text("$timeDisplay ${data['content']}", style: const TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, VoidCallback onAdd) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(onTap: onAdd, child: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 32)),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("删除", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 25),
      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(25)),
      child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 30),
    );
  }
}