package io.ente.auth.watch

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import com.google.crypto.tink.integration.android.AndroidKeystore
import java.io.File
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

internal class ProtectedKeyStore(context: Context) {
    private val keyguard = context.getSystemService(KeyguardManager::class.java)
    private val file = DeviceFile(File(context.noBackupFilesDir, "watch/private-key"))
    private val alias = "io.ente.auth.watch.enrollment"
    private val associatedData = "io.ente.auth.watch.private-key/v1".toByteArray()

    fun read(): PrivateKey? {
        val data = file.read() ?: return null
        requireWatch(!keyguard.isDeviceLocked, "watchLocked")
        val plaintext = AndroidKeystore.getAead(alias).decrypt(data, associatedData)
        return try { PrivateKey.decode(plaintext) } finally { plaintext.fill(0) }
    }

    fun write(key: PrivateKey) {
        if (Build.VERSION.SDK_INT < 30) throw WatchException("secureStorageUnavailable")
        requireWatch(keyguard.isDeviceSecure && !keyguard.isDeviceLocked, "watchLocked")
        requireWatch(file.read() == null, "wrongEnrollment")
        AndroidKeystore.generateNewKeyWithSpec(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(36 * 60 * 60, KeyProperties.AUTH_DEVICE_CREDENTIAL)
            .setUnlockedDeviceRequired(true).build())
        try {
            val store = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val secret = store.getKey(alias, null) as SecretKey
            val info = SecretKeyFactory.getInstance(secret.algorithm, "AndroidKeyStore")
                .getKeySpec(secret, KeyInfo::class.java) as KeyInfo
            @Suppress("DEPRECATION")
            requireWatch(info.isInsideSecureHardware, "secureStorageUnavailable")
            val plaintext = key.encode()
            try { file.write(AndroidKeystore.getAead(alias).encrypt(plaintext, associatedData)) }
            finally { plaintext.fill(0) }
        } catch (error: Exception) {
            AndroidKeystore.deleteKey(alias)
            throw error
        }
    }

    fun remove() {
        AndroidKeystore.deleteKey(alias)
        file.remove()
    }
}
