package com.commutescout.drive

import android.app.Application

class DriveApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Engine.init(this)
    }
}
