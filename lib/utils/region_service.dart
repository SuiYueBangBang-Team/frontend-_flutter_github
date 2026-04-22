import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class RegionService {
  static final RegionService _instance = RegionService._internal();
  factory RegionService() => _instance;
  RegionService._internal();

  List<dynamic>? _data;
  bool get isReady => _data != null;

  Future<void> init() async {
    if (_data != null) return;
    String jsonStr = await rootBundle.loadString('assets/data/china_regions.json');
    _data = jsonDecode(jsonStr);
  }

  List<String> getProvinces() {
    if (_data == null) return ["全部省份"];
    return ["全部省份", ..._data!.map((p) => p['name'] as String)];
  }

  List<String> getCities(String province) {
    if (_data == null) return ["全部城市"];
    final prov = _data!.cast<Map<String, dynamic>>().firstWhere(
      (p) => p['name'] == province,
      orElse: () => <String, dynamic>{},
    );
    if (prov.isEmpty) return ["全部城市"];
    List cities = prov['cities'] ?? [];
    return ["全部城市", ...cities.map((c) => c['name'] as String)];
  }

  List<String> getDistricts(String province, String city) {
    if (_data == null) return ["全部区县"];
    final prov = _data!.cast<Map<String, dynamic>>().firstWhere(
      (p) => p['name'] == province,
      orElse: () => <String, dynamic>{},
    );
    if (prov.isEmpty) return ["全部区县"];
    List cities = prov['cities'] ?? [];
    final c = cities.cast<Map<String, dynamic>>().firstWhere(
      (ci) => ci['name'] == city,
      orElse: () => <String, dynamic>{},
    );
    if (c.isEmpty) return ["全部区县"];
    return ["全部区县", ...List<String>.from(c['districts'] ?? [])];
  }
}
