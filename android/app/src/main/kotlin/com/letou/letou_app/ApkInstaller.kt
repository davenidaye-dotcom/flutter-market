package com.letou.letou_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import java.io.File

/**
 * 把已下载的安装包交给系统安装。用户点取消不算更新成功，不写本机版本。
 * 安装成功时立刻写入 Flutter 的 SharedPreferences，避免进程被换包杀掉后来不及记。
 */
object ApkInstaller {
    private const val prefName = "FlutterSharedPreferences"
    private const val prefKey = "flutter.builtin_app_version"

    @Volatile
    var sink: EventChannel.EventSink? = null

    @Volatile
    private var pendingVersion: String = ""

    fun openUnknownSources(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        )
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun canInstall(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return context.packageManager.canRequestPackageInstalls()
    }

    fun install(context: Context, apk: File, version: String) {
        if (!apk.isFile || apk.length() <= 0L) {
            throw IllegalStateException("安装包是空的")
        }
        pendingVersion = version.trim()
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setSize(apk.length())
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        var committed = false
        try {
            session.openWrite("base.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { input -> input.copyTo(out) }
                session.fsync(out)
            }
            val callback = Intent(context, ApkInstallReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pending = PendingIntent.getBroadcast(context, sessionId, callback, flags)
            session.commit(pending.intentSender)
            committed = true
        } finally {
            if (!committed) {
                session.abandon()
            }
            session.close()
        }
    }

    fun onStatus(context: Context, status: Int, intent: Intent) {
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = confirmIntent(intent)
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                }
                emit("confirm")
            }
            PackageInstaller.STATUS_SUCCESS -> {
                remember(context)
                emit("success")
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> emit("cancel")
            else -> emit("fail")
        }
    }

    private fun remember(context: Context) {
        val version = pendingVersion
        if (version.isEmpty()) return
        context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
            .edit()
            .putString(prefKey, version)
            .commit()
    }

    private fun emit(kind: String) {
        val target = sink ?: return
        Handler(Looper.getMainLooper()).post {
            try {
                target.success(kind)
            } catch (_: Exception) {
            }
        }
    }

    private fun confirmIntent(intent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
    }
}

class ApkInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        ApkInstaller.onStatus(context.applicationContext, status, intent)
    }
}
