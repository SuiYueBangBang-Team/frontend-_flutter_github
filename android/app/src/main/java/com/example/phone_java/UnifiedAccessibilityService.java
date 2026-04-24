package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;

import android.content.Context;
import android.content.Intent;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.Log;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * 统一无障碍服务 - 集成了微信、高德、美团、拼多多的自动化逻辑。
 */
public class UnifiedAccessibilityService extends AccessibilityService {

    private static final String TAG = "UnifiedAuto";
    private static UnifiedAccessibilityService instance;

    // SOS 相关变量
    private int volumePressCount = 0;
    private long lastPressTime = 0;
    private static final long DOUBLE_PRESS_TIMEOUT = 1000;  // 连续按键时间窗口
    private static final int TRIGGER_COUNT = 3;            // 需要连续按3次

    public static UnifiedAccessibilityService getInstance() {
        return instance;
    }

    private final WeChatAutoService weChatHandler = new WeChatAutoService();
    private final AmapAutoService amapHandler = new AmapAutoService();
    private final MeituanAutoService meituanHandler = new MeituanAutoService();
    private final PinduoduoAutoService pinduoduoHandler = new PinduoduoAutoService();
    private final AntiFraudHandler fraudHandler = new AntiFraudHandler();

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED 
                        | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                        | AccessibilityEvent.TYPE_VIEW_CLICKED
                        | AccessibilityEvent.TYPE_VIEW_FOCUSED
                        | AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED; // 新增：监听通知 (短信/微信提醒)
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.notificationTimeout = 100;
        
        // 移除 packageNames 限制，改为全局监听，或增加常见的通讯应用
        info.packageNames = null; 
        
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS 
                   | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                   | AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS;
        
        setServiceInfo(info);
        Log.d(TAG, "UnifiedAccessibilityService 已连接，反诈卫士已就绪。");
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
    }



    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) return;
        
        // 核心：反诈检测逻辑 (对所有事件进行文本提取分析)
        fraudHandler.onAccessibilityEvent(this, event);

        String packageName = event.getPackageName().toString();
        
        // 根据包名分发专项自动化逻辑
        switch (packageName) {
            case "com.tencent.mm":
                weChatHandler.handleEvent(this, event);
                break;
            case "com.autonavi.minimap":
                amapHandler.handleEvent(this, event);
                break;
            case "com.sankuai.meituan":
                meituanHandler.handleEvent(this, event);
                break;
            case "com.xunmeng.pinduoduo":
                pinduoduoHandler.handleEvent(this, event);
                break;
        }
    }

    @Override
    public void onInterrupt() {
        Log.w(TAG, "UnifiedAccessibilityService 被中断");
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            int keyCode = event.getKeyCode();
            if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                long currentTime = System.currentTimeMillis();

                if (currentTime - lastPressTime > DOUBLE_PRESS_TIMEOUT) {
                    volumePressCount = 1;
                } else {
                    volumePressCount++;
                }
                lastPressTime = currentTime;

                Log.d(TAG, "音量键按下，当前计数: " + volumePressCount);

                if (volumePressCount >= TRIGGER_COUNT) {
                    volumePressCount = 0;
                    triggerEmergencySOS();
                    return true;  // 消费事件
                }
            }
        }
        return super.onKeyEvent(event);
    }

    private void triggerEmergencySOS() {
        Log.i(TAG, "触发紧急救助功能 (SOS)!");

        // 1. 震动反馈
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v != null) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(new long[]{0, 200, 100, 200}, -1));
            } else {
                v.vibrate(new long[]{0, 200, 100, 200}, -1);
            }
        }

        // 2. 发送广播给 MainActivity 转发给 Flutter
        Intent intent = new Intent("com.example.phone_java.SOS_TRIGGER");
        intent.setPackage(getPackageName());
        sendBroadcast(intent);
    }
}
