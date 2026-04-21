import 'package:flutter/material.dart';
import 'dart:async';
import '../../utils/api_client.dart'; //  引入真实请求客户端

//  引入基础地图库与工具
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart'; //
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart'; //

//  使用这个标准的包引入，它完美兼容最新版的所有接口
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart'; // 用于申请定位权限

import 'dart:math';
import '../../utils/location_service.dart'; // 新增引入

class ChildLocationPage extends StatefulWidget {
  const ChildLocationPage({super.key});

  @override
  State<ChildLocationPage> createState() => _ChildLocationPageState();
}

class _ChildLocationPageState extends State<ChildLocationPage> {
  List<Map<String, dynamic>> boundDevices = [];
  bool isLoading = true;
  String? selectedDeviceId;
  //  新增：百度地图控制器
  BMFMapController? myMapController;

  bool _isFirstLocation = true; // 用于首次定位时移动地图视角


  Map<String, double> myLocation = {
    "lat": 23.27491548663772,
    "lng": 112.68073532165043, //BD09(百度坐标系)，本校
  };

  Timer? _realtimeTimer;


  // 新增：专门接收 LocationService 传来的位置更新
  void _onLocationUpdate(double lat, double lng) {
    if (!mounted) return;
    setState(() {
      myLocation['lat'] = lat;
      myLocation['lng'] = lng;
    });
    _updateMapOverlays();

    if (_isFirstLocation && myMapController != null) {
      _moveToVisibleCenter(lat, lng);
      _isFirstLocation = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchLocationData();

    // 改变这里：使用提取出来的服务
    LocationService().addListener(_onLocationUpdate); // 注册监听
    LocationService().requestPermissionAndLocate().then((hasPermission) {
      if (!hasPermission && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("需要定位权限才能显示您的当前位置")));
      }
    });

    _startRealtimeTracking();
  }

  @override
  void dispose() {
    _realtimeTimer?.cancel();
    // 改变这里：页面销毁时只需移除当前页面的监听，不再强制 stopLocation 杀死插件
    // 因为其他页面（如发帖页）可能还在使用定位
    LocationService().removeListener(_onLocationUpdate);
    super.dispose();
  }


  //  真实接口：获取已绑定的长辈设备列表
  //  isSilent 参数，用于控制是否显示转圈加载动画
  Future<void> _fetchLocationData({bool isSilent = false}) async {
// 💡只有在列表完全为空（首次进页面）时，才允许显示全屏的加载圈
    if (boundDevices.isEmpty && !isSilent) {
      setState(() => isLoading = true);
    }
    try {
      var response = await ApiClient().get('/api/location/all');

      if (response != null) {
        List<dynamic> list = response is List ? response : (response['data'] ?? []);

        setState(() {
          boundDevices = list.map((e) => {
            "id": e['id'].toString(),
            "name": e['name'] ?? "未知设备",
            // 💡 动态显示文字状态
            "status": (e['isOnline'] == true) ? "在线" : "离线",
            "lat": e['lat'] ?? 30.5450,
            "lng": e['lng'] ?? 114.3100,
            "battery": e['batteryLevel'] ?? 0,
            "volume": e['volumeLevel'] ?? 0,
            "isOnline": e['isOnline'] ?? false,
            "memberId": e['memberId']?.toString() ?? '',
          }).toList();

          if (boundDevices.isNotEmpty && selectedDeviceId == null) {
            selectedDeviceId = boundDevices.first['id'];
          }
        });
      }
    } catch (e) {
      // debugPrint("拉取设备列表失败: $e");
      if (mounted && !isSilent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("加载设备失败，请检查网络")));
      }
    } finally {
      // 最终必须把 isLoading 归位
      if (mounted) setState(() => isLoading = false);
    }
  }


  void _startRealtimeTracking() {
    // 建议把频率降到 5-10 秒一次，避免后端接口压力过大
    _realtimeTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;
      // 自动轮询时开启“静默刷新”，不再触发 isLoading，彻底解决页面跳动
      _fetchLocationData(isSilent: true);
    });
  }

  Future<void> _moveToVisibleCenter(double targetLat, double targetLng) async {
    if (myMapController == null) return;

    // 1. 获取像素密度
    double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    // 2. 获取屏幕尺寸（确保这是地图所在的尺寸）
    Size screenSize = MediaQuery.of(context).size;

    // 3. 计算目标点（逻辑像素）
    // X 为屏幕横向中心
    double targetX = screenSize.width / 2;
    // Y 为上方 55% 区域的中心点 = 总高度 * 0.55 / 2
    double targetY = screenSize.height * 0.375;

    // 4. 关键：将逻辑像素转换为物理像素
    BMFPoint targetScreenPt = BMFPoint(
      targetX * devicePixelRatio,
      targetY * devicePixelRatio,
    );

    BMFMapStatus mapStatus = BMFMapStatus(
      targetGeoPt: BMFCoordinate(targetLat, targetLng),
      targetScreenPt: targetScreenPt, // 此时坐标已匹配底层像素标准
    );

    await myMapController?.setNewMapStatus(
      mapStatus: mapStatus,
      animateDurationMs: 500,
    );
  }


