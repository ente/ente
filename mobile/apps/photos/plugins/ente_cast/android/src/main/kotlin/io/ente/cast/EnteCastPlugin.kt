package io.ente.cast

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.security.Signature
import java.security.interfaces.RSAPublicKey
import java.security.cert.CertPathValidator
import java.security.cert.CertificateFactory
import java.security.cert.PKIXParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509Certificate

class EnteCastPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var multicastChannel: MethodChannel
    private lateinit var authChannel: MethodChannel
    private lateinit var lock: WifiManager.MulticastLock
    private var holderCount = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val wifiManager = binding.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        lock = wifiManager.createMulticastLock("ente_cast_discovery").apply {
            setReferenceCounted(false)
        }
        multicastChannel = MethodChannel(binding.binaryMessenger, MULTICAST_CHANNEL)
        multicastChannel.setMethodCallHandler(this)
        authChannel = MethodChannel(binding.binaryMessenger, AUTH_CHANNEL)
        authChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                if (holderCount == 0) {
                    lock.acquire()
                }
                holderCount++
                result.success(null)
            }
            "release" -> {
                if (holderCount > 0 && --holderCount == 0 && lock.isHeld) {
                    lock.release()
                }
                result.success(null)
            }
            "verifyDeviceCredentials" -> {
                try {
                    verifyDeviceCredentials(call)
                    result.success(null)
                } catch (error: Exception) {
                    result.error(
                        "CAST_AUTH_FAILED",
                        error.message ?: "Cast device authentication failed",
                        null,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        multicastChannel.setMethodCallHandler(null)
        authChannel.setMethodCallHandler(null)
        holderCount = 0
        if (lock.isHeld) {
            lock.release()
        }
    }

    private fun verifyDeviceCredentials(call: MethodCall) {
        val certificateFactory = CertificateFactory.getInstance("X.509")
        val leaf = certificateFactory.parseCertificate(call.bytes("clientAuthCertificate"))
        val rootBytes = call.byteArrays("trustAnchors")
        val roots = rootBytes.map { certificateFactory.parseCertificate(it) }
        require(roots.isNotEmpty()) { "Cast trust store is empty" }

        val intermediates = call.byteArrays("intermediateCertificates")
            .filterNot { candidate -> rootBytes.any(candidate::contentEquals) }
            .map { certificateFactory.parseCertificate(it) }
        val certificatePath = certificateFactory.generateCertPath(
            listOf(leaf) + intermediates,
        )
        val parameters = PKIXParameters(
            roots.mapTo(mutableSetOf()) { TrustAnchor(it, null) },
        ).apply {
            isRevocationEnabled = false
        }
        CertPathValidator.getInstance("PKIX").validate(certificatePath, parameters)

        leaf.checkValidity()
        require(leaf.basicConstraints < 0) {
            "Cast device authentication certificate must not be a CA"
        }
        require(leaf.keyUsage?.firstOrNull() == true) {
            "Cast device certificate cannot sign"
        }
        val extendedKeyUsage = leaf.extendedKeyUsage
        require(extendedKeyUsage?.contains(CLIENT_AUTH_OID) == true) {
            "Cast device certificate is not valid for client authentication"
        }
        val publicKey = leaf.publicKey
        require(publicKey is RSAPublicKey) {
            "Cast device authentication key is not RSA"
        }
        require(publicKey.modulus.bitLength() >= MIN_RSA_KEY_BITS) {
            "Cast device authentication key is too small"
        }

        val verifier = Signature.getInstance(
            when (call.argument<Int>("hashAlgorithm")) {
                HASH_SHA1 -> "SHA1withRSA"
                HASH_SHA256 -> "SHA256withRSA"
                else -> throw IllegalArgumentException(
                    "Unsupported Cast signature hash algorithm",
                )
            },
        )
        verifier.initVerify(publicKey)
        verifier.update(call.bytes("signatureInput"))
        require(verifier.verify(call.bytes("signature"))) {
            "Cast device signature is invalid"
        }
    }

    private fun CertificateFactory.parseCertificate(bytes: ByteArray): X509Certificate {
        return generateCertificate(ByteArrayInputStream(bytes)) as X509Certificate
    }

    private fun MethodCall.bytes(name: String): ByteArray {
        return argument<ByteArray>(name)
            ?: throw IllegalArgumentException("Missing $name")
    }

    private fun MethodCall.byteArrays(name: String): List<ByteArray> {
        val values = argument<List<*>>(name)
            ?: throw IllegalArgumentException("Missing $name")
        return values.map {
            it as? ByteArray
                ?: throw IllegalArgumentException("$name contains a non-byte value")
        }
    }

    private companion object {
        const val MULTICAST_CHANNEL = "io.ente.cast/multicast"
        const val AUTH_CHANNEL = "io.ente.cast/auth"
        const val HASH_SHA1 = 0
        const val HASH_SHA256 = 1
        const val MIN_RSA_KEY_BITS = 2048
        const val CLIENT_AUTH_OID = "1.3.6.1.5.5.7.3.2"
    }
}
