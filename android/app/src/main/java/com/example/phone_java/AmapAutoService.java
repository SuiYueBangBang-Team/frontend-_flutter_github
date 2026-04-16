package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import java.util.ArrayList;
import java.util.List;

/**
 * 高德地图自动化处理器 - 由 UnifiedAccessibilityService 调度
 */
public class AmapAutoService {

    private static final String TAG = "AmapAuto";
    private static final String AMAP_PACKAGE = "com.autonavi.minimap";

    private static final String ID_HOME_SEARCHBAR_BG = "com.autonavi.minimap:id/maphome_searchbar_bg";
    private static final String ID_SEARCH_INPUT = "com.autonavi.minimap:id/input_search";
    private static final String ID_SEARCH_BTN = "com.autonavi.minimap:id/btn_search";
    private static final String ID_NAVI_BTN = "com.autonavi.minimap:id/btn_navi";

    private static final int STEP_IDLE                = 0;
    private static final int STEP_CLICK_SEARCH_BOX    = 1;
    private static final int STEP_INPUT_DESTINATION   = 2;
    private static final int STEP_CLICK_SEARCH_BTN    = 3;
    private static final int STEP_CLICK_RESULT_ITEM   = 4;
    private static final int STEP_CLICK_GO_HERE      = 5;
    private static final int STEP_CONFIRM_NAVI        = 6;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetDestination = "";
    private long lastHandledRequestId = -1L;
    private long stepStartTime = 0L;
    private AccessibilityService serviceInstance;

    public void handleEvent(AccessibilityService service, AccessibilityEvent event) {
        this.serviceInstance = service;
        
        long pendingRequestId = getPendingRequestId(service);
        String pendingDestination = getPendingDestination(service);

        if (pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            if (!pendingDestination.isEmpty()) {
                targetDestination = pendingDestination;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                step = STEP_CLICK_SEARCH_BOX;
                Log.d(TAG, "========== 🗺️ 高德动作：去 " + targetDestination + " ==========");
            }
        }

        if (step == STEP_IDLE) return;

        if (System.currentTimeMillis() - stepStartTime > 15000) {
            Log.e(TAG, "超时卡死，重置");
            clearPendingTask(service);
            step = STEP_IDLE;
            return;
        }

        handler.removeCallbacks(stateMachineRunnable);
        handler.postDelayed(stateMachineRunnable, 600);
    }

    private final Runnable stateMachineRunnable = new Runnable() {
        @Override
        public void run() {
            if (serviceInstance == null) return;
            AccessibilityNodeInfo root = serviceInstance.getRootInActiveWindow();
            if (root == null) return;

            boolean success = false;
            switch (step) {
                case STEP_CLICK_SEARCH_BOX:
                    if (AccessibilityUtils.clickByViewId(root, ID_HOME_SEARCHBAR_BG) || AccessibilityUtils.clickByAnyText(root, "查找地点")) {
                        step = STEP_INPUT_DESTINATION;
                        success = true;
                        handler.postDelayed(this, 1000);
                        return;
                    }
                    break;
                case STEP_INPUT_DESTINATION:
                    AccessibilityNodeInfo input = AccessibilityUtils.findFirstNodeByViewId(root, ID_SEARCH_INPUT);
                    if (input == null) input = AccessibilityUtils.findFirstNodeByClass(root, "android.widget.EditText");
                    if (input != null && AccessibilityUtils.inputText(input, targetDestination)) {
                        step = STEP_CLICK_SEARCH_BTN;
                        success = true;
                        handler.postDelayed(this, 800);
                        return;
                    }
                    break;
                case STEP_CLICK_SEARCH_BTN:
                    if (AccessibilityUtils.clickByViewId(root, ID_SEARCH_BTN) || AccessibilityUtils.clickByAnyText(root, "搜索")) {
                        step = STEP_CLICK_RESULT_ITEM;
                        success = true;
                    }
                    break;
                case STEP_CLICK_RESULT_ITEM:
                    if (AccessibilityUtils.clickByAnyText(root, targetDestination)) {
                        step = STEP_CLICK_GO_HERE;
                        success = true;
                    }
                    break;
                case STEP_CLICK_GO_HERE:
                    if (AccessibilityUtils.clickByViewId(root, ID_NAVI_BTN) || AccessibilityUtils.clickByAnyText(root, "开始导航", "到这里去")) {
                        step = STEP_CONFIRM_NAVI;
                        success = true;
                    }
                    break;
                case STEP_CONFIRM_NAVI:
                    if (AccessibilityUtils.clickByAnyText(root, "开始导航", "确定")) {
                        step = STEP_IDLE;
                        clearPendingTask(serviceInstance);
                        success = true;
                    }
                    break;
            }

            if (!success && step != STEP_IDLE) {
                handler.postDelayed(this, 500);
            }
        }
    };

    private String getPendingDestination(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getString("amap_destination", "").trim();
    }
    private long getPendingRequestId(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getLong("amap_request_id", -1L);
    }
    private void clearPendingTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("amap_destination").remove("amap_request_id").apply();
    }
}