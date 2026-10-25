package com.commutescout.drive

import android.app.Application

class DriveApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Engine.init(this)
    }

    /** Neural voice engines hold 100 MB and more: they go when the system asks for memory. */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        Neural.trim(level)
    }
}
