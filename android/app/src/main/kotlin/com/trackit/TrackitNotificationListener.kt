package com.trackit

import android.content.ComponentName
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** MVP parser: package IDs and formats are placeholders until real notification examples are supplied. */
class TrackitNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in SUPPORTED_PACKAGES) return
        val extras = sbn.notification.extras
        val text = listOf(
            extras.getCharSequence("android.title"),
            extras.getCharSequence("android.text"),
            extras.getCharSequence("android.bigText"),
        ).filterNotNull().joinToString(" ")
        val amount = AMOUNT.find(text)?.groupValues?.getOrNull(1)?.replace(".", "")?.replace(",", "")?.toLongOrNull() ?: return
        val merchant = MERCHANT.find(text)?.groupValues?.getOrNull(1)?.trim() ?: "Payment"
        val externalId = stableId(sbn.key, sbn.postTime, amount, merchant)
        TrackitNotificationQueue(this).add(Candidate(externalId, "digital", amount, merchant, sbn.postTime, sbn.packageName, 0.8))
    }

    companion object {
        // Replace placeholders with the exact package IDs used on the test device.
        val SUPPORTED_PACKAGES = setOf("com.example.qris", "com.example.bank")
        private val AMOUNT = Regex("(?:Rp\\.?\\s*)([0-9][0-9.,]*)", RegexOption.IGNORE_CASE)
        private val MERCHANT = Regex("(?:at|di|ke)\\s+([A-Za-z0-9 ._-]{2,50})", RegexOption.IGNORE_CASE)

        fun isEnabled(context: Context): Boolean {
            val expected = ComponentName(context, TrackitNotificationListener::class.java)
            return getEnabledListeners(context).any { it == expected }
        }

        private fun getEnabledListeners(context: Context): List<ComponentName> = ComponentName.unflattenFromString(
            android.provider.Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
        )?.let { listOf(it) } ?: emptyList()

        fun stableId(key: String, postTime: Long, amount: Long, merchant: String): String {
            val data = "$key|$postTime|$amount|${merchant.lowercase(Locale.ROOT)}"
            return MessageDigest.getInstance("SHA-256").digest(data.toByteArray()).joinToString("") { "%02x".format(it) }
        }
    }
}

data class Candidate(val externalId: String, val accountId: String, val amountMinor: Long, val merchant: String, val occurredAt: Long, val packageName: String, val confidence: Double) {
    fun toMap() = mapOf("externalId" to externalId, "accountId" to accountId, "amountMinor" to amountMinor, "merchant" to merchant, "occurredAt" to SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).format(Date(occurredAt)), "packageName" to packageName, "confidence" to confidence)
}
