package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.os.Build;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import androidx.annotation.RequiresApi;

public class RemoteControlAccessibilityService extends AccessibilityService {
    private static final String TAG = "RemoteControlAccessibilityService";
    private static RemoteControlAccessibilityService instance;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        Log.d(TAG, "RustDesk 远程控制无障碍服务已连接");
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // 在此处不需要主动监听特定页面的 UI 元素变化
        // 这个 Service 主要是为了让 RustDesk 拥有执行全局滑动、点击的手势权限 (performGesture)
    }

    @Override
    public void onInterrupt() {
        Log.w(TAG, "RustDesk 远程控制无障碍服务被中断");
    }

    @Override
    public boolean onUnbind(android.content.Intent intent) {
        instance = null;
        Log.d(TAG, "RustDesk 远程控制无障碍服务已解绑");
        return super.onUnbind(intent);
    }

    public static RemoteControlAccessibilityService getInstance() {
        return instance;
    }

    /**
     * 模拟全局点击事件（由 RustDesk 信令在接收到远端点击坐标时调用）
     */
    @RequiresApi(api = Build.VERSION_CODES.N)
    public void simulateClick(float x, float y) {
        Path clickPath = new Path();
        clickPath.moveTo(x, y);
        GestureDescription.StrokeDescription clickStroke = 
                new GestureDescription.StrokeDescription(clickPath, 0, 100);
        GestureDescription clickBuilder = new GestureDescription.Builder().addStroke(clickStroke).build();

        boolean dispatched = dispatchGesture(clickBuilder, new GestureResultCallback() {
            @Override
            public void onCompleted(GestureDescription gestureDescription) {
                super.onCompleted(gestureDescription);
                Log.d(TAG, "模拟点击成功: x=" + x + ", y=" + y);
            }

            @Override
            public void onCancelled(GestureDescription gestureDescription) {
                super.onCancelled(gestureDescription);
                Log.d(TAG, "模拟点击取消: x=" + x + ", y=" + y);
            }
        }, null);
        
        Log.d(TAG, "dispatchGesture (Click) 触发结果: " + dispatched);
    }

    /**
     * 模拟全局滑动事件（由 RustDesk 信令接收到远程滑动动作时调用）
     */
    @RequiresApi(api = Build.VERSION_CODES.N)
    public void simulateSwipe(float startX, float startY, float endX, float endY, long durationMs) {
        Path swipePath = new Path();
        swipePath.moveTo(startX, startY);
        swipePath.lineTo(endX, endY);
        GestureDescription.StrokeDescription swipeStroke = 
                new GestureDescription.StrokeDescription(swipePath, 0, durationMs);
        GestureDescription swipeBuilder = new GestureDescription.Builder().addStroke(swipeStroke).build();

        boolean dispatched = dispatchGesture(swipeBuilder, new GestureResultCallback() {
            @Override
            public void onCompleted(GestureDescription gestureDescription) {
                super.onCompleted(gestureDescription);
                Log.d(TAG, "模拟滑动成功");
            }

            @Override
            public void onCancelled(GestureDescription gestureDescription) {
                super.onCancelled(gestureDescription);
                Log.d(TAG, "模拟滑动取消");
            }
        }, null);

        Log.d(TAG, "dispatchGesture (Swipe) 触发结果: " + dispatched);
    }
}
