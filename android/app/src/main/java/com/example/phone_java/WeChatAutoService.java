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

    // 核心节点 ID（均已通过 uiautomatorviewer 在真机上抓取确认）
    private static final String ID_SEARCH_ENTRY = "com.tencent.mm:id/jha";
    private static final String ID_SEARCH_INPUT = "com.tencent.mm:id/d98";
    private static final String ID_MORE_FUNCTION = "com.tencent.mm:id/bjz";
    private static final String ID_MAIN_MORE = "com.tencent.mm:id/jga";
    // 图片抓取：收付款菜单文字节点 resource-id="com.tencent.mm:id/obc"，text="收付款"
    private static final String ID_SCAN_MENU_TEXT = "com.tencent.mm:id/obc";
    private static final String ID_PAYMENT_TEXT   = "com.tencent.mm:id/obc"; // 收付款与扫一扫共用同一菜单列表项 ID
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
    // 💡 新增：微信付款码状态机步骤
    private static final int STEP_PAYMENT_MAIN_MORE   = 30; // 点击主界面「+」按钮
    private static final int STEP_PAYMENT_CLICK_ITEM  = 31; // 点击弹出菜单中「收付款」

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetContact = "";
    private String targetMessage = "";
    private long lastHandledRequestId = -1L;
    private long lastHandledScanRequestId = -1L;
    private long lastHandledPaymentRequestId = -1L;
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

        // 💡 新增：检测「微信付款码」任务
        long pendingPaymentId = getPendingPaymentRequestId(service);
        if (step == STEP_IDLE && pendingPaymentId > 0 && pendingPaymentId != lastHandledPaymentRequestId) {
            step = STEP_PAYMENT_MAIN_MORE;
            lastHandledPaymentRequestId = pendingPaymentId;
            stepStartTime = System.currentTimeMillis();
            Log.d(TAG, "========== 💳 微信动作：打开付款码 ==========");
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
            } else if (step == STEP_PAYMENT_MAIN_MORE || step == STEP_PAYMENT_CLICK_ITEM) {
                clearPendingPaymentTask(service);
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
                        // 关键：这里至少要延迟 800ms - 1000ms，等待面板完全弹出来
                        handler.postDelayed(stateMachineRunnable, 1000);
                        return;
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
                // 💡 新增：微信付款码自动化
                case STEP_PAYMENT_MAIN_MORE:
                    // 点击微信主界面底部「+」更多按钮（jga 为主页级别的更多，图片抓取确认）
                    if (AccessibilityUtils.clickByViewId(root, ID_MAIN_MORE) || AccessibilityUtils.clickByAnyDesc(root, "更多功能")) {
                        step = STEP_PAYMENT_CLICK_ITEM;
                        success = true;
                        handler.postDelayed(this, 700); // 等待弹出菜单展开
                        return;
                    }
                    break;
                case STEP_PAYMENT_CLICK_ITEM:
                    // 在弹出菜单中点击「收付款」（图片抓取：text="收付款"，resource-id obc）
                    if (clickWeChatPaymentMenuItem()) {
                        step = STEP_IDLE;
                        clearPendingPaymentTask(serviceInstance);
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

    /**
     * 核心改进：全窗口扫描 + 坐标模拟点击
     * 解决微信面板节点不可点击及 ID 混淆问题
     */
    private boolean forceClickPanelVideo() {
        if (serviceInstance == null) return false;

        // 1. 获取所有交互窗口（解决权限或弹窗导致的根节点偏移）
        List<AccessibilityWindowInfo> windows = serviceInstance.getWindows();
        if (windows == null) return false;

        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root == null) continue;

            // 2. 优先通过文字检索 "视频通话"
            List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText("视频通话");
            if (nodes != null && !nodes.isEmpty()) {
                for (AccessibilityNodeInfo node : nodes) {
                    // 获取节点在屏幕上的绝对坐标系 Rect
                    android.graphics.Rect rect = new android.graphics.Rect();
                    node.getBoundsInScreen(rect);

                    // 3. 执行物理层模拟点击，绕过所有 View 层的点击拦截
                    clickAt(rect.centerX(), rect.centerY());
                    Log.d(TAG, "已执行物理点击: " + rect.centerX() + "," + rect.centerY());
                    return true;
                }
            }

            // 4. 冗余方案：修正 ID 为 al2 (字母 L)
            List<AccessibilityNodeInfo> idNodes = root.findAccessibilityNodeInfosByViewId("com.tencent.mm:id/a12");
            if (idNodes != null && !idNodes.isEmpty()) {
                android.graphics.Rect rect = new android.graphics.Rect();
                idNodes.get(0).getBoundsInScreen(rect);
                clickAt(rect.centerX(), rect.centerY());
                return true;
            }
        }
        return false;
    }

    /**
     * 模拟物理点击的方法
     */
    private void clickAt(int x, int y) {
        if (serviceInstance == null) return;
        android.accessibilityservice.GestureDescription.Builder builder = new android.accessibilityservice.GestureDescription.Builder();
        android.graphics.Path path = new android.graphics.Path();
        path.moveTo(x, y);
        // 模拟手指点下去停留100毫秒再抬起
        builder.addStroke(new android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 100));
        serviceInstance.dispatchGesture(builder.build(), null, null);
    }

    /**
     * 这是一个核心工具方法，建议放在 AccessibilityUtils 里或者本类中
     * 它的作用就是实现 XPath 中 /ancestor::... 的逻辑，直到找到能点的地方
     */
    public static boolean clickNodeOrParent(AccessibilityNodeInfo node) {
        if (node == null) return false;
        if (node.isClickable()) {
            return node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
        } else {
            AccessibilityNodeInfo parent = node.getParent();
            if (parent != null) {
                boolean result = clickNodeOrParent(parent);
                // 必须要 recycle 掉 parent，否则会内存泄漏导致脚本变慢
                parent.recycle();
                return result;
            }
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

    /**
     * 在弹出菜单中点击「收付款」
     * 图片中抓取：text="收付款"，resource-id="com.tencent.mm:id/obc"（与扫一扫同一列表 ID，靠文字区分）
     * 策略1：遍历所有窗口按文字匹配
     * 策略2：遍历所有窗口按 ID 精确查找包含"收付款"文字的节点
     */
    private boolean clickWeChatPaymentMenuItem() {
        if (serviceInstance == null) return false;
        // 先尝试当前活跃窗口
        AccessibilityNodeInfo activeRoot = serviceInstance.getRootInActiveWindow();
        if (activeRoot != null) {
            if (AccessibilityUtils.clickByAnyText(activeRoot, "收付款", "付款")) return true;
        }
        // 再遍历全部窗口（弹出菜单可能是独立 window）
        List<AccessibilityWindowInfo> windows = serviceInstance.getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo root = window.getRoot();
            if (root == null) continue;
            if (AccessibilityUtils.clickByAnyText(root, "收付款", "付款")) return true;
            if (AccessibilityUtils.clickByAnyDesc(root, "收付款", "付款码")) return true;
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
    private long getPendingPaymentRequestId(Context context) {
        return context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).getLong("wechat_payment_request_id", -1L);
    }
    private void clearPendingScanTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("wechat_scan_request_id").apply();
    }
    private void clearPendingPaymentTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("wechat_payment_request_id").apply();
    }
    private void clearPendingTask(Context context) {
        context.getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE).edit().remove("wechat_contact").remove("wechat_message").remove("wechat_request_id").apply();
    }
}