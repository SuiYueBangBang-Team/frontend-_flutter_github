package com.example.phone_java;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;

import java.util.List;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "voice_intent";
    private static final String ACCESSIBILITY_CHANNEL = "com.yourcompany.phone_java/accessibility";
    private static final String FLOAT_CHANNEL = "com.yourcompany.phone_java/float_window";

    public static final String PREF_NAME = "com.example.phone_java";
    public static final String KEY_WECHAT_CONTACT = "wechat_contact";
    public static final String KEY_WECHAT_REQUEST_ID = "wechat_request_id";
    public static final String KEY_WECHAT_SCAN_REQUEST_ID = "wechat_scan_request_id";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    android.util.Log.d("MainActivity", "收到 Flutter 调用: " + call.method + ", 参数 appName: " + call.argument("appName"));
                    if ("openAppByName".equals(call.method)) {
                        String appName = call.argument("appName");
                        boolean opened = openAppByName(appName);
                        android.util.Log.d("MainActivity", "openAppByName(" + appName + ") = " + opened);
                        result.success(opened);
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

        // 监听悬浮窗的语音事件，透传到 Flutter（暂时禁用）
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

    private static final String TAG = "MainActivity";
    private static final String WECHAT_PACKAGE = "com.tencent.mm";

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
}
