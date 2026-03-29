package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

public class WeChatAutoService extends AccessibilityService {

    private static final String WECHAT_PACKAGE = "com.tencent.mm";

    private static final int STEP_IDLE = 0;
    private static final int STEP_CLICK_SEARCH = 1;
    private static final int STEP_INPUT_CONTACT = 2;
    private static final int STEP_OPEN_CHAT = 3;
    private static final int STEP_OPEN_MORE_PANEL = 4;
    private static final int STEP_CLICK_AUDIO_VIDEO = 5;
    private static final int STEP_CLICK_VOICE_CALL = 6;
    private static final int STEP_DONE = 7;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int currentStep = STEP_IDLE;
    private String targetContact = "";
    private long lastActionTime = 0L;
    private long lastHandledRequestId = -1L;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.notificationTimeout = 120;
        info.packageNames = new String[]{WECHAT_PACKAGE};
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        setServiceInfo(info);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) {
            return;
        }
        if (!WECHAT_PACKAGE.contentEquals(event.getPackageName())) {
            return;
        }

        long pendingRequestId = getPendingRequestId();
        if (pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            String pendingContact = getPendingContact();
            if (!pendingContact.isEmpty()) {
                targetContact = pendingContact;
                currentStep = STEP_CLICK_SEARCH;
                lastHandledRequestId = pendingRequestId;
                lastActionTime = 0L;
            }
        }

        if (currentStep == STEP_IDLE) {
            return;
        }

        long now = System.currentTimeMillis();
        if (now - lastActionTime < 350) {
            return;
        }

        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) {
            return;
        }

        switch (currentStep) {
            case STEP_CLICK_SEARCH:
                if (clickByAnyText(root, "搜索", "Search")) {
                    currentStep = STEP_INPUT_CONTACT;
                    markAction();
                }
                break;

            case STEP_INPUT_CONTACT:
                if (setTextToFirstInput(root, targetContact)) {
                    currentStep = STEP_OPEN_CHAT;
                    markAction();
                    delayClickContact();
                }
                break;

            case STEP_OPEN_CHAT:
                if (clickByAnyText(root, targetContact)) {
                    currentStep = STEP_OPEN_MORE_PANEL;
                    markAction();
                }
                break;

            case STEP_OPEN_MORE_PANEL:
                if (clickByAnyText(root, "更多功能按钮", "更多功能", "更多", "+")) {
                    currentStep = STEP_CLICK_AUDIO_VIDEO;
                    markAction();
                }
                break;

            case STEP_CLICK_AUDIO_VIDEO:
                if (clickByAnyText(root, "音视频通话", "视频通话", "音视频")) {
                    currentStep = STEP_CLICK_VOICE_CALL;
                    markAction();
                }
                break;

            case STEP_CLICK_VOICE_CALL:
                if (clickByAnyText(root, "语音通话", "语音聊天")) {
                    currentStep = STEP_DONE;
                    markAction();
                    clearPendingContact();
                    resetLater();
                }
                break;

            default:
                break;
        }
    }

    @Override
    public void onInterrupt() {
        // no-op
    }

    private void markAction() {
        lastActionTime = System.currentTimeMillis();
    }

    private void delayClickContact() {
        handler.postDelayed(() -> {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null || currentStep != STEP_OPEN_CHAT) {
                return;
            }
            if (clickByAnyText(root, targetContact)) {
                currentStep = STEP_OPEN_MORE_PANEL;
                markAction();
            }
        }, 700);
    }

    private void resetLater() {
        handler.postDelayed(() -> {
            currentStep = STEP_IDLE;
            targetContact = "";
        }, 1200);
    }

    private String getPendingContact() {
        SharedPreferences prefs = getSharedPreferences(MainActivity.PREF_NAME, Context.MODE_PRIVATE);
        String value = prefs.getString(MainActivity.KEY_WECHAT_CONTACT, "");
        return value == null ? "" : value.trim();
    }

    private long getPendingRequestId() {
        SharedPreferences prefs = getSharedPreferences(MainActivity.PREF_NAME, Context.MODE_PRIVATE);
        return prefs.getLong(MainActivity.KEY_WECHAT_REQUEST_ID, -1L);
    }

    private void clearPendingContact() {
        SharedPreferences prefs = getSharedPreferences(MainActivity.PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .remove(MainActivity.KEY_WECHAT_CONTACT)
                .remove(MainActivity.KEY_WECHAT_REQUEST_ID)
                .apply();
    }

    private boolean setTextToFirstInput(AccessibilityNodeInfo root, String text) {
        AccessibilityNodeInfo input = findFirstNodeByClass(root, "android.widget.EditText");
        if (input == null) {
            List<AccessibilityNodeInfo> hintNodes = findNodesByAnyText(root, "搜索", "Search");
            if (!hintNodes.isEmpty()) {
                for (AccessibilityNodeInfo node : hintNodes) {
                    AccessibilityNodeInfo candidate = findFirstNodeByClass(node, "android.widget.EditText");
                    if (candidate != null) {
                        input = candidate;
                        break;
                    }
                }
            }
        }
        if (input == null) {
            return false;
        }
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
        boolean ok = input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        if (!ok) {
            input.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
            ok = input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
        }
        return ok;
    }

    private boolean clickByAnyText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> nodes = findNodesByAnyText(root, texts);
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node)) {
                return true;
            }
        }
        return false;
    }

    private List<AccessibilityNodeInfo> findNodesByAnyText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> result = new ArrayList<>();
        if (root == null) {
            return result;
        }
        for (String text : texts) {
            if (text == null || text.trim().isEmpty()) {
                continue;
            }
            List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(text);
            if (found != null && !found.isEmpty()) {
                result.addAll(found);
            }
        }
        return result;
    }

    private AccessibilityNodeInfo findFirstNodeByClass(AccessibilityNodeInfo root, String className) {
        if (root == null) {
            return null;
        }
        Deque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            AccessibilityNodeInfo node = queue.poll();
            if (node == null) {
                continue;
            }
            CharSequence cls = node.getClassName();
            if (cls != null && className.contentEquals(cls)) {
                return node;
            }
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) {
                    queue.add(child);
                }
            }
        }
        return null;
    }

    private boolean performClick(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo cur = node;
        while (cur != null) {
            if (cur.isClickable()) {
                return cur.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            }
            cur = cur.getParent();
        }
        return false;
    }
}
