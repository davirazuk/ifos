package com.qobuzdl.app;

import android.webkit.WebView;

public class DeliverJs implements Runnable {
    private final WebView webView;
    private final String js;

    public DeliverJs(WebView webView, String js) {
        this.webView = webView;
        this.js = js;
    }

    @Override
    public void run() {
        webView.evaluateJavascript(js, null);
    }
}