//  核心新增：绘制真实地图覆盖物
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

  //  真实接口：绑定设备弹窗
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
                      //  发送验证码按钮
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
                //  确认绑定按钮
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
    // 动态计算精确的吸附比例，190 = 底部导航栏(124) + 标题栏高度(66)
    double screenHeight = MediaQuery.of(context).size.height;
    double minSize = 210.0 / screenHeight;
    double initialSize = 0.45 > minSize ? 0.45 : minSize + 0.1;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. 底层：全屏地图区域
          _buildMapLayer(),

          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "审图号: GS（2021）4841",
                style: TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),

          // 2. 右侧：地图控制悬浮按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: Column(
              children: [
                // 仅保留定位按钮，并修改为固定图标与直接跳转逻辑
                _buildMapControlButton(
                  icon: Icons.near_me, // 使用固定图标
                  color: Colors.black87, // 固定颜色，取消原有的蓝色激活状态
                  onTap: () {
                    // 新增：点击时先强制触发一次状态更新，并重新绘制地图上的标记点
                    setState(() {});
                    _updateMapOverlays();
                    // 点击立即回到“我的位置”
                    if (myMapController != null && myLocation['lat'] != null) {
                      _moveToVisibleCenter(myLocation['lat']!, myLocation['lng']!);
                    }
                  },
                ),
              ],
            ),
          ),

          // 3. 上层：可拖拽的设备列表底部面板
          DraggableScrollableSheet(
            initialChildSize: initialSize, //  使用计算出的初始高度
            minChildSize: minSize,         //  使用计算出的精确最小吸附高度
            maxChildSize: 0.85,
            snap: true,
            snapSizes: [minSize, initialSize, 0.85], //  动态的三段式吸附
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
                      // 💡 修复：把原来的单个加号按钮，改成 Row，包容刷新和添加两个按钮
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              // 手动点击刷新时，采用带转圈动画的非静默刷新，给用户明确的反馈
                              _fetchLocationData(isSilent: false);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设备状态已更新")));
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 28, color: Colors.blueAccent),
                          ),
                          IconButton(
                            onPressed: _showBindDeviceDialog, //  唤起真实绑定弹窗
                            icon: const Icon(Icons.add, size: 28, color: Colors.blueAccent),
                          ),
                        ],
                      ),
                        ],
                      ),
                    ),


                    const Divider(height: 1),

                    if (isLoading && boundDevices.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
                    else if (!isLoading && boundDevices.isEmpty)
                      const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("尚未绑定长辈设备", style: TextStyle(color: Colors.grey)))),
                    // 渲染设备列表
                    ...boundDevices.map((device) => _buildDeviceItem(device)),

                    // 增大底部的留白，防止最下面的设备被导航条遮挡
                    const SizedBox(height: 140),
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
      // setState 后立刻主动命令地图重绘所有大头针，实现图标秒切！
        _updateMapOverlays();

        //  新增：点击长辈设备后，地图立刻平滑跳转到该长辈的经纬度位置
        if (myMapController != null) {
          _moveToVisibleCenter(device['lat']!, device['lng']!);
        }
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(device['status'], style: TextStyle(fontSize: 12, color: isOnline ? Colors.grey[600] : Colors.redAccent)),
                      if (isOnline) ...[
                        const SizedBox(width: 12),
                        Icon(device['battery'] < 20 ? Icons.battery_alert_rounded : Icons.battery_full_rounded, size: 14, color: device['battery'] < 20 ? Colors.red : Colors.green),
                        const SizedBox(width: 2),
                        Text("${device['battery']}%", style: TextStyle(fontSize: 12, color: device['battery'] < 20 ? Colors.red : Colors.green)),
                        const SizedBox(width: 12),
                        Icon(device['volume'] == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 2),
                        Text(device['volume'] == 0 ? "静音" : "${device['volume']}%", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onPressed: () => _showDeviceOptions(device),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceOptions(Map<String, dynamic> device) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text("编辑称呼"),
              onTap: () { Navigator.pop(context); _showEditAliasDialog(device); },
            ),
            ListTile(
              leading: const Icon(Icons.link_off, color: Colors.red),
              title: const Text("删除设备", style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _deleteDevice(device); },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAliasDialog(Map<String, dynamic> device) {
    final controller = TextEditingController(text: device['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("编辑称呼"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              final alias = controller.text.trim();
              if (alias.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ApiClient().put('/api/family/members/${device['memberId']}', data: {'alias': alias});
                _fetchLocationData(isSilent: true);
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("修改失败: $e")));
              }
            },
            child: const Text("确认"),
          ),
        ],
      ),
    );
  }

  void _deleteDevice(Map<String, dynamic> device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要解除与「${device['name']}」的绑定吗？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiClient().delete('/api/family/members/${device['memberId']}');
                setState(() => boundDevices.removeWhere((d) => d['memberId'] == device['memberId']));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("删除失败: $e")));
              }
            },
            child: const Text("删除", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 悬浮按钮组件 (已增加点击水波纹动效)
  Widget _buildMapControlButton({required IconData icon, required VoidCallback onTap, Color color = Colors.black87}) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      //  使用 Material 和 InkWell 包裹 Icon，实现原生的点击水波纹动效
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );
  }

// 🗺️ 地图图层 Widget
  Widget _buildMapLayer() {
    // 仅用于初始化第一帧画面的视觉居中（因为初始化时 zoomLevel 锁死为 15）
    double offsetLat = myLocation['lat']! - 0.018;

    // 构造包含了中心点坐标、缩放级别等状态参数的地图选项
    BMFMapOptions mapOptions = BMFMapOptions(
      center: BMFCoordinate(offsetLat, myLocation['lng']!),
      zoomLevel: 15,
      rotateEnabled: false, // 禁用地图的双指旋转手势
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFF1F0EA),
      child: BMFMapWidget(
        onBMFMapCreated: (controller) {
          myMapController = controller;
        },
        mapOptions: mapOptions,
      ),
    );
  }

}