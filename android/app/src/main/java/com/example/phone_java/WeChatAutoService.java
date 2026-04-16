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
 * 微信自动化处理器 - 由 UnifiedAccessibilityService 调度
 */
public class WeChatAutoService {

    private static final String TAG = "WeChatAuto";
    private static final String WECHAT_PACKAGE = "com.tencent.mm";

    // 核心节点 ID
    private static final String ID_SEARCH_ENTRY = "com.tencent.mm:id/jha";
    private static final String ID_SEARCH_INPUT = "com.tencent.mm:id/d98";
    private static final String ID_MORE_FUNCTION = "com.tencent.mm:id/bjz";
    private static final String ID_MAIN_MORE = "com.tencent.mm:id/jga";
    private static final String ID_SCAN_MENU_TEXT = "com.tencent.mm:id/obc";
    private static final String ID_SCAN_MENU_ROW = "com.tencent.mm:id/n7g";
    private static final String ID_SEND_BTN = "com.tencent.mm:id/bql";
    private static final String ID_SEND_BAR = "com.tencent.mm:id/bqn";

    // 状态机常量
    private static final int STEP_IDLE = 0;
    private static final int STEP_OPEN_SEARCH = 1;
    private static final int STEP_INPUT_CONTACT = 2;
    private static final int STEP_CLICK_CONTACT = 3;
    private static final int STEP_CLICK_PLUS = 4;
    private static final int STEP_INPUT_MESSAGE = 7;
    private static final int STEP_CLICK_SEND    = 8;
    private static final int STEP_CLICK_PANEL_VIDEO = 5;
    private static final int STEP_CLICK_POPUP_VOICE = 6;
    private static final int STEP_SCAN_MAIN_MORE = 20;
    private static final int STEP_SCAN_MENU_ITEM = 21;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetContact = "";
    private String targetMessage = "";
    private long lastHandledRequestId = -1L;
    private long lastHandledScanRequestId = -1L;
    private long stepStartTime = 0L;
    private AccessibilityService serviceInstance;

    public void handleEvent(AccessibilityService service, AccessibilityEvent event) {
        this.serviceInstance = service;
        
        long pendingRequestId = getPendingRequestId(service);
        String pendingContact = getPendingContact(service);
        String pendingMessage = getPendingMessage(service);

        long pendingScanId = getPendingScanRequestId(service);
        if (step == STEP_IDLE && pendingScanId > 0 && pendingScanId != lastHandledScanRequestId) {
            step = STEP_SCAN_MAIN_MORE;
            lastHandledScanRequestId = pendingScanId;
            stepStartTime = System.currentTimeMillis();
            Log.d(TAG, "========== 📷 微信动作：扫一扫 ==========");
        }

        if (step == STEP_IDLE && pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            if (!pendingContact.isEmpty()) {
                targetContact = pendingContact;
                targetMessage = pendingMessage;
                step = STEP_OPEN_SEARCH;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                Log.d(TAG, "========== 💬 微信动作：发消息/通话 ==========");
            }
        }

        if (step == STEP_IDLE) return;

        if (System.currentTimeMillis() - stepStartTime > 15000) {
            Log.e(TAG, "超时卡死，重置");
            if (step == STEP_SCAN_MAIN_MORE || step == STEP_SCAN_MENU_ITEM) {
                clearPendingScanTask(service);
            } else {
                clearPendingTask(service);
            }
            step = STEP_IDLE;
            return;
        }

        handler.removeCallbacks(stateMachineRunnable);
        handler.postDelayed(stateMachineRunnable, 500);
    }

