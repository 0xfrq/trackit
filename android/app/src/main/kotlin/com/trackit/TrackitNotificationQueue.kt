package com.trackit

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class TrackitNotificationQueue(private val context: Context) {
    private val prefs = context.getSharedPreferences("trackit_queue", Context.MODE_PRIVATE)
    private val alias = "trackit.notification.queue"

    fun read(): List<Candidate> {
        val encoded = prefs.getString("items", null) ?: return emptyList()
        return runCatching {
            val json = JSONArray(decrypt(encoded))
            (0 until json.length()).map { item ->
                val value = json.getJSONObject(item)
                Candidate(value.getString("externalId"), value.getString("accountId"), value.getLong("amountMinor"), value.getString("merchant"), value.getLong("occurredAt"), value.getString("packageName"), value.getDouble("confidence"))
            }
        }.getOrDefault(emptyList())
    }

    @Synchronized fun add(candidate: Candidate) {
        val items = read().filterNot { it.externalId == candidate.externalId } + candidate
        val json = JSONArray().apply { items.forEach { put(JSONObject().apply {
            put("externalId", it.externalId); put("accountId", it.accountId); put("amountMinor", it.amountMinor); put("merchant", it.merchant); put("occurredAt", it.occurredAt); put("packageName", it.packageName); put("confidence", it.confidence)
        }) } }
        prefs.edit().putString("items", encrypt(json.toString())).apply()
    }

    @Synchronized fun remove(externalId: String) {
        val items = read().filterNot { it.externalId == externalId }
        val json = JSONArray().apply { items.forEach { put(JSONObject().apply {
            put("externalId", it.externalId); put("accountId", it.accountId); put("amountMinor", it.amountMinor); put("merchant", it.merchant); put("occurredAt", it.occurredAt); put("packageName", it.packageName); put("confidence", it.confidence)
        }) } }
        prefs.edit().putString("items", encrypt(json.toString())).apply()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
            init(android.security.keystore.KeyGenParameterSpec.Builder(alias, android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)), Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val bytes = Base64.decode(value, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), StandardCharsets.UTF_8)
    }
}
