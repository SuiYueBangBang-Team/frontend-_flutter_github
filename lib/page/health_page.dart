import 'package:flutter/material.dart';
import 'dart:async'; // 💡 引入定时器库
import '../app_fonts.dart';
import '../utils/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  List<Map<String, dynamic>> todayMeds = [];
  List<Map<String, dynamic>> reminders = [];
  bool isLoading = true;

  // 💡 轮询提醒核心变量
  Timer? _pollingTimer;
  int _lastRemindCount = -1; // -1 表示尚未初始化

  @override
  void initState() {
    super.initState();
    _fetchHealthData();

    // 💡 开启定时器，每 5 秒去后端查一次是否有新提醒
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkReminders();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel(); // 💡 退出页面时务必销毁定时器，防止内存泄漏
    super.dispose();
  }

  // 2. 💡 替换原来的 _checkReminders 方法
  Future<void> _checkReminders() async {
    try {
      var response = await ApiClient().get('/api/family/medications/remind_count');
      if (response == null) return;

      int currentCount = 0;
      if (response['count'] != null) {
        currentCount = response['count'];
      } else if (response['data'] != null && response['data']['count'] != null) {
        currentCount = response['data']['count'];
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      int savedCount = prefs.getInt('elder_remind_count') ?? -1;

      // print("【长辈端轮询】当前后端次数: $currentCount，本地持久化旧次数: $savedCount");

      if (savedCount == -1) {
        // 1️⃣ 第一次打开APP / 退出重登后缓存被清空
        await prefs.setInt('elder_remind_count', currentCount);

        // 💡 核心修复：如果退出重登后发现后端有未读的提醒(大于0)，直接弹窗！不再吞掉！
        if (currentCount > 0) {
          // print("【长辈端轮询】🚨 刚登录发现未读的提醒！立刻触发弹窗！");
          _showElderWarningDialog();
        } else {
          // print("【长辈端轮询】初始化基准完毕，当前无提醒。");
        }

      } else if (currentCount > savedCount) {
        // 2️⃣ 正常停留页面时：次数增加，说明子女刚按了按钮
        await prefs.setInt('elder_remind_count', currentCount);
        // print("【长辈端轮询】🚨 发现新提醒！立刻触发弹窗！");
        _showElderWarningDialog();

      } else if (currentCount < savedCount) {
        // 3️⃣ 💡 隐藏Bug修复：如果到了第二天后端Redis清零了，本地必须同步归零！
        // 否则 1 < 15 永远不成立，第二天再也收不到提醒了！
        await prefs.setInt('elder_remind_count', currentCount);
        // print("【长辈端轮询】🔄 新的一天，后端次数已重置，本地同步归零！");
      }

    } catch (e) {
      // debugPrint("【长辈端轮询】报错拉取失败: $e");
    }
  }

  // 💡 专属长辈的强提醒弹窗
  void _showElderWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 强制用户必须点击按钮才能关掉弹窗
      builder: (context) => AlertDialog(
        backgroundColor: Colors.redAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 36),
            SizedBox(width: 10),
            Text("吃药提醒！", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "您的子女刚刚发来提醒，请立刻检查今日的药物是否已经服用！",
          style: TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              _fetchHealthData(); // 关掉弹窗后顺便刷新一下列表数据
            },
            child: const Text("我知道了，马上吃", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 💡 获取健康数据
  Future<void> _fetchHealthData() async {
    setState(() => isLoading = true);
    try {
      // 💡 修复：路径修改为与后端一致的 /api/family/medications/today
      var medsData = await ApiClient().get('/api/family/medications/today');
      var remsData = await ApiClient().get('/api/health/reminders'); // 假设提醒的接口没变
      setState(() {
        todayMeds = List<Map<String, dynamic>>.from(medsData ?? []);
        reminders = List<Map<String, dynamic>>.from(remsData ?? []);
      });
    } catch (e) {
      print("拉取健康数据失败: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 💡 切换吃药状态
  Future<void> _toggleMedStatus(int index) async {
    var med = todayMeds[index];
    bool currentStatus = med['isTaken'] ?? false;
    int id = med['id'];

    setState(() => todayMeds[index]['isTaken'] = !currentStatus);

    try {
      // 💡 注意：如果你后端没有写这个 put 接口，这里请求会报错但UI会自己恢复
      await ApiClient().put('/api/health/medications/$id/status', data: {
        "isTaken": !currentStatus
      });
    } catch (e) {
      setState(() => todayMeds[index]['isTaken'] = currentStatus);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("状态更新失败，请稍后再试")));
    }
  }

  // 💡 删除用药
  Future<void> _deleteMed(int index) async {
    var med = todayMeds[index];
    setState(() => todayMeds.removeAt(index));
    try {
      // 💡 修复：路径修改为与后端一致的 /api/family/medications/
      await ApiClient().delete('/api/family/medications/${med['id']}');
    } catch (e) {
      setState(() => todayMeds.insert(index, med));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败")));
    }
  }

  // 💡 删除提醒
  Future<void> _deleteReminder(int index) async {
    var rem = reminders[index];
    setState(() => reminders.removeAt(index));
    try {
      await ApiClient().delete('/api/health/reminders/${rem['id']}');
    } catch (e) {
      setState(() => reminders.insert(index, rem));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("删除失败")));
    }
  }

  // 💡 添加用药记录弹窗
  void _showAddMedDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController doseController = TextEditingController();
    TextEditingController timeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("添加用药", style: TextStyle(fontWeight: FontWeight.bold)),
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
                labelText: "提醒时间",
                hintText: "点击选择时间",
                suffixIcon: Icon(Icons.access_time_rounded, color: Colors.blueAccent),
              ),
              onTap: () async {
                TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    );
                  },
                );

                if (picked != null) {
                  String hh = picked.hour.toString().padLeft(2, '0');
                  String mm = picked.minute.toString().padLeft(2, '0');
                  timeController.text = "$hh:$mm";
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || doseController.text.isEmpty || timeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请填写完整信息")));
                return;
              }
              try {
                // 💡 修复：路径修改为与后端一致的 /api/family/medications
                await ApiClient().post('/api/family/medications', data: {
                  "name": nameController.text,
                  "dose": doseController.text,
                  "timeStr": timeController.text,
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

  // 💡 添加提醒事项弹窗
  void _showAddReminderDialog() {
    TextEditingController contentController = TextEditingController();
    TextEditingController timeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("添加提醒事项", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: contentController, decoration: const InputDecoration(labelText: "提醒内容 (如：测血压)")),
            const SizedBox(height: 10),
            TextField(
              controller: timeController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "提醒时间",
                hintText: "点击选择时间",
                suffixIcon: Icon(Icons.access_time_rounded, color: Colors.blueAccent),
              ),
              onTap: () async {
                TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    );
                  },
                );

                if (picked != null) {
                  String hh = picked.hour.toString().padLeft(2, '0');
                  String mm = picked.minute.toString().padLeft(2, '0');
                  timeController.text = "$hh:$mm";
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              if (contentController.text.isEmpty || timeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请填写完整信息")));
                return;
              }
              try {
                await ApiClient().post('/api/health/reminders', data: {
                  "content": contentController.text,
                  "timeStr": timeController.text,
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
        child: isLoading && todayMeds.isEmpty && reminders.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 150),
          children: [
            const SizedBox(height: 10),
            _buildSectionHeader("今日用药", Icons.medical_services_rounded, Colors.green, _showAddMedDialog),
            if (todayMeds.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("暂无用药记录"))),
            ...todayMeds.asMap().entries.map((entry) {
              int index = entry.key;
              return Dismissible(
                key: Key('med_${entry.value['id']}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) => _showConfirmDialog("确定删除该用药记录吗？"),
                onDismissed: (_) => _deleteMed(index),
                background: _buildDeleteBackground(),
                child: _buildMedItem(index, entry.value),
              );
            }),

            const SizedBox(height: 40),
            _buildSectionHeader("提醒事项", Icons.notifications_active_rounded, Colors.orange, _showAddReminderDialog),
            if (reminders.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("暂无提醒事项"))),
            ...reminders.asMap().entries.map((entry) {
              int index = entry.key;
              return Dismissible(
                key: Key('rem_${entry.value['id']}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) => _showConfirmDialog("确定删除该提醒吗？"),
                onDismissed: (_) => _deleteReminder(index),
                background: _buildDeleteBackground(),
                child: _buildReminderItem(entry.value),
              );
            }),

            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(child: Text("左滑卡片可以删除记录", style: TextStyle(color: Colors.grey.withOpacity(0.6), fontSize: AppFonts.caption))),
            ),
          ],
        ),
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
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 30), Text("删除", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, VoidCallback onAdd) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: AppFonts.titleLarge, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildMedItem(int index, Map<String, dynamic> data) {
    bool isTaken = data['isTaken'] ?? false;
    // 💡 修复：后端返回的是 timeStr，防止为 null
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
          GestureDetector(
            onTap: () => _toggleMedStatus(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
              decoration: BoxDecoration(color: isTaken ? Colors.green : Colors.orange, borderRadius: BorderRadius.circular(15)),
              child: Text(isTaken ? "已吃" : "待提醒", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppFonts.bodyLarge)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderItem(Map<String, dynamic> data) {
    String timeDisplay = data['timeStr'] ?? data['time'] ?? '未知时间';
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(25)),
      child: Row(children: [
        const Icon(Icons.notifications_active, color: Colors.orangeAccent, size: 32),
        const SizedBox(width: 15),
        Expanded(child: Text("$timeDisplay ${data['content']}", style: const TextStyle(fontSize: AppFonts.bodyLarge, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}