import 'package:flutter/material.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async'; // 补充引入 Completer 需要的包

class LocationService {
  // 1. 单例模式，确保全局只有一个定位实例
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();
  bool _isInitialized = false;

  // 2. 缓存最新的经纬度，方便发帖页面直接读取
  double? latitude;
  double? longitude;

  // 3. 监听器列表，支持多个页面同时监听定位变化
  final List<Function(double lat, double lng)> _listeners = [];

  // 添加监听
  void addListener(Function(double, double) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  // 移除监听
  void removeListener(Function(double, double) listener) {
    _listeners.remove(listener);
  }

  /// 🌟 新增：专门为社区、发帖页准备的“单次逆地理编码（解析地址）”方法
  Future<String?> getSingleAddress() async {
    // 1. 创建一个“任务承诺 (Completer)”
    Completer<String?> completer = Completer();

    try {
      _locationPlugin.setAgreePrivacy(true);

      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: true, // 必须开启地址解析
        openGps: true,
        coordType: BMFLocationCoordType.bd09ll,
        scanspan: 1000,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});

      _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
        // 2. 拦截：如果没有解析出中文地址，直接 return 等下一次
        if (result.address == null && result.locationDetail == null) {
          return;
        }

        // 3. 拿到真实地址
        String realAddress = result.locationDetail ?? result.address ?? "未知位置";

        // 4. 如果这个“承诺”还没兑现，我们就兑现它（返回数据）
        if (!completer.isCompleted) {
          completer.complete(realAddress);
          // 💡 拿到中文地址后，立刻掐断底层定位，省电！
          _locationPlugin.stopLocation();
        }
      });

      await _locationPlugin.startLocation();

      // 5. 返回这个“承诺”，调用它的页面会在这里一直等（await），直到上面 complete
      return completer.future;

    } catch (e) {
      // debugPrint("单次定位异常: $e");
      if (!completer.isCompleted) completer.complete("定位失败");
      return completer.future;
    }
  }

  // 请求权限并开启定位
  Future<bool> requestPermissionAndLocate() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      await _initLocation();
      return true;
    }
    return false;
  }

  // 原汁原味的百度定位初始化逻辑
  Future<void> _initLocation() async {
    if (_isInitialized) {
      // 如果已经初始化过，直接启动即可
      _locationPlugin.startLocation();
      return;
    }

    try {
      // debugPrint("📌 LocationService: 正在初始化百度定位...");
      _locationPlugin.setAgreePrivacy(true);

      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: true,
        openGps: true,
        coordType: BMFLocationCoordType.bd09ll,
        scanspan: 8000,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});

      _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
        // debugPrint("📍 百度定位回调到达! 错误码=${result.errorCode}, 经度=${result.longitude}, 纬度=${result.latitude}");
        if (result.latitude != null && result.longitude != null && result.latitude! > 1.0) {
          latitude = result.latitude;
          longitude = result.longitude;

          // 通知所有正在监听的页面更新UI
          for (var listener in _listeners) {
            listener(latitude!, longitude!);
          }
        }
      });

      await _locationPlugin.startLocation();
      _isInitialized = true;
      // debugPrint("📌 LocationService: 定位启动成功");
    } catch (e) {
      // debugPrint("❌ LocationService 定位异常: $e");
    }
  }

  /// 🌟 修复后：获取精简版的地址信息（城市到区，农村到村）
  Future<Map<String, String>> getSimplifiedLocation() async {
    Completer<Map<String, String>> completer = Completer();

    // 1. 修复点：在单次定位前，主动检查并申请权限
    PermissionStatus status = await Permission.location.request();
    if (!status.isGranted) {
      return {"display": "定位权限被拒绝"};
    }

    try {
      _locationPlugin.setAgreePrivacy(true);
      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: true,
        coordType: BMFLocationCoordType.bd09ll,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});

      _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
        // 2. 修复点：绝不能直接 return 导致死锁。如果拿不到地址，也要 complete 释放 Future
        if (result.address == null && result.district == null) {
          if (!completer.isCompleted) {
            completer.complete({"display": "无法获取详细地址"});
            _locationPlugin.stopLocation();
          }
          return;
        }

        // 核心逻辑：地址精简处理
        String city = result.city ?? "";
        String district = result.district ?? "";
        String town = result.town ?? "";

        String displayAddress;
        if (city.isNotEmpty && district.isNotEmpty) {
          displayAddress = "$city$district";
          if (town.isNotEmpty && !town.contains("街道")) {
            displayAddress = "$city$district$town";
          }
        } else {
          displayAddress = district.isNotEmpty ? district : "未知位置";
        }

        // 3. 成功拿到地址，正常释放 Future
        if (!completer.isCompleted) {
          completer.complete({
            "province": result.province ?? "",
            "city": city,
            "district": district,
            "display": displayAddress,
          });
          _locationPlugin.stopLocation();
        }
      });

      await _locationPlugin.startLocation();
      return completer.future;
    } catch (e) {
      return {"display": "定位组件异常"};
    }
  }

  // 停止定位 (可以在App退出或不需要后台定位时调用)
  void stopLocation() {
    _locationPlugin.stopLocation();
  }



}