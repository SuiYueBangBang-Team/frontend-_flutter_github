import 'package:flutter/material.dart';
import 'package:flutter_bmflocation/flutter_bmflocation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final LocationFlutterPlugin _locationPlugin = LocationFlutterPlugin();
  bool _isServiceRunning = false;

  // 1. 状态存储
  double? latitude;
  double? longitude;

  // 2. 消费者队列
  final List<Function(double lat, double lng)> _listeners = []; // 持续监听者（地图）
  final List<Completer<Map<String, String>>> _addressRequests = []; // 单次请求者（发帖）

  /// 统一初始化并设置“中央分发器”
  Future<void> _ensureInitialized() async {
    // 权限检查
    PermissionStatus status = await Permission.location.request();
    if (!status.isGranted) return;

    // 重点：只需设置一次全局回调
    _locationPlugin.setAgreePrivacy(true);
    _locationPlugin.seriesLocationCallback(callback: (BaiduLocation result) {
      // A. 更新内部缓存
      if (result.latitude != null && result.longitude != null) {
        latitude = result.latitude;
        longitude = result.longitude;
      }

      // B. 分发给持续监听者（地图页）
      if (latitude != null && longitude != null) {
        for (var listener in List.from(_listeners)) {
          listener(latitude!, longitude!);
        }
      }

      // C. 分发给单次请求者（发帖页）
      if (result.address != null || result.district != null) {
        if (_addressRequests.isNotEmpty) {
          final locMap = {
            "province": result.province ?? "",
            "city": result.city ?? "",
            "district": result.district ?? "",
            "display": "${result.city ?? ""}${result.district ?? ""}${result.town ?? ""}",
          };

          // 履行所有待处理的“承诺”
          for (var completer in List.from(_addressRequests)) {
            if (!completer.isCompleted) completer.complete(locMap);
          }
          _addressRequests.clear();

          // 优化策略：如果没有地图页在听，拿完地址就关掉引擎省电
          _checkAndStopService();
        }
      }
    });
  }

  /// 智能停止：只有当没有人在听，且没有待处理请求时才真正关闭
  void _checkAndStopService() {
    if (_listeners.isEmpty && _addressRequests.isEmpty) {
      _locationPlugin.stopLocation();
      _isServiceRunning = false;
    }
  }

  /// 发帖页调用：获取精简地址
  Future<Map<String, String>> getSimplifiedLocation() async {
    await _ensureInitialized();

    Completer<Map<String, String>> completer = Completer();
    _addressRequests.add(completer);

    if (!_isServiceRunning) {
      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: true,
        coordType: BMFLocationCoordType.bd09ll,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});
      await _locationPlugin.startLocation();
      _isServiceRunning = true;
    }

    // 增加超时保护，防止永远卡死
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _addressRequests.remove(completer);
      return {"display": "定位超时"};
    });
  }

  /// 地图页调用：开始监听
  void addListener(Function(double, double) listener) async {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }

    await _ensureInitialized();
    if (!_isServiceRunning) {
      BaiduLocationAndroidOption androidOption = BaiduLocationAndroidOption(
        locationMode: BMFLocationMode.hightAccuracy,
        isNeedAddress: true, // 保持开启地址解析以兼容可能的地址显示需求
        coordType: BMFLocationCoordType.bd09ll,
        scanspan: 8000,
      );
      await _locationPlugin.prepareLoc(androidOption.getMap(), {});
      await _locationPlugin.startLocation();
      _isServiceRunning = true;
    }
  }

  /// 移除监听
  void removeListener(Function(double, double) listener) {
    _listeners.remove(listener);
    _checkAndStopService();
  }

  // 旧方法适配
  Future<bool> requestPermissionAndLocate() async {
    await _ensureInitialized();
    return true;
  }
}