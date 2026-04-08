package com.example.phone_java.wxapi;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

import com.example.phone_java.BuildConfig;
import com.tencent.mm.opensdk.modelbase.BaseReq;
import com.tencent.mm.opensdk.modelbase.BaseResp;
import com.tencent.mm.opensdk.openapi.IWXAPI;
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler;
import com.tencent.mm.opensdk.openapi.WXAPIFactory;

/**
 * 微信 SDK 回调入口，包名与类名必须固定为「应用包名.wxapi.WXEntryActivity」。
 */
public class WXEntryActivity extends Activity implements IWXAPIEventHandler {

    private IWXAPI api;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String appId = BuildConfig.WECHAT_APP_ID;
        if (appId == null || appId.isEmpty()) {
            finish();
            return;
        }
        api = WXAPIFactory.createWXAPI(this, appId, false);
        try {
            api.handleIntent(getIntent(), this);
        } catch (Throwable t) {
            finish();
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (api != null) {
            api.handleIntent(intent, this);
        }
    }

    @Override
    public void onReq(BaseReq baseReq) {
        finish();
    }

    @Override
    public void onResp(BaseResp baseResp) {
        finish();
    }
}
