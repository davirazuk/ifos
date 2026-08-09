package com.qobuzdl.app;

import android.webkit.WebView;
import android.webkit.WebViewClient;

public class AppWebViewClient extends WebViewClient {
    private final MainActivity activity;

    public AppWebViewClient(MainActivity activity) {
        this.activity = activity;
    }

    @Override
    public void onPageFinished(WebView view, String url) {
        activity.onPageFinishedLoading();
    }

    @Override
    public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
        activity.onPageFailedLoading();
    }
}
