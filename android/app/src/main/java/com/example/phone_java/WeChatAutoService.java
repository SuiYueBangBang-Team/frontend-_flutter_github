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
    /** 聊天页右下角加号面板用 */
    private static final String ID_MORE_FUNCTION = "com.tencent.mm:id/bjz";
    /** 微信首页（会话列表）右上角「更多功能」Button，content-desc 为「更多功能」 */
    private static final String ID_MAIN_MORE = "com.tencent.mm:id/jga";
    /** 首页 + 菜单中「扫一扫」文案；父行可选 n7g */
    private static final String ID_SCAN_MENU_TEXT = "com.tencent.mm:id/obc";
    private static final String ID_SCAN_MENU_ROW = "com.tencent.mm:id/n7g";
    // 发送区：输入框旁「发送」为 Button，resource-id 以 Appium/布局树为准（微信版本变更时需再抓）
    private static final String ID_SEND_BTN = "com.tencent.mm:id/bql";
    /** 发送按钮所在输入栏外层 LinearLayout，便于在子树内精确定位 */
    private static final String ID_SEND_BAR = "com.tencent.mm:id/bqn";

    // 状态机常量
    private static final int STEP_IDLE = 0;
    private static final int STEP_OPEN_SEARCH = 1;
    private static final int STEP_INPUT_CONTACT = 2;
    private static final int STEP_CLICK_CONTACT = 3;
    private static final int STEP_CLICK_PLUS = 4;
    private static final int STEP_CLICK_PANEL_VIDEO = 5;
    private static final int STEP_CLICK_POPUP_VOICE = 6;
    private static final int STEP_INPUT_MESSAGE = 7;   // 发消息：输入消息文字
    private static final int STEP_CLICK_SEND    = 8;   // 发消息：点击发送按钮
    /** 无障碍打开「扫一扫」：主界面点 + 菜单 */
    private static final int STEP_SCAN_MAIN_MORE = 20;
    private static final int STEP_SCAN_MENU_ITEM = 21;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private int step = STEP_IDLE;
    private String targetContact = "";
    private String targetMessage = "";
    private long lastHandledRequestId = -1L;
    private long lastHandledScanRequestId = -1L;
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
        Log.d(TAG, ">>> onAccessibilityEvent 触发: " + event);

        if (event == null || event.getPackageName() == null) {
            Log.w(TAG, "event 或 packageName 为 null，跳过");
            return;
        }
        if (!WECHAT_PACKAGE.contentEquals(event.getPackageName())) {
            Log.w(TAG, "不是微信的事件: " + event.getPackageName() + "，跳过");
            return;
        }

        long pendingRequestId = getPendingRequestId();
        String pendingContact = getPendingContact();
        String pendingMessage = getPendingMessage();

        Log.d(TAG, "当前 SharedPreferences 状态:");
        Log.d(TAG, "   - pendingRequestId: " + pendingRequestId);
        Log.d(TAG, "   - pendingContact: [" + pendingContact + "]");
        Log.d(TAG, "   - lastHandledRequestId: " + lastHandledRequestId);
        Log.d(TAG, "   - 当前 step: " + step);

        long pendingScanId = getPendingScanRequestId();
        if (step == STEP_IDLE && pendingScanId > 0 && pendingScanId != lastHandledScanRequestId) {
            step = STEP_SCAN_MAIN_MORE;
            lastHandledScanRequestId = pendingScanId;
            stepStartTime = System.currentTimeMillis();
            Log.d(TAG, "========== 📷 检测到新任务：微信扫一扫（无障碍） ==========");
        }

        if (step == STEP_IDLE && pendingRequestId > 0 && pendingRequestId != lastHandledRequestId) {
            if (!pendingContact.isEmpty()) {
                targetContact = pendingContact;
                targetMessage = pendingMessage;
                step = STEP_OPEN_SEARCH;
                lastHandledRequestId = pendingRequestId;
                stepStartTime = System.currentTimeMillis();
                if (!targetMessage.isEmpty()) {
                    Log.d(TAG, "========== 💬 检测到新任务：给 " + targetContact + " 发消息: " + targetMessage + " ==========");
                } else {
                    Log.d(TAG, "========== 📞 检测到新任务：拨打给 " + targetContact + " ==========");
                }
            }
        }

        if (step == STEP_IDLE) {
            Log.d(TAG, "当前 step 为 IDLE，不执行状态机");
            return;
        }

        if (System.currentTimeMillis() - stepStartTime > 15000) {
            Log.e(TAG, "步骤超时卡死，强制重置状态机！当前停留在 step=" + step);
            if (step == STEP_SCAN_MAIN_MORE || step == STEP_SCAN_MENU_ITEM) {
                clearPendingScanTask();
            } else {
                clearPendingTask();
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
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null) {
                if (step == STEP_SCAN_MAIN_MORE || step == STEP_SCAN_MENU_ITEM) {
                    handler.removeCallbacks(this);
                    handler.postDelayed(this, 500);
                    return;
                }
                if (step < STEP_CLICK_PANEL_VIDEO) return;
            }

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
                        // 关键分支：targetMessage 非空 → 发消息；空 → 打电话
                        if (!targetMessage.isEmpty()) {
                            step = STEP_INPUT_MESSAGE;
                        } else {
                            step = STEP_CLICK_PANEL_VIDEO;
                        }
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                    }
                    break;

                case STEP_INPUT_MESSAGE:
                    if (inputMessageText(root, targetMessage)) {
                        Log.d(TAG, "【5💬】成功在输入框填入消息：" + targetMessage);
                        step = STEP_CLICK_SEND;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 500);
                        return;
                    }
                    break;

                case STEP_CLICK_SEND:
                    if (clickSendButton(root)) {
                        Log.d(TAG, "【6💬】成功点击发送按钮！消息已发送，任务完成！");
                        step = STEP_IDLE;
                        clearPendingTask();
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

                case STEP_SCAN_MAIN_MORE:
                    if (clickMainPageMoreForScan(root)) {
                        Log.d(TAG, "【扫一扫-1】已点击首页「更多功能」");
                        step = STEP_SCAN_MENU_ITEM;
                        stepStartTime = System.currentTimeMillis();
                        success = true;
                        handler.postDelayed(this, 600);
                        return;
                    }
                    break;

                case STEP_SCAN_MENU_ITEM:
                    if (clickWeChatScanMenuItem()) {
                        Log.d(TAG, "【扫一扫-2】已点击「扫一扫」，任务完成");
                        step = STEP_IDLE;
                        clearPendingScanTask();
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

    private String getPendingMessage() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getString("wechat_message", "").trim();
    }

    private long getPendingRequestId() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getLong("wechat_request_id", -1L);
    }

    private long getPendingScanRequestId() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        return prefs.getLong("wechat_scan_request_id", -1L);
    }

    private void clearPendingScanTask() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        prefs.edit().remove("wechat_scan_request_id").apply();
    }

    private void clearPendingTask() {
        SharedPreferences prefs = getSharedPreferences("com.example.phone_java", Context.MODE_PRIVATE);
        prefs.edit()
                .remove("wechat_contact")
                .remove("wechat_message")
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

    /** 会话列表页右上角「更多功能」（与聊天页加号不同） */
    private boolean clickMainPageMoreForScan(AccessibilityNodeInfo root) {
        if (root == null) return false;
        Log.d(TAG, "【扫一扫-1】尝试点击首页「更多功能」加号");
        if (clickByViewId(root, ID_MAIN_MORE)) {
            Log.d(TAG, "【扫一扫-1】通过ID点击加号成功");
            return true;
        }
        if (clickByAnyDesc(root, "更多功能")) {
            Log.d(TAG, "【扫一扫-1】通过content-desc点击加号成功");
            return true;
        }
        Log.w(TAG, "【扫一扫-1】未找到加号节点，等待重试");
        return false;
    }

    /** + 菜单在独立窗口时遍历所有 Window，修复误点问题 */
    private boolean clickWeChatScanMenuItem() {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;

        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo windowRoot = window.getRoot();
            if (windowRoot == null) continue;

            // 🔴 第一步：优先精准匹配「扫一扫」文本，绝对不先点通用行ID！
            List<AccessibilityNodeInfo> scanTextNodes = windowRoot.findAccessibilityNodeInfosByText("扫一扫");
            if (scanTextNodes != null && !scanTextNodes.isEmpty()) {
                for (AccessibilityNodeInfo textNode : scanTextNodes) {
                    Log.d(TAG, "【扫一扫-2】匹配到「扫一扫」文本节点: " + textNode);
                    // 从文本节点向上找可点击的父行（n7g），只点这一行，不会误点其他
                    AccessibilityNodeInfo clickableParent = findClickableParent(textNode);
                    if (clickableParent != null) {
                        if (performClick(clickableParent)) {
                            Log.d(TAG, "【扫一扫-2】成功点击「扫一扫」文本对应的可点击父行");
                            return true;
                        }
                    }
                    // 兜底：直接点击文本节点本身
                    if (performClick(textNode)) {
                        Log.d(TAG, "【扫一扫-2】成功点击「扫一扫」文本节点");
                        return true;
                    }
                }
            }

            // 🟡 第二步：兜底匹配「扫一扫」专属ID（obc），只有文本匹配失败时才用
            List<AccessibilityNodeInfo> scanIdNodes = windowRoot.findAccessibilityNodeInfosByViewId(ID_SCAN_MENU_TEXT);
            if (scanIdNodes != null && !scanIdNodes.isEmpty()) {
                for (AccessibilityNodeInfo node : scanIdNodes) {
                    Log.d(TAG, "【扫一扫-2】匹配到「扫一扫」ID节点: " + node);
                    if (performClick(node)) {
                        Log.d(TAG, "【扫一扫-2】成功通过ID点击「扫一扫」");
                        return true;
                    }
                    // 向上找可点击父行兜底
                    AccessibilityNodeInfo clickableParent = findClickableParent(node);
                    if (clickableParent != null && performClick(clickableParent)) {
                        Log.d(TAG, "【扫一扫-2】成功通过ID父行点击「扫一扫」");
                        return true;
                    }
                }
            }

            // 🟢 第三步：绝对禁止优先匹配通用行ID n7g！只在文本/ID都失败时，兜底精准匹配
            List<AccessibilityNodeInfo> rowNodes = windowRoot.findAccessibilityNodeInfosByViewId(ID_SCAN_MENU_ROW);
            if (rowNodes != null && !rowNodes.isEmpty()) {
                for (AccessibilityNodeInfo row : rowNodes) {
                    // 遍历行的子节点，确认行内包含「扫一扫」文本，再点击
                    List<AccessibilityNodeInfo> childTexts = findNodesByAnyText(row, "扫一扫");
                    if (childTexts != null && !childTexts.isEmpty()) {
                        Log.d(TAG, "【扫一扫-2】匹配到包含「扫一扫」的行节点: " + row);
                        if (performClick(row)) {
                            Log.d(TAG, "【扫一扫-2】成功点击包含「扫一扫」的行");
                            return true;
                        }
                    }
                }
            }
        }
        Log.w(TAG, "【扫一扫-2】未找到「扫一扫」节点，等待重试");
        return false;
    }

    /** 从节点向上查找最近的可点击父节点（用于菜单项点击） */
    private AccessibilityNodeInfo findClickableParent(AccessibilityNodeInfo node) {
        if (node == null) return null;
        AccessibilityNodeInfo cur = node;
        while (cur != null) {
            if (cur.isClickable()) {
                return cur;
            }
            cur = cur.getParent();
        }
        return null; // 没找到可点击父节点，返回原节点兜底
    }

    private boolean clickByViewIdInAllWindows(String viewId) {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo windowRoot = window.getRoot();
            if (windowRoot != null && clickByViewId(windowRoot, viewId)) return true;
        }
        return false;
    }

    private boolean clickTextInAllWindows(String text) {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo windowRoot = window.getRoot();
            if (windowRoot != null && clickByAnyText(windowRoot, text)) return true;
        }
        return false;
    }

    /**
     * 发消息专用：在聊天输入框填入消息文字
     */
    private boolean inputMessageText(AccessibilityNodeInfo root, String message) {
        // 聊天输入框 ID 与搜索框相同（d98），优先按 ID 找，找不到再用 EditText 兜底
        AccessibilityNodeInfo input = findFirstNodeByViewId(root, ID_SEARCH_INPUT);
        if (input == null) {
            input = findFirstNodeByClass(root, "android.widget.EditText");
        }
        if (input == null) return false;

        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, message);
        return input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
    }

    /**
     * 发消息专用：点击发送按钮（优先 bql，再输入栏 bqn 内查找，最后跨窗口 + 冒泡点击）
     */
    private boolean clickSendButton(AccessibilityNodeInfo root) {
        if (root != null) {
            if (clickByViewId(root, ID_SEND_BTN)) return true;
            if (clickSendInsideSendBar(root)) return true;
            if (clickSendByTextPreferButton(root)) return true;
        }
        if (clickSendButtonInAllWindows()) return true;
        return false;
    }

    /** 在 com.tencent.mm:id/bqn 输入栏内找发送 Button（bql 或文案「发送」） */
    private boolean clickSendInsideSendBar(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> bars = root.findAccessibilityNodeInfosByViewId(ID_SEND_BAR);
        if (bars == null || bars.isEmpty()) return false;
        for (AccessibilityNodeInfo bar : bars) {
            List<AccessibilityNodeInfo> byId = bar.findAccessibilityNodeInfosByViewId(ID_SEND_BTN);
            if (byId != null) {
                for (AccessibilityNodeInfo n : byId) {
                    if (performClick(n) || forceBubbleClick(n)) return true;
                }
            }
            if (clickSendByTextPreferButton(bar)) return true;
        }
        return false;
    }

    /** 只点 class 含 Button 且 text 为「发送」的节点，避免点到其它含「发送」的文案 */
    private boolean clickSendByTextPreferButton(AccessibilityNodeInfo root) {
        List<AccessibilityNodeInfo> nodes = findNodesByAnyText(root, "发送");
        for (AccessibilityNodeInfo node : nodes) {
            CharSequence cls = node.getClassName();
            if (cls == null || !cls.toString().contains("Button")) continue;
            if (performClick(node) || forceBubbleClick(node)) return true;
        }
        for (AccessibilityNodeInfo node : nodes) {
            if (performClick(node) || forceBubbleClick(node)) return true;
        }
        return false;
    }

    /** 聊天页发送条有时不在 active window，遍历所有窗口 */
    private boolean clickSendButtonInAllWindows() {
        List<AccessibilityWindowInfo> windows = getWindows();
        if (windows == null) return false;
        for (AccessibilityWindowInfo window : windows) {
            AccessibilityNodeInfo windowRoot = window.getRoot();
            if (windowRoot == null) continue;
            if (clickByViewId(windowRoot, ID_SEND_BTN)) return true;
            if (clickSendInsideSendBar(windowRoot)) return true;
            if (clickSendByTextPreferButton(windowRoot)) return true;
        }
        return false;
    }

    /** 与视频面板类似：从节点向上每层尝试 ACTION_CLICK；仅当某次 performAction 成功时视为已点 */
    private boolean forceBubbleClick(AccessibilityNodeInfo node) {
        if (node == null) return false;
        boolean ok = false;
        AccessibilityNodeInfo cur = node;
        while (cur != null) {
            if (cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)) ok = true;
            if (cur.isClickable() && cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)) ok = true;
            cur = cur.getParent();
        }
        return ok;
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