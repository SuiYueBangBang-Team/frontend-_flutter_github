package com.example.phone_java;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;

import androidx.annotation.NonNull;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import java.io.File;

import java.util.List;

import com.example.phone_java.BuildConfig;
import com.tencent.mm.opensdk.modelbiz.WXLaunchMiniProgram;
import com.tencent.mm.opensdk.openapi.IWXAPI;
import com.tencent.mm.opensdk.openapi.WXAPIFactory;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.app.Activity;

public class MainActivity extends FlutterActivity {

    private static final int REQUEST_PHONE_STATE_PERMISSIONS = 5678;

    /**
     * 话费充值小程序「账号原始ID」（截图）。拉起接口使用 gh_ 原始 ID，不是小程序 AppID（wx...）。
     */
    private static final String RECHARGE_MINI_PROGRAM_USER_NAME = "gh_fefb88a96b0e";

    private static final String CHANNEL = "voice_intent";
    private static final String ACCESSIBILITY_CHANNEL = "com.yourcompany.phone_java/accessibility";
    private static final String FLOAT_CHANNEL = "com.yourcompany.phone_java/float_window";
    private static final String EMERGENCY_CHANNEL = "com.yourcompany.phone_java/emergency";

    private static final String TAG = "MainActivity";
    private static final String WECHAT_PACKAGE = "com.tencent.mm";
    private static final String AMAP_PACKAGE = "com.autonavi.minimap";
    private static final String MEITUAN_PACKAGE = "com.sankuai.meituan";
    private static final String PINDUODUO_PACKAGE = "com.xunmeng.pinduoduo";

    public static final String PREF_NAME = "com.example.phone_java";
    public static final String KEY_WECHAT_CONTACT = "wechat_contact";
    public static final String KEY_WECHAT_REQUEST_ID = "wechat_request_id";
    public static final String KEY_WECHAT_SCAN_REQUEST_ID = "wechat_scan_request_id";
    public static final String KEY_WECHAT_PAYMENT_REQUEST_ID = "wechat_payment_request_id"; // 💡 新增：微信付款码任务 ID
    public static final String KEY_AMAP_REQUEST_ID = "amap_request_id";
    public static final String KEY_AMAP_DESTINATION = "amap_destination";
    public static final String KEY_MEITUAN_REQUEST_ID = "meituan_request_id";
    public static final String KEY_MEITUAN_KEYWORD = "meituan_keyword";
    public static final String KEY_PINDUODUO_REQUEST_ID = "pinduoduo_request_id";
    public static final String KEY_PINDUODUO_KEYWORD = "pinduoduo_keyword";

