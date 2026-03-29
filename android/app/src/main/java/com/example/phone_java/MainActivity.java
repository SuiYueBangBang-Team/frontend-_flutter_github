package com.example.phone_java;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;

import androidx.annotation.NonNull;

import java.util.List;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    // 原有的通用通道
    private static final String CHANNEL = "voice_intent";

    // 💡 新增：与 Flutter 中对应的新通道
    private static final String ACCESSIBILITY_CHANNEL = "com.yourcompany.phone_java/accessibility";

    // 共享常量的定义（你刚才补充的）
    public static final String PREF_NAME = "voice_automation";
    public static final String KEY_WECHAT_CONTACT = "wechat_target_contact";
    public static final String KEY_WECHAT_REQUEST_ID = "wechat_request_id";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // 1. 注册原有的 openAppByName 监听
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("openAppByName".equals(call.method)) {
                        String appName = call.argument("appName");
                        boolean opened = openAppByName(appName);
                        result.success(opened);
                    } else {
                        result.notImplemented();
                    }
                });

        // 💡 2. 新增：注册微信自动化通话监听
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ACCESSIBILITY_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("startWeChatCall".equals(call.method)) {
                        String contact = call.argument("contact");
                        startWeChatCall(contact);
                        result.success(true);
                    } else {
                        result.notImplemented();
                    }
                });
    }

    // 💡 核心逻辑：接收到联系人后，写入 SharedPreferences，并拉起微信
    private void startWeChatCall(String contact) {
        if (contact == null || contact.trim().isEmpty()) {
            return;
        }

        // 1. 将目标联系人和当前时间戳（作为唯一请求ID）写入本地缓存
        // WeChatAutoService 检测到新的 RequestID 就会开始工作
        SharedPreferences prefs = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_WECHAT_CONTACT, contact)
                .putLong(KEY_WECHAT_REQUEST_ID, System.currentTimeMillis())
                .apply();

        // 2. 拉起微信 (包名固定为 com.tencent.mm)
        PackageManager pm = getPackageManager();
        Intent intent = pm.getLaunchIntentForPackage("com.tencent.mm");
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            startActivity(intent);
        }
    }

    private boolean openAppByName(String appName) {
        if (appName == null || appName.trim().isEmpty()) {
            return false;
        }
        PackageManager pm = getPackageManager();
        List<ApplicationInfo> apps = pm.getInstalledApplications(0);
        String targetName = appName.trim().toLowerCase();
        for (ApplicationInfo app : apps) {
            String label = pm.getApplicationLabel(app).toString();
            if (label != null && label.toLowerCase().contains(targetName)) {
                Intent launchIntent = pm.getLaunchIntentForPackage(app.packageName);
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(launchIntent);
                    return true;
                }
            }
        }
        return false;
    }
}