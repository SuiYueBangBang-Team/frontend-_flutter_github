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

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED 
                        | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                        | AccessibilityEvent.TYPE_VIEW_CLICKED
                        | AccessibilityEvent.TYPE_VIEW_FOCUSED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.notificationTimeout = 100;
        
        // 监听 4 个核心应用的包名
        info.packageNames = new String[]{
                "com.tencent.mm",           // 微信
                "com.autonavi.minimap",     // 高德地图
                "com.sankuai.meituan",      // 美团
                "com.xunmeng.pinduoduo"     // 拼多多
        };
        
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS 
                   | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        
        setServiceInfo(info);
        Log.d(TAG, "UnifiedAccessibilityService 已连接，手势功能就绪。");
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
        
        String packageName = event.getPackageName().toString();
        
        // 根据包名分发事件
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