    private IWXAPI wxApi;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        registerWeChatAppIfConfigured();

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    android.util.Log.d("MainActivity", "收到 Flutter 调用: " + call.method + ", 参数 appName: " + call.argument("appName"));
                    if ("openAppByName".equals(call.method)) {
                        String appName = call.argument("appName");
                        boolean opened = openAppByName(appName);
                        android.util.Log.d("MainActivity", "openAppByName(" + appName + ") = " + opened);
                        result.success(opened);
                    } else if ("launchWeChatMiniProgram".equals(call.method)) {
                        String userName = call.argument("userName");
                        String path = call.argument("path");
                        Integer miniType = call.argument("miniprogramType");
                        if (userName == null || userName.trim().isEmpty()) {
                            result.success(false);
                            return;
                        }
                        boolean ok = launchWeChatMiniProgram(userName.trim(), path != null ? path : "", miniType);
                        result.success(ok);
                    } else if ("launchWeChatPhoneRechargeMiniProgram".equals(call.method)) {
                        String path = call.argument("path");
                        boolean ok = launchWeChatMiniProgram(RECHARGE_MINI_PROGRAM_USER_NAME, path != null ? path : "", null);
                        result.success(ok);
                    } else {
                        android.util.Log.w("MainActivity", "未知方法: " + call.method);
                        result.notImplemented();
                    }
                });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ACCESSIBILITY_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("startWeChatCall".equals(call.method)) {
                        String contact = call.argument("contact");
                        boolean ok = cacheWeChatTargetAndLaunch(contact);
                        result.success(ok);
                    } else if ("startWeChatSendMessage".equals(call.method)) {
                        String contact = call.argument("contact");
                        String message = call.argument("message");
                        boolean ok = cacheWeChatSendAndLaunch(contact, message);
                        result.success(ok);
                    } else if ("startWeChatScan".equals(call.method)) {
                        boolean ok = cacheWeChatScanAndLaunch();
                        result.success(ok);
                    } else if ("startWeChatPayment".equals(call.method)) {
                        // 💡 新增：微信付款码
                        boolean ok = cacheWeChatPaymentAndLaunch();
                        result.success(ok);
                    } else if ("startAmapNavi".equals(call.method)) {
                        String destination = call.argument("destination");
                        boolean ok = cacheAmapNaviAndLaunch(destination);
                        result.success(ok);
                    } else if ("startMeituanSearch".equals(call.method)) {
                        String keyword = call.argument("keyword");
                        boolean ok = cacheMeituanKeywordAndLaunch(keyword);
                        result.success(ok);
                    } else if ("startPinduoduoSearch".equals(call.method)) {
                        String keyword = call.argument("keyword");
                        boolean ok = cachePinduoduoKeywordAndLaunch(keyword);
                        result.success(ok);
                    } else {
                        result.notImplemented();
                    }
                });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), FLOAT_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("show".equals(call.method)) {
                        FloatWindowService.show(MainActivity.this);
                        result.success(true);
                    } else if ("hide".equals(call.method)) {
                        FloatWindowService.hide(MainActivity.this);
                        result.success(true);
                    } else if ("updateRecording".equals(call.method)) {
                        boolean recording = call.argument("recording");
                        FloatWindowService.updateRecordingState(MainActivity.this, recording);
                        result.success(true);
                    } else {
                        result.notImplemented();
                    }
                });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.yourcompany.phone_java/rustdesk")
                .setMethodCallHandler((call, result) -> {
                    if ("isPackageInstalled".equals(call.method)) {
                        String packageName = call.argument("packageName");
                        boolean installed = isPackageInstalled(packageName);
                        android.util.Log.d(TAG, packageName + " 是否已安装: " + installed);
                        result.success(installed);
                    } else if ("launchPackage".equals(call.method)) {
                        String packageName = call.argument("packageName");
                        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(packageName);
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(launchIntent);
                            android.util.Log.d(TAG, "✅ 已启动: " + packageName);
                            result.success(true);
                        } else {
                            android.util.Log.e(TAG, "❌ 无法启动 " + packageName + "，可能未安装");
                            result.success(false);
                        }
                    } else if ("installApk".equals(call.method)) {
                        // 从 Flutter 传来的 APK 文件路径，触发系统安装器
                        String filePath = call.argument("filePath");
                        if (filePath != null) {
                            try {
                                File apkFile = new File(filePath);
                                if (apkFile.exists()) {
                                    Uri apkUri = FileProvider.getUriForFile(
                                            MainActivity.this,
                                            getApplicationContext().getPackageName() + ".fileprovider",
                                            apkFile);
                                    Intent installIntent = new Intent(Intent.ACTION_VIEW);
                                    installIntent.setDataAndType(apkUri, "application/vnd.android.package-archive");
                                    installIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                    installIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                                    startActivity(installIntent);
                                    android.util.Log.d(TAG, "\u2705 \u5df2\u5524\u8d77\u7cfb\u7edf\u5b89\u88c5\u5668: " + filePath);
                                    result.success(true);
                                } else {
                                    android.util.Log.e(TAG, "\u274c APK \u6587\u4ef6\u4e0d\u5b58\u5728: " + filePath);
                                    result.success(false);
                                }
                            } catch (Exception e) {
                                android.util.Log.e(TAG, "\u274c \u5b89\u88c5 APK \u5f02\u5e38: " + e.getMessage());
                                result.error("INSTALL_ERROR", e.getMessage(), null);
                            }
                        } else {
                            result.error("INVALID_ARGS", "filePath is null", null);
                        }
                    } else {
                        result.notImplemented();
                    }
                });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.yourcompany.phone_java/anti_fraud")
                .setMethodCallHandler((call, result) -> {
                    if ("requestCallScreeningRole".equals(call.method)) {
                        android.util.Log.i(TAG, "[反诈角色请求] API Level: " + android.os.Build.VERSION.SDK_INT);
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            android.app.role.RoleManager roleManager = (android.app.role.RoleManager) getSystemService(Context.ROLE_SERVICE);
                            if (roleManager != null) {
                                if (!roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING)) {
                                    Intent intent = roleManager.createRequestRoleIntent(android.app.role.RoleManager.ROLE_CALL_SCREENING);
                                    if (intent != null) {
                                        startActivityForResult(intent, 1234);
                                        result.success("REQUESTING");
                                    } else {
                                        result.success("INTENT_NULL");
                                    }
                                } else {
                                    result.success("ALREADY_HELD");
                                }
                            } else {
                                result.success("ROLE_MANAGER_NULL");
                            }
                        } else {
                            result.success("NOT_SUPPORTED");
                        }
                    } else if ("openDefaultAppsSettings".equals(call.method)) {
                        try {
                            Intent intent = new Intent(android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS);
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(intent);
                            result.success(true);
                        } catch (Exception e) {
                            result.success(false);
                        }
                    } else if ("checkCallScreeningRole".equals(call.method)) {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            android.app.role.RoleManager roleManager = (android.app.role.RoleManager) getSystemService(Context.ROLE_SERVICE);
                            if (roleManager != null) {
                                result.success(roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING));
                            } else {
                                result.success(false);
                            }
                        } else {
                            result.success(false);
                        }
                    } else if ("checkPhoneStatePermissions".equals(call.method)) {
                        boolean hasReadPhone = ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED;
                        boolean hasReadLog = ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED;
                        boolean hasAnswer = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED;
                        result.success(hasReadPhone && hasReadLog && hasAnswer);
                    } else if ("requestPhoneStatePermissions".equals(call.method)) {
                        String[] perms = {
                            android.Manifest.permission.READ_PHONE_STATE,
                            android.Manifest.permission.READ_CALL_LOG,
                            android.Manifest.permission.ANSWER_PHONE_CALLS
                        };
                        boolean allGranted = true;
                        for (String p : perms) {
                            if (ContextCompat.checkSelfPermission(this, p) != PackageManager.PERMISSION_GRANTED) {
                                allGranted = false;
                                break;
                            }
                        }
                        if (allGranted) {
                            result.success("ALREADY_GRANTED");
                        } else {
                            ActivityCompat.requestPermissions(this, perms, REQUEST_PHONE_STATE_PERMISSIONS);
                            result.success("REQUESTING");
                        }
                    } else if ("startAntiFraudService".equals(call.method)) {
                        AntiFraudForegroundService.start(MainActivity.this);
                        result.success(true);
                    } else if ("stopAntiFraudService".equals(call.method)) {
                        AntiFraudForegroundService.stop(MainActivity.this);
                        result.success(true);
                    } else if ("isAntiFraudServiceRunning".equals(call.method)) {
                        result.success(AntiFraudForegroundService.isRunning());
                    } else {
                        result.notImplemented();
                    }
                });

        // 监听悬浮窗的语音事件，透传到 Flutter（暂时禁用）
        
        // SOS 广播监听
        android.content.IntentFilter filter = new android.content.IntentFilter("com.example.phone_java.SOS_TRIGGER");
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(new android.content.BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    android.util.Log.i(TAG, "收到 SOS 广播，通知 Flutter");
                    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), EMERGENCY_CHANNEL)
                            .invokeMethod("onEmergencySOS", null);
                }
            }, filter, Context.RECEIVER_EXPORTED);
        } else {
            registerReceiver(new android.content.BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    android.util.Log.i(TAG, "收到 SOS 广播，通知 Flutter");
                    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), EMERGENCY_CHANNEL)
                            .invokeMethod("onEmergencySOS", null);
                }
            }, filter);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 1234) {
            boolean actuallyHeld = false;
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                android.app.role.RoleManager rm = (android.app.role.RoleManager) getSystemService(Context.ROLE_SERVICE);
                if (rm != null) {
                    actuallyHeld = rm.isRoleHeld(android.app.role.RoleManager.ROLE_CALL_SCREENING);
                }
            }
            android.util.Log.i(TAG, "[角色请求结果] resultCode=" + resultCode + ", 实际持有=" + actuallyHeld);
            if (getFlutterEngine() != null) {
                new MethodChannel(getFlutterEngine().getDartExecutor().getBinaryMessenger(), "com.yourcompany.phone_java/anti_fraud")
                    .invokeMethod("roleResult", actuallyHeld);
            }
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_PHONE_STATE_PERMISSIONS) {
            boolean allGranted = true;
            for (int r : grantResults) {
                if (r != PackageManager.PERMISSION_GRANTED) {
                    allGranted = false;
                    break;
                }
            }
            android.util.Log.i(TAG, "[降级权限结果] allGranted=" + allGranted);
            if (getFlutterEngine() != null) {
                new MethodChannel(getFlutterEngine().getDartExecutor().getBinaryMessenger(), "com.yourcompany.phone_java/anti_fraud")
                    .invokeMethod("phoneStatePermResult", allGranted);
            }
        }
    }

    private void registerWeChatAppIfConfigured() {
        String appId = BuildConfig.WECHAT_APP_ID;
        if (appId == null || appId.isEmpty()) {
            android.util.Log.w(TAG, "未配置 wechat.app.id，微信 SDK 未注册（无法拉起小程序）");
            return;
        }
        wxApi = WXAPIFactory.createWXAPI(this, appId, true);
        wxApi.registerApp(appId);
        android.util.Log.d(TAG, "微信 SDK 已注册 AppID（移动应用）");
    }

    /**
     * 使用微信开放平台 SDK 拉起小程序。需在微信开放平台创建「移动应用」，包名与签名与当前 APK 一致，并配置 gradle.properties：wechat.app.id
     */
    private boolean launchWeChatMiniProgram(String userName, String path, Integer miniprogramType) {
        String appId = BuildConfig.WECHAT_APP_ID;
        if (appId == null || appId.isEmpty()) {
            android.util.Log.e(TAG, "请在 android/gradle.properties 中配置 wechat.app.id（微信开放平台「移动应用」AppID）");
            return false;
        }
        if (wxApi == null) {
            wxApi = WXAPIFactory.createWXAPI(this, appId, true);
            wxApi.registerApp(appId);
        }
        if (!wxApi.isWXAppInstalled()) {
            android.util.Log.e(TAG, "微信未安装");
            return false;
        }
        if (userName == null || userName.trim().isEmpty()) {
            android.util.Log.e(TAG, "小程序 userName（原始ID，gh_开头）为空");
            return false;
        }
        WXLaunchMiniProgram.Req req = new WXLaunchMiniProgram.Req();
        req.userName = userName.trim();
        req.path = path != null ? path : "";
        int t = miniprogramType != null ? miniprogramType : 0;
        req.miniprogramType = t;
        boolean sent = wxApi.sendReq(req);
        android.util.Log.d(TAG, "launchWeChatMiniProgram userName=" + req.userName + " sent=" + sent);
        return sent;
    }

    private boolean cacheWeChatTargetAndLaunch(String contact) {
        android.util.Log.d(TAG, "✅ cacheWeChatTargetAndLaunch 被调用，contact = " + contact);

        if (contact == null || contact.trim().isEmpty()) {
            android.util.Log.e(TAG, "❌ contact 为空，直接返回 false");
            return false;
        }

        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_WECHAT_CONTACT, contact.trim())
                .putLong(KEY_WECHAT_REQUEST_ID, System.currentTimeMillis())
                .apply();

        android.util.Log.d(TAG, "✅ SharedPreferences 写入完成:");
        android.util.Log.d(TAG, "   - PREF_NAME: " + PREF_NAME);
        android.util.Log.d(TAG, "   - KEY_WECHAT_CONTACT: " + KEY_WECHAT_CONTACT + " = " + contact.trim());
        android.util.Log.d(TAG, "   - KEY_WECHAT_REQUEST_ID: " + System.currentTimeMillis());

        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(WECHAT_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 微信已启动！");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到微信包名: " + WECHAT_PACKAGE);
        return false;
    }

    // 缓存微信发消息参数并拉起微信
    private boolean cacheWeChatSendAndLaunch(String contact, String message) {
        if (contact == null || contact.trim().isEmpty() || message == null || message.trim().isEmpty()) {
            android.util.Log.e(TAG, "❌ contact 或 message 为空，拒绝执行");
            return false;
        }
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_WECHAT_CONTACT, contact.trim())
                .putString("wechat_message", message.trim())
                .putLong(KEY_WECHAT_REQUEST_ID, System.currentTimeMillis())
                .apply();
        android.util.Log.d(TAG, "✅ 微信发消息参数缓存: contact=" + contact.trim() + ", message=" + message.trim());
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(WECHAT_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 微信已启动，等待无障碍服务自动化");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到微信包名");
        return false;
    }

    /** 拉起微信并由无障碍服务打开主界面「扫一扫」 */
    private boolean cacheWeChatScanAndLaunch() {
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putLong(KEY_WECHAT_SCAN_REQUEST_ID, System.currentTimeMillis())
                .apply();
        android.util.Log.d(TAG, "✅ 微信扫一扫任务已写入 wechat_scan_request_id");
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(WECHAT_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 微信已启动，等待无障碍打开扫一扫");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到微信包名");
        return false;
    }

    /**
     * 💡 新增：拉起微信并由无障碍服务自动导航到「收付款」页面
     * 流程：微信主界面 → 点击「+」更多按钮 → 点击弹出菜单中「收付款」
     */
    private boolean cacheWeChatPaymentAndLaunch() {
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putLong(KEY_WECHAT_PAYMENT_REQUEST_ID, System.currentTimeMillis())
                .apply();
        android.util.Log.d(TAG, "✅ 微信付款码任务已写入 wechat_payment_request_id");
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(WECHAT_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 微信已启动，等待无障碍服务自动打开收付款");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到微信包名: " + WECHAT_PACKAGE);
        return false;
    }

    /** 缓存高德导航目的地并拉起高德地图，由无障碍服务自动输入目的地并开始导航 */
    /** 缓存高德导航目的地并拉起高德地图，由无障碍服务自动输入目的地并开始导航 */
    private boolean cacheAmapNaviAndLaunch(String destination) {
        if (destination == null || destination.trim().isEmpty()) {
            android.util.Log.e(TAG, "❌ 高德导航目的地为空，拒绝执行");
            return false;
        }
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_AMAP_DESTINATION, destination.trim())
                .putLong(KEY_AMAP_REQUEST_ID, System.currentTimeMillis())
                .apply();
        android.util.Log.d(TAG, "✅ 高德导航目的地已缓存: " + destination.trim());

        // 【修复】只启动高德主页，完全交给无障碍服务自动化
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(AMAP_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 高德地图已启动，等待无障碍服务自动搜索目的地");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到高德地图包名: " + AMAP_PACKAGE);
        return false;
    }

    /** 缓存美团搜索关键词并拉起美团，由无障碍服务自动点击搜索框、输入关键词、点搜索 */
    private boolean cacheMeituanKeywordAndLaunch(String keyword) {
        if (keyword == null || keyword.trim().isEmpty()) {
            android.util.Log.e(TAG, "❌ 美团搜索关键词为空，拒绝执行");
            return false;
        }
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_MEITUAN_KEYWORD, keyword.trim())
                .putLong(KEY_MEITUAN_REQUEST_ID, System.currentTimeMillis())
                .apply();
        android.util.Log.d(TAG, "✅ 美团搜索关键词已缓存: " + keyword.trim());

        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(MEITUAN_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 美团已启动，等待无障碍服务自动搜索关键词");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到美团包名: " + MEITUAN_PACKAGE);
        return false;
    }

    /** 缓存拼多多搜索关键词并拉起拼多多，由无障碍服务自动点击搜索框、输入关键词、点搜索 */
    private boolean cachePinduoduoKeywordAndLaunch(String keyword) {
        if (keyword == null || keyword.trim().isEmpty()) {
            android.util.Log.e(TAG, "❌ 拼多多搜索关键词为空，拒绝执行");
            return false;
        }
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_PINDUODUO_KEYWORD, keyword.trim())
                .putLong(KEY_PINDUODUO_REQUEST_ID, System.currentTimeMillis())
                .apply();
        android.util.Log.d(TAG, "✅ 拼多多搜索关键词已缓存: " + keyword.trim());

        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(PINDUODUO_PACKAGE);
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launchIntent);
            android.util.Log.d(TAG, "✅ 拼多多已启动，等待无障碍服务自动搜索关键词");
            return true;
        }
        android.util.Log.e(TAG, "❌ 未找到拼多多包名: " + PINDUODUO_PACKAGE);
        return false;
    }


    private boolean openAppByName(String appName) {
        android.util.Log.d("MainActivity", "openAppByName() 被调用，appName = " + appName);
        if (appName == null || appName.trim().isEmpty()) {
            android.util.Log.w("MainActivity", "❌ appName 为空，直接返回 false");
            return false;
        }
        PackageManager pm = getPackageManager();
        List<ApplicationInfo> apps = pm.getInstalledApplications(0);
        String targetName = appName.trim().toLowerCase();
        android.util.Log.d("MainActivity", "开始遍历已安装应用，targetName = " + targetName + "，共 " + apps.size() + " 个");
        for (ApplicationInfo app : apps) {
            String label = pm.getApplicationLabel(app).toString();
            android.util.Log.d("MainActivity", "遍历 app: " + label + " (package: " + app.packageName + ")");
            if (label != null && label.toLowerCase().contains(targetName)) {
                android.util.Log.d("MainActivity", "✅ 匹配成功: " + label);
                Intent launchIntent = pm.getLaunchIntentForPackage(app.packageName);
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(launchIntent);
                    android.util.Log.i("MainActivity", "✅ 应用已启动: " + label);
                    return true;
                } else {
                    android.util.Log.w("MainActivity", "⚠️ 匹配成功但 launchIntent 为 null: " + label);
                }
            }
        }
        android.util.Log.w("MainActivity", "❌ 未找到匹配应用: " + appName);
        return false;
    }

    /** 检查指定包名的应用是否已安装 */
    private boolean isPackageInstalled(String packageName) {
        try {
            getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }
}
