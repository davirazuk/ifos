package com.qobuzdl.app;

public class OpenPicker implements Runnable {
    private final MainActivity activity;

    public OpenPicker(MainActivity activity) {
        this.activity = activity;
    }

    @Override
    public void run() {
        activity.openFolderPicker();
    }
}
