import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import '../../utils/api_client.dart'; // 💡 引入真实请求客户端

class ChildLocationPage extends StatefulWidget {
  const ChildLocationPage({super.key});

  @override
  State<ChildLocationPage> createState() => _ChildLocationPageState();
}

class _ChildLocationPageState extends State<ChildLocationPage> {
  List<Map<String, dynamic>> boundDevices = [];
  bool isLoading = true;
  bool _isTrackingLocked = false;
  String? selectedDeviceId;

  Map<String, double> myLocation = {
    "lat": 30.5450,
    "lng": 114.3100,
  };

  Timer? _realtimeTimer;

  @override
  void initState() {
    super.initState();
    _fetchLocationData(); // 💡 页面初始化时拉取真实设备列表
    _startRealtimeTracking();
  }

  @override
  void dispose() {
    _realtimeTimer?.cancel();
    super.dispose();
  }

  // 💡 真实接口：获取已绑定的长辈设备列表
  Future<void> _fetchLocationData() async {
    setState(() => isLoading = true);

    try {
      // 请求后端 /api/family/devices
      var response = await ApiClient().get('/api/family/devices');

      if (response != null) {
        List<dynamic> list = response is List ? response : (response['data'] ?? []);

        setState(() {
          boundDevices = list.map((e) => {
            "id": e['id'].toString(),
            "name": e['name'] ?? "未知设备",
            "status": e['status'] ?? "离线",
            // ⚠️ 注意：目前后端 DeviceVO 尚未提供真实的经纬度，这里先随机生成偏移坐标，以免地图报错。
            // 未来后端增加了 lat/lng 后，直接替换为 e['lat'] 即可。
            "lat": 30.5450 + (Random().nextDouble() - 0.5) * 0.01,
            "lng": 114.3100 + (Random().nextDouble() - 0.5) * 0.01,
            "battery": e['batteryLevel'] ?? 0,
            "volume": e['volumeLevel'] ?? 0,
            "isOnline": e['isOnline'] ?? false,
          }).toList();

          if (boundDevices.isNotEmpty && selectedDeviceId == null) {
            selectedDeviceId = boundDevices.first['id'];
          }
        });
      }
    } catch (e) {
      debugPrint("拉取设备列表失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("加载设备失败，请检查网络")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 💡 模拟坐标跳动 (保留原有功能)
  void _startRealtimeTracking() {
    _realtimeTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      setState(() {
        myLocation['lat'] = myLocation['lat']! + 0.0001;
        myLocation['lng'] = myLocation['lng']! + 0.00005;

        for (var device in boundDevices) {
          // 仅模拟在线设备的轻微移动
          if (device['isOnline'] == true) {
            device['lat'] += (Random().nextDouble() - 0.5) * 0.0002;
            device['lng'] += (Random().nextDouble() - 0.5) * 0.0002;
          }
        }
      });
    });
  }

  // 💡 真实接口：绑定设备弹窗
  void _showBindDeviceDialog() {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    final TextEditingController aliasController = TextEditingController();

    // 使用 StatefulBuilder 让弹窗内部也能局部刷新状态 (如：按钮的 Loading)
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isSendingCode = false;
            bool isBinding = false;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("添加绑定长辈"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: "长辈手机号",
                        hintText: "请输入已注册的长辈账号",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: codeController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: "验证码",
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                              )
                          )
                      ),
                      const SizedBox(width: 10),
                      // 💡 发送验证码按钮
                      SizedBox(
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: isSendingCode ? null : () async {
                            if (phoneController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请先输入手机号")));
                              return;
                            }
                            setStateDialog(() => isSendingCode = true);
                            try {
                              // 调用发送验证码接口 (使用 Query 参数)
                              await ApiClient().post('/api/family/bind/send-sms?phone_number=${phoneController.text}');
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("验证码发送成功，请注意查收")));
                            } catch (e) {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("发送失败: $e")));
                            } finally {
                              setStateDialog(() => isSendingCode = false);
                            }
                          },
                          child: isSendingCode
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text("获取"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: aliasController,
                    decoration: InputDecoration(
                        labelText: "长辈称呼 (如: 爸爸)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
                // 💡 确认绑定按钮
                ElevatedButton(
                  onPressed: isBinding ? null : () async {
                    if (phoneController.text.isEmpty || codeController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("手机号和验证码不能为空")));
                      return;
                    }
                    setStateDialog(() => isBinding = true);
                    try {
                      // 调用确认绑定接口
                      await ApiClient().post('/api/family/bind/confirm', data: {
                        "phoneNumber": phoneController.text,
                        "code": codeController.text,
                        "alias": aliasController.text.isEmpty ? "长辈" : aliasController.text
                      });

                      if (mounted) {
                        Navigator.pop(context); // 绑定成功，关闭弹窗
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("绑定成功！")));
                        _fetchLocationData(); // 立刻刷新底部面板的设备列表
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("绑定失败: $e")));
                    } finally {
                      setStateDialog(() => isBinding = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: isBinding
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("确认绑定", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. 底层：全屏地图区域
          _buildMapLayer(),

          // 2. 右侧：地图控制悬浮按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: Column(
              children: [
                _buildMapControlButton(
                  icon: Icons.layers_rounded,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("切换地图图层"))),
                ),
                const SizedBox(height: 12),
                _buildMapControlButton(
                  icon: _isTrackingLocked ? Icons.navigation_rounded : Icons.near_me_outlined,
                  color: _isTrackingLocked ? Colors.blueAccent : Colors.black87,
                  onTap: () {
                    setState(() {
                      _isTrackingLocked = !_isTrackingLocked;
                    });
                  },
                ),
              ],
            ),
          ),

          // 3. 上层：可拖拽的设备列表底部面板
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: const [0.15, 0.45, 0.85],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // 拖拽指示条
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 10),
                        width: 40, height: 5,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2.5)),
                      ),
                    ),

                    // 标题与添加按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("家庭设备", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          IconButton(
                            onPressed: _showBindDeviceDialog, // 💡 唤起真实绑定弹窗
                            icon: const Icon(Icons.add, size: 28, color: Colors.blueAccent),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    if (isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
                    else if (boundDevices.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("尚未绑定长辈设备", style: TextStyle(color: Colors.grey)))),

                    // 渲染设备列表
                    ...boundDevices.map((device) => _buildDeviceItem(device)),

                    const SizedBox(height: 100),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 渲染设备列表子项
  Widget _buildDeviceItem(Map<String, dynamic> device) {
    bool isOnline = device['isOnline'] ?? false;
    bool isSelected = selectedDeviceId == device['id'];

    return InkWell(
      onTap: () {
        if (!isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设备已离线，无法查看实时位置")));
          return;
        }
        setState(() => selectedDeviceId = device['id']);
      },
      child: Container(
        color: isSelected ? Colors.blue.withOpacity(0.05) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: isOnline ? Colors.blue[50] : Colors.grey[100], shape: BoxShape.circle),
              child: Icon(
                Icons.phone_iphone_rounded,
                color: isOnline ? (isSelected ? Colors.blueAccent : Colors.black87) : Colors.grey[400],
                size: 28,
              ),
            ),
            const SizedBox(width: 15),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device['name'], style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isOnline ? Colors.black87 : Colors.grey[600])),
                  const SizedBox(height: 4),
                  Text(device['status'], style: TextStyle(fontSize: 13, color: isOnline ? Colors.grey[600] : Colors.redAccent)),
                ],
              ),
            ),

            if (isOnline) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text("${device['battery']}%", style: TextStyle(fontSize: 12, color: device['battery'] < 20 ? Colors.red : Colors.green)),
                      const SizedBox(width: 4),
                      Icon(device['battery'] < 20 ? Icons.battery_alert_rounded : Icons.battery_full_rounded, size: 16, color: device['battery'] < 20 ? Colors.red : Colors.green),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(device['volume'] == 0 ? "静音" : "${device['volume']}%", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(width: 4),
                      Icon(device['volume'] == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 16, color: Colors.grey[600]),
                    ],
                  )
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  // 悬浮按钮组件
  Widget _buildMapControlButton({required IconData icon, required VoidCallback onTap, Color color = Colors.black87}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }

  // 🗺️ 地图图层 (仅供展示)
  Widget _buildMapLayer() {
    return Container(
      width: double.infinity, height: double.infinity,
      color: const Color(0xFFF1F0EA),
      child: Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: _FakeMapPainter()),

          AnimatedPositioned(
            duration: const Duration(seconds: 2),
            curve: Curves.linear,
            top: 400 - (myLocation['lat']! - 30.54) * 10000,
            left: 150 + (myLocation['lng']! - 114.30) * 10000,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)]),
                  child: const Text("我的位置", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(height: 5),
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.blueAccent, blurRadius: 10)]),
                ),
              ],
            ),
          ),

          ...boundDevices.where((d) => d['isOnline']).map((device) {
            bool isSelected = selectedDeviceId == device['id'];
            double lat = (device['lat'] ?? 0.0).toDouble();
            double lng = (device['lng'] ?? 0.0).toDouble();

            double top = 400 - (lat - 30.54) * 10000;
            double left = 150 + (lng - 114.30) * 10000;

            return AnimatedPositioned(
              duration: const Duration(seconds: 2),
              curve: Curves.linear,
              top: top, left: left,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 10, backgroundColor: isSelected ? Colors.white : Colors.green, child: Icon(Icons.person, size: 14, color: isSelected ? Colors.green : Colors.white)),
                        const SizedBox(width: 6),
                        Text(device['name'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Icon(Icons.location_on, color: isSelected ? Colors.green : Colors.grey, size: isSelected ? 48 : 40),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 8..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(0, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.5, size.width, size.height * 0.3);
    path.moveTo(size.width * 0.3, 0);
    path.lineTo(size.width * 0.4, size.height);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}