package com.letou.letou_app

import android.content.Context
import android.os.Build
import java.io.File

/**
 * 云手机系统自己的文件或属性出现一项即拦截。
 * 真机上的控制端包名只计一项，必须再碰上系统特征才拦截。
 */
internal object CloudPhoneGate {
    private val guestFiles = listOf(
        "/system/etc/business-config.xml",
        "/etc/business-config.xml",
        "/system/bin/ldinit",
        "/system/bin/ldmountsf",
        "/system/priv-app/ldAppStore",
        "/system/bin/nox-prop",
        "/system/lib/libnoxspeedup.so",
        "/system/bin/microvirt-prop",
        "/system/lib/libdroid4x.so",
        "/system/bin/windroyed",
        "/system/bin/ttVM-prop",
        "/system/bin/duosconfig",
        "/system/etc/xxzs_prop.sh",
        "/system/priv-app/VMOS/vmos.prop",
        "/system/bin/androVM-prop",
        "/system/lib/libc_malloc_debug_qemu.so",
        "/dev/qemu_pipe",
        "/dev/socket/qemud",
        "/system/bin/qemu-props",
    )

    private val guestProps = listOf(
        "ro.com.cph.non_root",
        "ro.com.cph.notification_disable",
        "com.cph.mainkeys",
        "ro.com.cph.toast_enable",
        "ro.sys.cloud.android_id",
    )

    fun blocked(context: Context): Boolean {
        if (guestFiles.any { exists(it) }) return true
        if (prop("ro.kernel.qemu") == "1") return true
        if (prop("vmos.camera.enable") == "1") return true
        if (guestProps.any { prop(it).isNotEmpty() }) return true
        return marks(context).size >= 2
    }

    private fun marks(context: Context): Set<String> {
        val marks = LinkedHashSet<String>()
        val build = listOf(
            Build.FINGERPRINT,
            Build.MODEL,
            Build.MANUFACTURER,
            Build.BRAND,
            Build.DEVICE,
            Build.PRODUCT,
            Build.HARDWARE,
            Build.BOARD,
            Build.HOST,
        ).joinToString("\n").lowercase()

        if (build.contains("goldfish") || build.contains("ranchu") || build.contains("vbox") || build.contains("genymotion")) {
            marks.add("emulator-hardware")
        }
        if (build.contains("qemu")) marks.add("qemu")
        if (build.contains("redfinger")) marks.add("redfinger-build")
        if (build.contains("ddyun") || build.contains("duoduoyun")) marks.add("ddyun-build")
        if (build.contains("leidian") || build.contains("ldyuncs") || build.contains("ldyun") || build.contains("ldplayer")) {
            marks.add("ld-build")
        }
        if (build.contains("vmos")) marks.add("vmos-build")
        if (build.contains("monbox")) marks.add("cph-name")
        if (hasPkg(context, "com.redfinger.app") || hasPkg(context, "com.redfinger.global.agent1") ||
            hasPkg(context, "com.redfinger.business") || hasPkg(context, "com.cyjh.ddyun") ||
            hasPkg(context, "com.ld.dianquan")
        ) {
            marks.add("cloud-client")
        }
        return marks
    }

    private fun hasPkg(context: Context, name: String): Boolean {
        return try {
            context.packageManager.getPackageInfo(name, 0)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun prop(key: String): String {
        return try {
            val cls = Class.forName("android.os.SystemProperties")
            val method = cls.getMethod("get", String::class.java, String::class.java)
            (method.invoke(null, key, "") as? String)?.trim().orEmpty()
        } catch (_: Throwable) {
            ""
        }
    }

    private fun exists(path: String): Boolean = try {
        File(path).exists()
    } catch (_: Throwable) {
        false
    }
}
