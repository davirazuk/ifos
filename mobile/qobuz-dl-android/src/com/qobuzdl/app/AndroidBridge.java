package com.qobuzdl.app;

import android.webkit.JavascriptInterface;

public class AndroidBridge {
    private final MainActivity activity;

    public AndroidBridge(MainActivity activity) {
        this.activity = activity;
    }

    @JavascriptInterface
    public void browseFolder() {
        activity.runOnUiThread(new OpenPicker(activity));
    }
}
