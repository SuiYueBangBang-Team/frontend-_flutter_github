package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;

/**
 * 统一无障碍服务 - 集成了微信、高德、美团、拼多多的自动化逻辑，
 * 同时继承了原远程控制服务的全局手势模拟能力。
 */
public class UnifiedAccessibilityService extends AccessibilityService {

    private static final String TAG = "UnifiedAuto";
    private static UnifiedAccessibilityService instance;

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
                   | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        
        setServiceInfo(info);
        Log.d(TAG, "UnifiedAccessibilityService 已连接，反诈卫士已就绪。");
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
    }

    /**
     * 模拟点击（用于远程协助）
     */
    public void simulateClick(int x, int y) {
        Log.d(TAG, "模拟点击: (" + x + ", " + y + ")");
        GestureDescription.Builder builder = new GestureDescription.Builder();
        Path path = new Path();
        path.moveTo(x, y);
        builder.addStroke(new GestureDescription.StrokeDescription(path, 0, 10));
        dispatchGesture(builder.build(), null, null);
    }

    /**
     * 模拟滑动（用于远程协助）
     */
    public void simulateSwipe(int x1, int y1, int x2, int y2, int duration) {
        Log.d(TAG, "模拟滑动: (" + x1 + ", " + y1 + ") -> (" + x2 + ", " + y2 + ")");
        GestureDescription.Builder builder = new GestureDescription.Builder();
        Path path = new Path();
        path.moveTo(x1, y1);
        path.lineTo(x2, y2);
        builder.addStroke(new GestureDescription.StrokeDescription(path, 0, duration));
        dispatchGesture(builder.build(), null, null);
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
}