    private final Runnable stateMachineRunnable = new Runnable() {
        @Override
        public void run() {
            if (serviceInstance == null) return;
            AccessibilityNodeInfo root = serviceInstance.getRootInActiveWindow();
            if (root == null) {
                if (step == STEP_SCAN_MAIN_MORE || step == STEP_SCAN_MENU_ITEM) {
                    handler.postDelayed(this, 500);
                }
                return;
            }

            boolean success = false;
            switch (step) {
                case STEP_OPEN_SEARCH:
                    if (AccessibilityUtils.clickByViewId(root, ID_SEARCH_ENTRY) || AccessibilityUtils.clickByAnyDesc(root, "搜索")) {
                        step = STEP_INPUT_CONTACT;
                        success = true;
                    }
                    break;
                case STEP_INPUT_CONTACT:
                    AccessibilityNodeInfo input = AccessibilityUtils.findFirstNodeByViewId(root, ID_SEARCH_INPUT);
                    if (input == null) input = AccessibilityUtils.findFirstNodeByClass(root, "android.widget.EditText");
                    if (input != null && AccessibilityUtils.inputText(input, targetContact)) {
                        step = STEP_CLICK_CONTACT;
                        success = true;
                        handler.postDelayed(this, 1000);
                        return;
                    }
                    break;
                case STEP_CLICK_CONTACT:
                    if (clickContactResult(root, targetContact)) {
                        step = STEP_CLICK_PLUS;
                        success = true;
                    }
                    break;
                case STEP_CLICK_PLUS:
                    if (AccessibilityUtils.clickByViewId(root, ID_MORE_FUNCTION) || AccessibilityUtils.clickByAnyDesc(root, "更多功能")) {
                        step = targetMessage.isEmpty() ? STEP_CLICK_PANEL_VIDEO : STEP_INPUT_MESSAGE;
                        success = true;
                    }
                    break;
                case STEP_INPUT_MESSAGE:
                    AccessibilityNodeInfo msgInput = AccessibilityUtils.findFirstNodeByViewId(root, ID_SEARCH_INPUT);
                    if (msgInput == null) msgInput = AccessibilityUtils.findFirstNodeByClass(root, "android.widget.EditText");
                    if (msgInput != null && AccessibilityUtils.inputText(msgInput, targetMessage)) {
                        step = STEP_CLICK_SEND;
                        success = true;
                        handler.postDelayed(this, 500);
                        return;
                    }
                    break;
                case STEP_CLICK_SEND:
                    if (clickSendButton(root)) {
                        step = STEP_IDLE;
                        clearPendingTask(serviceInstance);
                        success = true;
                    }
                    break;
                case STEP_CLICK_PANEL_VIDEO:
                    if (forceClickPanelVideo()) {
                        step = STEP_CLICK_POPUP_VOICE;
                        success = true;
                    }
                    break;
                case STEP_CLICK_POPUP_VOICE:
                    if (clickTextOrDescInAllWindows("语音通话", "语音聊天")) {
                        step = STEP_IDLE;
                        clearPendingTask(serviceInstance);
                        success = true;
                    }
                    break;
                case STEP_SCAN_MAIN_MORE:
                    if (AccessibilityUtils.clickByViewId(root, ID_MAIN_MORE) || AccessibilityUtils.clickByAnyDesc(root, "更多功能")) {
                        step = STEP_SCAN_MENU_ITEM;
                        success = true;
                        handler.postDelayed(this, 600);
                        return;
                    }
                    break;
                case STEP_SCAN_MENU_ITEM:
                    if (clickWeChatScanMenuItem()) {
                        step = STEP_IDLE;
                        clearPendingScanTask(serviceInstance);
                        success = true;
                    }
                    break;
            }

            if (!success && step != STEP_IDLE) {
                handler.postDelayed(this, 500);
            }
        }
    };

    private boolean clickContactResult(AccessibilityNodeInfo root, String contact) {
        List<AccessibilityNodeInfo> nodes = AccessibilityUtils.findNodesByAnyText(root, contact);
        for (AccessibilityNodeInfo node : nodes) {
            String cls = node.getClassName() != null ? node.getClassName().toString() : "";
            if (cls.contains("EditText")) continue;
            if (AccessibilityUtils.performClick(node)) return true;
        }
        return false;
    }

    private boolean clickSendButton(AccessibilityNodeInfo root) {
        if (AccessibilityUtils.clickByViewId(root, ID_SEND_BTN)) return true;
        List<AccessibilityNodeInfo> nodes = AccessibilityUtils.findNodesByAnyText(root, "发送");
        for (AccessibilityNodeInfo node : nodes) {
            if (AccessibilityUtils.performClick(node)) return true;
        }
        return false;
    }

    private boolean forceClickPanelVideo() {
        if (serviceInstance == null) return false;
        List<AccessibilityWindowInfo> windows = serviceInstance.getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root == null) continue;
            if (AccessibilityUtils.clickByAnyText(root, "视频通话") || AccessibilityUtils.clickByViewId(root, "com.tencent.mm:id/a12")) return true;
        }
        return false;
    }

    private boolean clickTextOrDescInAllWindows(String... keywords) {
        if (serviceInstance == null) return false;
        List<AccessibilityWindowInfo> windows = serviceInstance.getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root != null) {
                if (AccessibilityUtils.clickByAnyText(root, keywords) || AccessibilityUtils.clickByAnyDesc(root, keywords)) return true;
            }
        }
        return false;
    }

    private boolean clickWeChatScanMenuItem() {
        if (serviceInstance == null) return false;
        List<AccessibilityWindowInfo> windows = serviceInstance.getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root == null) continue;
            if (AccessibilityUtils.clickByAnyText(root, "扫一扫") || AccessibilityUtils.clickByViewId(root, ID_SCAN_MENU_TEXT)) return true;
        }
        return false;
    }

    private String getPendingContact(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getString("wechat_contact", "").trim();
    }
    private String getPendingMessage(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getString("wechat_message", "").trim();
    }
    private long getPendingRequestId(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getLong("wechat_request_id", -1L);
    }
    private long getPendingScanRequestId(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getLong("wechat_scan_request_id", -1L);
    }
    private void clearPendingScanTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("wechat_scan_request_id").apply();
    }
    private void clearPendingTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("wechat_contact").remove("wechat_message").remove("wechat_request_id").apply();
    }
}