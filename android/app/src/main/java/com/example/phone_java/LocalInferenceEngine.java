package com.example.phone_java;

import android.util.Log;
import org.tensorflow.lite.Interpreter;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * 本地推理引擎 - 将文本转换为张量并调用 TFLite 模型
 */
public class LocalInferenceEngine {
    private static final String TAG = "LocalInference";
    private static final int MAX_LEN = 50;

    public float predict(Interpreter interpreter, String text) {
        if (interpreter == null || text == null || text.isEmpty()) return 0;

        try {
            // 1. 简单的字符分词与编码 (需与 Python 脚本一致)
            // 真实场景下应下载并读取 tokenizer.json，这里示意性实现最常用的中文字符偏移
            float[][] input = new float[1][MAX_LEN];
            for (int i = 0; i < Math.min(text.length(), MAX_LEN); i++) {
                // 这里使用最简单的 utf-8 编码映射，实际中需与训练集 Vocab 对齐
                input[0][i] = (float) (text.charAt(i) % 1000); 
            }

            // 2. 准备输出
            float[][] output = new float[1][1];

            // 3. 执行推理
            interpreter.run(input, output);
            float score = output[0][0];
            Log.d(TAG, "本地模型评分: " + score + " for text: " + text);
            return score;

        } catch (Exception e) {
            Log.e(TAG, "本地推理异常", e);
            return 0;
        }
    }
}
