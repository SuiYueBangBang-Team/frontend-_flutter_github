package com.example.phone_java;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONObject;
import org.tensorflow.lite.Interpreter;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

/**
 * 训练模型管理器 - 负责从后端拉取新的 TFLite 模型并加载
 */
public class ModelManager {
    private static final String TAG = "ModelManager";
    private static final String BASE_URL = "http://10.96.97.231:9000/api/fraud/model";
    private static final String PREF_KEY_VERSION = "model_version";
    
    private final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .build();
            
    private Interpreter interpreter;
    private final Context context;

    public ModelManager(Context context) {
        this.context = context.getApplicationContext();
        loadLocalModelIfExist();
    }

    /**
     * 加载本地存储的模型
     */
    private void loadLocalModelIfExist() {
        File modelFile = new File(context.getFilesDir(), "fraud_model.tflite");
        if (modelFile.exists()) {
            try {
                interpreter = new Interpreter(modelFile);
                Log.i(TAG, "✅ 成功加载本地 TFLite 模型");
            } catch (Exception e) {
                Log.e(TAG, "❌ 加载本地模型失败", e);
            }
        }
    }

    /**
     * 检查并后台下载新模型
     */
    public void checkForUpdates() {
        Request request = new Request.Builder()
                .url(BASE_URL + "/version")
                .get()
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                Log.w(TAG, "检查模型更新失败: " + e.getMessage());
            }

            @Override
            public void onResponse(Call call, Response response) throws IOException {
                if (response.isSuccessful() && response.body() != null) {
                    try {
                        JSONObject json = new JSONObject(response.body().string());
                        if (json.getInt("code") == 200) {
                            long remoteVersion = json.getJSONObject("data").getLong("version");
                            SharedPreferences prefs = context.getSharedPreferences("ModelPrefs", Context.MODE_PRIVATE);
                            long localVersion = prefs.getLong(PREF_KEY_VERSION, 0);

                            if (remoteVersion > localVersion) {
                                Log.i(TAG, "发现新版本模型: " + remoteVersion + "，开始下载...");
                                downloadNewModel(remoteVersion);
                            }
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "解析版本信息失败", e);
                    }
                }
            }
        });
    }

    private void downloadNewModel(long version) {
        Request request = new Request.Builder()
                .url(BASE_URL + "/download")
                .get()
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                Log.e(TAG, "下载模型文件失败", e);
            }

            @Override
            public void onResponse(Call call, Response response) throws IOException {
                if (response.isSuccessful() && response.body() != null) {
                    File file = new File(context.getFilesDir(), "fraud_model.tflite.tmp");
                    try (InputStream is = response.body().byteStream();
                         FileOutputStream fos = new FileOutputStream(file)) {
                        byte[] buffer = new byte[8192];
                        int len;
                        while ((len = is.read(buffer)) != -1) {
                            fos.write(buffer, 0, len);
                        }
                        fos.flush();
                        
                        // 覆盖正式文件并更新版本
                        File target = new File(context.getFilesDir(), "fraud_model.tflite");
                        if (file.renameTo(target)) {
                            context.getSharedPreferences("ModelPrefs", Context.MODE_PRIVATE)
                                    .edit().putLong(PREF_KEY_VERSION, version).apply();
                            Log.i(TAG, "✅ 新模型下载并替换成功，版本: " + version);
                            loadLocalModelIfExist(); // 重新加载
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "保存模型文件异常", e);
                    }
                }
            }
        });
    }

    public Interpreter getInterpreter() {
        return interpreter;
    }
}
