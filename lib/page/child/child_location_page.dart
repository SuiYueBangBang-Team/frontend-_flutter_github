import 'package:flutter/material.dart';
import 'dart:async';
import '../../utils/api_client.dart'; // 💡 引入真实请求客户端

// 💡 引入基础地图库与工具
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart'; //
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart'; //

// 💡 使用这个标准的包引入，它完美兼容最新版的所有接口
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart'; // 用于申请定位权限


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
  // 💡 新增：百度地图控制器
  BMFMapController? myMapController;

  // 初始化定位插件类
  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin(); //
  bool _isFirstLocation = true; // 用于首次定位时移动地图视角

// 请求定位权限
  Future<void> _requestPermissionAndLocate() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _initLocation();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("需要定位权限才能显示您的当前位置")));
      }
    }
  }

  // 初始化并开启真实定位
  void _initLocation() async {
    try {
      debugPrint("📌 定位流程 1: 正在设置隐私政策...");
      _locationPlugin.setAgreePrivacy(true);

      debugPrint("📌 定位流程 2: 正在初始化参数...");
      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: true,
        openGps: true,
        coordType: BMFLocationCoordType.bd09ll,
        scanspan: 2000,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});

      debugPrint("📌 定位流程 3: 正在注册定位回调...");
      _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
        // 💡 无论成功失败，只要百度给回应了，就会打印这句话
        debugPrint("📍 百度定位回调到达! 错误码=${result.errorCode}, 经度=${result.longitude}, 纬度=${result.latitude}");

        if (!mounted) return;
        if (result.latitude != null && result.longitude != null && result.latitude! > 1.0) {
          setState(() {
            myLocation['lat'] = result.latitude!;
            myLocation['lng'] = result.longitude!;
          });
          _updateMapOverlays();
          if (_isFirstLocation && myMapController != null && !_isTrackingLocked) {
            myMapController?.setCenterCoordinate(
                BMFCoordinate(result.latitude!, result.longitude!), true);
            _isFirstLocation = false;
          }
        }
      });

      debugPrint("📌 定位流程 4: 发送启动定位指令...");
      await _locationPlugin.startLocation();
      debugPrint("📌 定位流程 5: 启动指令发送成功，等待百度回调...");

    } catch (e) {
      debugPrint("❌ 定位流程发生异常: $e");
    }
  }

  Map<String, double> myLocation = {
    "lat": 23.112724,
    "lng": 113.259987,
  };

  Timer? _realtimeTimer;

  @override
  void initState() {
    super.initState();
    _fetchLocationData();
    _requestPermissionAndLocate(); // 启动真实定位
    _startRealtimeTracking();
  }

  @override
  void dispose() {
    _realtimeTimer?.cancel();
    // 停止定位，防止内存泄漏
    _locationPlugin.stopLocation(); // [cite: 20]
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
            // ✅ 替换为直接读取后端真实数据
            "lat": e['lat'] ?? 30.5450, // 赋一个默认值兜底
            "lng": e['lng'] ?? 114.3100,

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


  void _startRealtimeTracking() {
    // 建议把频率降到 5-10 秒一次，避免后端接口压力过大
    _realtimeTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;

      // 1. 每隔一段时间，去后端拉取一次长辈的最新位置
      _fetchLocationData();

      // 2. 视角追踪逻辑保留,跟踪逻辑：若开启了导航居中且存在选中设备，则转移地图视角
      if (_isTrackingLocked && selectedDeviceId != null) {
        var targetDevice = boundDevices.firstWhere((d) => d['id'] == selectedDeviceId, orElse: () => {});
        if (targetDevice.isNotEmpty && targetDevice['isOnline'] == true) {
          myMapController?.setCenterCoordinate(
              BMFCoordinate(targetDevice['lat'], targetDevice['lng']), true);
        }
      }
    });
  }


// 💡 核心新增：绘制真实地图覆盖物
  void _updateMapOverlays() {
    if (myMapController == null) return;
    myMapController?.cleanAllMarkers(); // 清除旧图标

    // 1. 绘制“我”的位置
    BMFMarker myMarker = BMFMarker(
      position: BMFCoordinate(myLocation['lat']!, myLocation['lng']!),
      title: "我的位置",
      // ⚠️ 必须提供本地资源图作 Marker
      icon: "assets/icons/my_location.png",
    );
    myMapController?.addMarker(myMarker);

    // 2. 绘制长辈设备的位置
    for (var device in boundDevices) {
      if (device['isOnline'] == true) {
        bool isSelected = selectedDeviceId == device['id'];
        BMFMarker deviceMarker = BMFMarker(
          position: BMFCoordinate(device['lat']!, device['lng']!),
          title: device['name'],
          icon: isSelected ? "assets/icons/device_selected.png" : "assets/icons/device_normal.png",
        );
        myMapController?.addMarker(deviceMarker);
      }
    }
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

// 🗺️ 替换为真实的地图图层 Widget
  Widget _buildMapLayer() {
    // 💡 构造包含了中心点坐标、缩放级别以及预留边界等状态参数的地图选项
    BMFMapOptions mapOptions = BMFMapOptions(
        center: BMFCoordinate(myLocation['lat']!, myLocation['lng']!),
        zoomLevel: 15,
        mapPadding: BMFEdgeInsets(left: 0, top: 0, right: 0, bottom: 0)); //

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFF1F0EA),
      // 💡 BMFMapWidget 替代旧版 FakePainter
      child: BMFMapWidget(
        onBMFMapCreated: (controller) {
          myMapController = controller;
          _updateMapOverlays(); // 地图初始化完毕，立刻执行一次标注绘制
        },
        mapOptions: mapOptions, //
      ),
    );
  }
}