package dev.rainlink.rainlink.core

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Ciphertext stays in SQLite; its non-exportable key stays in Android Keystore. */
internal class AndroidSecretStore {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Synchronized
    private fun key(): SecretKey {
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build())
        }.generateKey()
    }

    fun protect(id: String, credentials: JSONObject): String {
        validateId(id)
        val value = JSONObject()
        for (field in FIELDS) {
            val input = if (credentials.has(field)) credentials.get(field) else ""
            require(input is String) { "凭据格式无效" }
            val text = input
            require(text.toByteArray(Charsets.UTF_8).size <= MAX_FIELD_LENGTH) { "凭据超过长度限制" }
            value.put(field, text)
        }
        val plain = value.toString().toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            cipher.updateAAD(aad(id))
            return PREFIX + Base64.encodeToString(cipher.iv + cipher.doFinal(plain), Base64.NO_WRAP)
        } finally {
            plain.fill(0)
        }
    }

    fun reveal(id: String, sealed: String): JSONObject {
        validateId(id)
        require(sealed.startsWith(PREFIX) && sealed.length <= MAX_CIPHER_LENGTH) { "凭据格式无效" }
        val bytes = Base64.decode(sealed.substring(PREFIX.length), Base64.NO_WRAP)
        require(bytes.size >= IV_LENGTH + 16) { "凭据格式无效" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, IV_LENGTH)))
        cipher.updateAAD(aad(id))
        val plain = cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH)
        try {
            return JSONObject(String(plain, Charsets.UTF_8)).also { result ->
                require(FIELDS.all { result.get(it) is String && result.getString(it).toByteArray(Charsets.UTF_8).size <= MAX_FIELD_LENGTH })
            }
        } finally {
            plain.fill(0)
        }
    }

    /** Decrypt only recognized node positions; never walk arbitrary user JSON. */
    fun prepare(request: JSONObject): String {
        val secrets = JSONObject()
        fun node(value: JSONObject) {
            val id = value.getString("id")
            val sealed = value.optString("credential", "")
            if (sealed.isNotEmpty()) secrets.put(sealed, reveal(id, sealed))
        }
        fun target(value: JSONObject) {
            value.optJSONObject("node")?.let(::node)
            value.optJSONObject("chain")?.getJSONArray("hops")?.let { hops ->
                require(hops.length() in 2..5) { "代理链须包含 2–5 个节点" }
                for (index in 0 until hops.length()) node(hops.getJSONObject(index))
            }
        }
        target(request)
        request.optJSONObject("routing")?.optJSONArray("outbounds")?.let { outbounds ->
            require(outbounds.length() <= 32) { "规则出站数量超出限制" }
            for (index in 0 until outbounds.length()) target(outbounds.getJSONObject(index))
        }
        request.put("secrets", secrets)
        return request.toString()
    }

    private fun validateId(id: String) = require(ID.matches(id)) { "凭据标识无效" }
    private fun aad(id: String) = "RainLink:credentials:v1:$id".toByteArray(Charsets.UTF_8)

    companion object {
        private const val KEY_ALIAS = "RainLink.credentials.v1"
        private const val PREFIX = "rlk1."
        private const val IV_LENGTH = 12
        private const val MAX_FIELD_LENGTH = 4096
        private const val MAX_CIPHER_LENGTH = 98304
        private val ID = Regex("^[a-zA-Z0-9_-]{1,128}$")
        private val FIELDS = listOf("username", "password", "obfsPassword")
    }
}
