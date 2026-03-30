package com.example.phone_java;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

public class WeChatAutoService extends AccessibilityService {

    private static final String TAG = "WeChatAuto";
    private static final String WECHAT_PACKAGE = "com.tencent.mm";

    // 核心节点 ID
    private static final String ID_SEARCH_ENTRY = "com.tencent.mm:id/jha";
    private static final String ID_SEARCH_INPUT = "com.tencent.mm:id/d98";
    private static final String ID_MORE_FUNCTION = "com.tencent.mm:id/bjz";

    // 状态机常量
    private static final int STEP_IDLE = 0;
    private static final int STEP_OPEN_SEARCH = 1;
    private static final int STEP_INPUT_CONTACT = 2;
    private static final int STEP_CLICK_CONTACT = 3;
    private static final int STEP_CLICK_PLUS = 4;
    private static final int STEP_CLICK_PANEL_VIDEO = 5;
    private static final int STEP_CLICK_POPUP_VOICE = 6;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetContact = "";
    private long lastHandledRequestId = -1L;
    private long stepStartTime = 0L;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.notificationTimeout = 100;
        info.packageNames = new String[]{WECHAT_PACKAGE};
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        setServiceInfo(info);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) return;
        if (!WECHAT_PACKAGE.contentEquals(event.getPackageName())) return;

        long pendingRequestId = getPendingRequestId();
        if (pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            String pendingContact = getPendingContact();
            if (!pendingContact.isEmpty()) {
                targetContact = pendingContact;
                step = STEP_OPEN_SEARCH;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                Log.d(TAG, "========== 开始新任务：拨打给 " + targetContact + " ==========");
            }
        }

        if (step == STEP_IDLE) return;

        if (System.currentTimeMillis() - stepStartTime > 15000) {
            Log.e(TAG, "步骤超时卡死，强制重置状态机！当前停留在 step=" + step);
            step = STEP_IDLE;
            clearPendingTask();
            return;
        }

        handler.removeCallbacks(stateMachineRunnable);
        handler.postDelayed(stateMachineRunnable, 500);
    }

    private final Runnable stateMachineRunnable = new Runnable() {
        @Override
        public void run() {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null && step < STEP_CLICK_PANEL_VIDEO) return;

            boolean success = false;

            switch (step) {
                case STEP_OPEN_SEARCH:
                    if (clickWeChatSearch(root)) {
                        Log.d(TAG, "【1】成功点击主页右上角搜索");
                        step = STEP_INPUT_CONTACT;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    }
                    break;

                case STEP_INPUT_CONTACT:
                    if (inputContactName(root, targetContact)) {
                        Log.d(TAG, "【2】成功在输入框填入联系人：" + targetContact);
                        step = STEP_CLICK_CONTACT;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 1000);
                        return;
                    }
                    break;

                case STEP_CLICK_CONTACT:
                    if (clickContactResult(root, targetContact)) {
                        Log.d(TAG, "【3】成功点击搜索结果，进入聊天界面");
                        step = STEP_CLICK_PLUS;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    }
                    break;

                case STEP_CLICK_PLUS:
                    if (clickMoreFunction(root)) {
                        Log.d(TAG, "【4】成功点击聊天页右下角的加号");
                        step = STEP_CLICK_PANEL_VIDEO;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    }
                    break;

                case STEP_CLICK_PANEL_VIDEO:
                    // 💡 第5步：直接动用“无差别暴力穿透点击”
                    if (forceClickPanelVideo()) {
                        Log.d(TAG, "【5】成功通过暴力穿透点击了 视频通话");
                        step = STEP_CLICK_POPUP_VOICE;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    }
                    break;

                case STEP_CLICK_POPUP_VOICE:
                    if (clickTextOrDescInAllWindows("语音通话", "语音聊天")) {
                        Log.d(TAG, "【6】成功点击弹窗中的 语音通话！任务完成！");
                        step = STEP_IDLE;
                        clearPendingTask();
                        success = true;
                    }
                    break;
            }

            if (!success && step != STEP_IDLE) {
                handler.removeCallbacks(this);
                handler.postDelayed(this, 500);
            }
        }
    };

    // ---------------------------------
    //         🔥 终极杀招：无差别暴力点击
    // ---------------------------------
    private boolean forceClickPanelVideo() {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;

        boolean isClicked = false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root == null) continue;

            // 找"视频通话"这几个字，或者找 a12 这个 id
            List<AccessibilityNodeInfo> targets = new ArrayList<>();
            List<AccessibilityNodeInfo> byText = root.findAccessibilityNodeInfosByText("视频通话");
            if (byText != null) targets.addAll(byText);

            List<AccessibilityNodeInfo> byId = root.findAccessibilityNodeInfosByViewId("com.tencent.mm:id/a12");
            if (byId != null) targets.addAll(byId);

            for (AccessibilityNodeInfo node : targets) {
                AccessibilityNodeInfo cur = node;
                // 从文字节点开始，一路向外层包装盒发送点击指令！不管它承不承认自己能点！
                while (cur != null) {
                    cur.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                    if (cur.isClickable()) {
                        cur.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                    }
                    cur = cur.getParent();
                }
                isClicked = true;
            }
        }
        return isClicked;
    }

    // ---------------------------------
    //         跨窗口天眼搜索工具
    // ---------------------------------
    private boolean clickTextOrDescInAllWindows(String... keywords) {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo windowRoot = window.getRoot();
            if (windowRoot != null) {
                if (clickByAnyText(windowRoot, keywords)) return true;
                if (clickByAnyDesc(windowRoot, keywords)) return true;
            }
        }
        return false;
    }

    @Override
    public void onInterrupt() {}

    // ---------------------------------
    //         SharedPreferences
    // ---------------------------------
    private String getPendingContact() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getString("wechat_contact", "").trim();
    }

    private long getPendingRequestId() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getLong("wechat_request_id", -1L);
    }

    private void clearPendingTask() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        prefs.edit()
                .remove("wechat_contact")
                .remove("wechat_request_id")
                .apply();
    }

    // ---------------------------------
    //         各个步骤的具体实现
    // ---------------------------------
    private boolean clickWeChatSearch(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_SEARCH_ENTRY)) return true;
        return clickByAnyDesc(root, "搜索");
    }

    private boolean inputContactName(AccessibilityNodeInfo root, String contact) {
        AccessibilityNodeInfo input = findFirstNodeByViewId(root, ID_SEARCH_INPUT);
        if (input == null) input = findFirstNodeByClass(root, "android.widget.EditText");
        if (input == null) return false;

        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, contact);
        return input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
    }

    private boolean clickContactResult(AccessibilityNodeInfo root, String contact) {
        List<AccessibilityNodeInfo> nodes = findNodesByAnyText(root, contact);
        for (AccessibilityNodeInfo node : nodes) {
            CharSequence className = node.getClassName();
            if (className != null && className.toString().contains("EditText")) {
                continue;
            }
            if (performClick(node)) return true;
        }
        return false;
    }

    private boolean clickMoreFunction(AccessibilityNodeInfo root) {
        if (clickByViewId(root, ID_MORE_FUNCTION)) return true;
        return clickByAnyDesc(root, "更多功能按钮，已折叠", "更多功能");
    }

    // ---------------------------------
    //         底层通用工具方法
    // ---------------------------------
    private boolean clickByAnyText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> nodes = findNodesByAnyText(root, texts);
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node)) return true;
        }
        return false;
    }

    private boolean clickByAnyDesc(AccessibilityNodeInfo root, String... descs) {
        List<AccessibilityNodeInfo> all = flatten(root);
        for (AccessibilityNodeInfo node : all) {
            CharSequence cd = node.getContentDescription();
            if (cd == null) continue;
            String value = cd.toString();
            for (String d : descs) {
                if (d != null && !d.isEmpty() && value.contains(d)) {
                    if (performClick(node)) return true;
                }
            }
        }
        return false;
    }

    private boolean clickByViewId(AccessibilityNodeInfo root, String viewId) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId(viewId);
        if (nodes == null || nodes.isEmpty()) return false;
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node)) return true;
        }
        return false;
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

    private List<AccessibilityNodeInfo> findNodesByAnyText(AccessibilityNodeInfo root, String... texts) {
        List<AccessibilityNodeInfo> result = new ArrayList<>();
        if (root == null) return result;
        for (String text : texts) {
            if (text == null || text.trim().isEmpty()) continue;
            List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(text);
            if (found != null && !found.isEmpty()) result.addAll(found);
        }
        return result;
    }

    private AccessibilityNodeInfo findFirstNodeByViewId(AccessibilityNodeInfo root, String viewId) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId(viewId);
        return (nodes != null && !nodes.isEmpty()) ? nodes.get(0) : null;
    }

    private AccessibilityNodeInfo findFirstNodeByClass(AccessibilityNodeInfo root, String className) {
        if (root == null) return null;
        Deque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            AccessibilityNodeInfo node = queue.poll();
            if (node == null) continue;
            CharSequence cls = node.getClassName();
            if (cls != null && className.contentEquals(cls)) return node;
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) queue.add(child);
            }
        }
        return null;
    }

    private List<AccessibilityNodeInfo> flatten(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> out = new ArrayList<>();
        if (root == null) return out;
        Deque<AccessibilityNodeInfo> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            AccessibilityNodeInfo node = queue.poll();
            if (node == null) continue;
            out.add(node);
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) queue.add(child);
            }
        }
        return out;
    }
}