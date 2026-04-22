import 'package:flutter/material.dart';
import 'dart:async';
import '../../utils/api_client.dart';

import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';

import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dart:math';
import '../../utils/location_service.dart';

class ChildLocationPage extends StatefulWidget {
  const ChildLocationPage({super.key});

  @override
  State<ChildLocationPage> createState() => _ChildLocationPageState();
}

class _ChildLocationPageState extends State<ChildLocationPage> {
  List<Map<String, dynamic>> boundDevices = [];
  bool isLoading = true;

  // 💡 演示修改：用于记录每个设备的点击次数，实现“连续点击弹窗”
  final Map<String, int> _deviceClickCounts = {};

  final Set<String> _alertedDeviceIds = {};
  String? selectedDeviceId;
  BMFMapController? myMapController;
  bool _isFirstLocation = true;


  Map<String, double> myLocation = {
    "lat": 23.27491548663772,
    "lng": 112.68073532165043,
  };

  Timer? _realtimeTimer;

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
    LocationService().addListener(_onLocationUpdate);
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
    LocationService().removeListener(_onLocationUpdate);
    super.dispose();
  }

  Future<void> _fetchLocationData({bool isSilent = false}) async {
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
            "status": (e['isOnline'] == true) ? "在线" : "离线",
            "lat": e['lat'] ?? 30.5450,
            "lng": e['lng'] ?? 114.3100,
            "battery": e['batteryLevel'] ?? 0,
            "volume": e['volumeLevel'] ?? 0,
            "isOnline": e['isOnline'] ?? false,
            "memberId": e['memberId']?.toString() ?? '',
            "isAnomaly": e['isAnomaly'] ?? false,
          }).toList();

          if (boundDevices.isNotEmpty && selectedDeviceId == null) {
            selectedDeviceId = boundDevices.first['id'];
          }

          // 💡 演示修改：此处删除了原本根据后端 isAnomaly 自动触发弹窗的循环逻辑
          // 保证弹窗只由前端点击触发
        });
      }
    } catch (e) {
      if (mounted && !isSilent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("加载设备失败，请检查网络")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showAnomalyAlert(String deviceName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: const [
            Icon(Icons.warning_rounded, color: Colors.redAccent, size: 32),
            SizedBox(width: 10),
            Text("风险预警", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "系统检测到「$deviceName」的实时位置已偏离日常安全活动区域！\n\n请尽快通过电话联系长辈或查看其具体位置，确认安全状况。",
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("我知道了", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text("立即联系", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _startRealtimeTracking() {
    _realtimeTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;
      _fetchLocationData(isSilent: true);
    });
  }

  Future<void> _moveToVisibleCenter(double targetLat, double targetLng) async {
    if (myMapController == null) return;
    double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    Size screenSize = MediaQuery.of(context).size;
    double targetX = screenSize.width / 2;
    double targetY = screenSize.height * 0.375;

    BMFPoint targetScreenPt = BMFPoint(
      targetX * devicePixelRatio,
      targetY * devicePixelRatio,
    );

    BMFMapStatus mapStatus = BMFMapStatus(
      targetGeoPt: BMFCoordinate(targetLat, targetLng),
      targetScreenPt: targetScreenPt,
    );

    await myMapController?.setNewMapStatus(
      mapStatus: mapStatus,
      animateDurationMs: 500,
    );
  }

  void _updateMapOverlays() {
    if (myMapController == null) return;
    myMapController?.cleanAllMarkers();

    BMFMarker myMarker = BMFMarker(
      position: BMFCoordinate(myLocation['lat']!, myLocation['lng']!),
      title: "我的位置",
      icon: "assets/icons/my_location.png",
    );
    myMapController?.addMarker(myMarker);

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

  void _showBindDeviceDialog() {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    final TextEditingController aliasController = TextEditingController();

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
                ElevatedButton(
                  onPressed: isBinding ? null : () async {
                    if (phoneController.text.isEmpty || codeController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("手机号和验证码不能为空")));
                      return;
                    }
                    setStateDialog(() => isBinding = true);
                    try {
                      await ApiClient().post('/api/family/bind/confirm', data: {
                        "phoneNumber": phoneController.text,
                        "code": codeController.text,
                        "alias": aliasController.text.isEmpty ? "长辈" : aliasController.text
                      });

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("绑定成功！")));
                        _fetchLocationData();
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
    double screenHeight = MediaQuery.of(context).size.height;
    double minSize = 210.0 / screenHeight;
    double initialSize = 0.45 > minSize ? 0.45 : minSize + 0.1;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
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

          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: Column(
              children: [
                _buildMapControlButton(
                  icon: Icons.near_me,
                  color: Colors.black87,
                  onTap: () {
                    setState(() {});
                    _updateMapOverlays();
                    if (myMapController != null && myLocation['lat'] != null) {
                      _moveToVisibleCenter(myLocation['lat']!, myLocation['lng']!);
                    }
                  },
                ),
              ],
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: initialSize,
            minChildSize: minSize,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: [minSize, initialSize, 0.85],
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
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 10),
                        width: 40, height: 5,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2.5)),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("家庭设备", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  _fetchLocationData(isSilent: false);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设备状态已更新")));
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 28, color: Colors.blueAccent),
                              ),
                              IconButton(
                                onPressed: _showBindDeviceDialog,
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

                    ...boundDevices.map((device) => _buildDeviceItem(device)),

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

  Widget _buildDeviceItem(Map<String, dynamic> device) {
    bool isOnline = device['isOnline'] ?? false;
    bool isSelected = selectedDeviceId == device['id'];

    return InkWell(
      onTap: () {
        // 💡 演示修改：点击计数逻辑开始
        String devId = device['id'];
        _deviceClickCounts[devId] = (_deviceClickCounts[devId] ?? 0) + 1;

        // 如果连续点击同一个设备 3 次，弹出风险预警
        if (_deviceClickCounts[devId]! >= 3) {
          _showAnomalyAlert(device['name']);
          _deviceClickCounts[devId] = 0; // 弹出后重置计数
        }
        // 演示逻辑结束

        if (!isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设备已离线，无法查看实时位置")));
          return;
        }
        setState(() => selectedDeviceId = device['id']);
        _updateMapOverlays();

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

  Widget _buildMapControlButton({required IconData icon, required VoidCallback onTap, Color color = Colors.black87}) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]
      ),
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

  Widget _buildMapLayer() {
    double offsetLat = myLocation['lat']! - 0.018;

    BMFMapOptions mapOptions = BMFMapOptions(
      center: BMFCoordinate(offsetLat, myLocation['lng']!),
      zoomLevel: 15,
      rotateEnabled: false,
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