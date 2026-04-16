package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;

/**
 * 远程控制无障碍服务 - 专门用于执行全局手势（点击、滑动）
 * 供 RustDesk/ToDesk 演示及控制使用
 */
public class RemoteControlAccessibilityService extends AccessibilityService {

    private static final String TAG = "RemoteControl";
    private static RemoteControlAccessibilityService instance;

    public static RemoteControlAccessibilityService getInstance() {
        return instance;
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        Log.d(TAG, "远程控制无障碍服务已连接");
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // 远程控制服务通常不需要监听特定的 UI 事件，只需提供手势执行能力
    }

    @Override
    public void onInterrupt() {
        Log.w(TAG, "远程控制服务被中断");
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
    }

    /**
     * 模拟点击
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
     * 模拟滑动
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
}
