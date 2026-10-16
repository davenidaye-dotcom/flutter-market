package com.letou.letou_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.NetworkInterface

/**
 * 本机是否有 VPN。抓包软件的 VPN 模式（Reqable、HttpCanary 等）会建一张 TUN 虚拟网卡，
 * 把整机流量拽进去。检测到就让 App 不发包，抓包工具里连 CONNECT 都不会出现。
 *
 * 不判断 p2p：它是 Wi-Fi Direct 的接口名（p2p0），很多手机常驻，会误伤。
 */
object VpnCheck {

    private val vpnInterfacePrefixes = listOf("tun", "tap", "ppp", "ipsec", "utun")

    fun isActive(context: Context): Boolean {
        return hasVpnTransport(context) || hasVpnInterface()
    }

    @Suppress("DEPRECATION")
    private fun hasVpnTransport(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false
            // 只看当前默认网络会漏：VPN 起来之前的老网络仍可能是默认网络。逐个看。
            cm.allNetworks.any { network ->
                cm.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun hasVpnInterface(): Boolean {
        return try {
            val all = NetworkInterface.getNetworkInterfaces() ?: return false
            all.asSequence().any { ni ->
                ni.isUp && vpnInterfacePrefixes.any { ni.name.startsWith(it, ignoreCase = true) }
            }
        } catch (_: Exception) {
            false
        }
    }
}
