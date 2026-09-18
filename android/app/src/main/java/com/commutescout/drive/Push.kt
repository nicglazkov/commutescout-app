package com.commutescout.drive

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.JsonPrimitive

/**
 * Watch alerts and alerts ahead reach the phone through Firebase Cloud
 * Messaging. The device token is registered with the account on sign-in
 * and whenever Firebase rotates it, and forgotten on sign-out, so a
 * shared phone never keeps getting the previous account's alerts.
 */
class PushRegistrar(private val context: Context, private val account: Account) {
    companion object {
        private const val TAG = "Push"
        const val CHANNEL = "alerts"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) != null) return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Road alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Watch areas and hazards ahead"
                },
            )
        }
    }

    private val p = context.getSharedPreferences("push", Context.MODE_PRIVATE)

    /** On sign-in: the current token goes to the account. */
    suspend fun register() {
        val token = runCatching { FirebaseMessaging.getInstance().token.await() }.getOrNull() ?: return
        register(token)
    }

    suspend fun register(token: String) {
        val auth = account.token() ?: return
        val version = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: ""
        val body = """{"platform":"android","token":${JsonPrimitive(token)},"app_version":${JsonPrimitive(version)}}"""
        val (status, _) = runCatching { Backend.send("POST", "/api/me/devices", auth, body) }.getOrElse { return }
        if (status == 200) {
            p.edit().putString("registered", token).apply()
            Log.i(TAG, "registered with the account")
        } else {
            Log.w(TAG, "register: $status")
        }
    }

    /** Before sign-out: the account forgets this phone. */
    suspend fun forget() {
        val token = p.getString("registered", null) ?: return
        val auth = account.token() ?: return
        val body = """{"platform":"android","token":${JsonPrimitive(token)}}"""
        runCatching { Backend.send("DELETE", "/api/me/devices", auth, body) }
        p.edit().remove("registered").apply()
    }
}

class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        CoroutineScope(Dispatchers.IO).launch { Engine.push.register(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: "CommuteScout"
        val body = message.notification?.body ?: message.data["body"] ?: return
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            message.data["url"]?.let { putExtra("csUrl", it) }
        }
        val pending = PendingIntent.getActivity(
            this, body.hashCode(), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        PushRegistrar.ensureChannel(this)
        val n = NotificationCompat.Builder(this, PushRegistrar.CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        val allowed = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (allowed) NotificationManagerCompat.from(this).notify(body.hashCode(), n)
    }
}
