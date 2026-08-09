package com.qobuzdl.app;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import android.view.KeyEvent;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity implements Runnable {
    private static final String APP_URL = "http://127.0.0.1:8765/";
    private static final int REQUEST_OPEN_FOLDER = 4201;
    private WebView webView;
    private Handler handler;

    public void onPageFinishedLoading() {
    }

    public void onPageFailedLoading() {
        handler.postDelayed(this, 1000);
    }

    @Override
    public void run() {
        webView.loadUrl(APP_URL);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        handler = new Handler(Looper.getMainLooper());
        webView = new WebView(this);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setMediaPlaybackRequiresUserGesture(false);

        webView.setWebViewClient(new AppWebViewClient(this));
        webView.addJavascriptInterface(new AndroidBridge(this), "AndroidBridge");

        setContentView(webView);
        webView.loadUrl(APP_URL);
    }

    public void openFolderPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        startActivityForResult(intent, REQUEST_OPEN_FOLDER);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_OPEN_FOLDER) {
            return;
        }
        String path = null;
        if (resultCode == RESULT_OK && data != null) {
            Uri treeUri = data.getData();
            path = resolveTreePath(treeUri);
        }
        deliverFolderPath(path);
    }

    private String resolveTreePath(Uri treeUri) {
        if (treeUri == null) {
            return null;
        }
        String docId = DocumentsContract.getTreeDocumentId(treeUri);
        if (docId == null) {
            return null;
        }
        int colon = docId.indexOf(':');
        String volume = colon >= 0 ? docId.substring(0, colon) : docId;
        String relative = colon >= 0 ? docId.substring(colon + 1) : "";
        if ("primary".equals(volume)) {
            String base = "/storage/emulated/0";
            return relative.isEmpty() ? base : base + "/" + relative;
        }
        // Non-primary volumes (SD cards, etc.) aren't reliably a plain path Termux
        // can write to without extra permissions; caller shows an error for this case.
        return null;
    }

    private void deliverFolderPath(String path) {
        final String js;
        if (path != null) {
            js = "window.__androidFolderPicked && window.__androidFolderPicked("
                    + org.json.JSONObject.quote(path) + ")";
        } else {
            js = "window.__androidFolderPicked && window.__androidFolderPicked(null)";
        }
        webView.post(new DeliverJs(webView, js));
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        webView.destroy();
        super.onDestroy();
    }
}
