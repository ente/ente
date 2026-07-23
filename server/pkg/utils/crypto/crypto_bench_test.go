package crypto

import (
	"encoding/base64"
	"testing"

	"github.com/ente/museum/ente"
)

// Benchmark encryption operations

func BenchmarkEncryptLibsodium(b *testing.B) {
	benchmarkEncrypt(b, Encrypt)
}

func BenchmarkEncryptNative(b *testing.B) {
	benchmarkEncrypt(b, EncryptNative)
}

func benchmarkEncrypt(b *testing.B, encryptFunc func(string, []byte) (ente.EncryptionResult, error)) {
	sizes := []struct {
		name string
		size int
	}{
		{"Small_32B", 32},
		{"Medium_1KB", 1024},
		{"Large_10KB", 10240},
		{"XLarge_100KB", 102400},
		{"Huge_1MB", 1048576},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			data := generateLargeText(size.size)
			key := generateTestKey()

			b.SetBytes(int64(size.size))

			for b.Loop() {
				_, err := encryptFunc(data, key)
				if err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Benchmark decryption operations

func BenchmarkDecryptLibsodium(b *testing.B) {
	benchmarkDecrypt(b, Encrypt, Decrypt)
}

func BenchmarkDecryptNative(b *testing.B) {
	benchmarkDecrypt(b, EncryptNative, DecryptNative)
}

func benchmarkDecrypt(b *testing.B,
	encryptFunc func(string, []byte) (ente.EncryptionResult, error),
	decryptFunc func([]byte, []byte, []byte) (string, error)) {

	sizes := []struct {
		name string
		size int
	}{
		{"Small_32B", 32},
		{"Medium_1KB", 1024},
		{"Large_10KB", 10240},
		{"XLarge_100KB", 102400},
		{"Huge_1MB", 1048576},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			data := generateLargeText(size.size)
			key := generateTestKey()

			// Encrypt once for benchmark
			encResult, err := encryptFunc(data, key)
			if err != nil {
				b.Fatal(err)
			}

			cipher := encResult.Cipher
			nonce := encResult.Nonce

			b.SetBytes(int64(size.size))

			for b.Loop() {
				_, err := decryptFunc(cipher, key, nonce)
				if err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Benchmark hash operations

func BenchmarkHashLibsodium(b *testing.B) {
	benchmarkHash(b, GetHash)
}

func BenchmarkHashNative(b *testing.B) {
	benchmarkHash(b, GetHashNative)
}

func benchmarkHash(b *testing.B, hashFunc func(string, []byte) (string, error)) {
	sizes := []struct {
		name string
		size int
	}{
		{"Small_32B", 32},
		{"Medium_1KB", 1024},
		{"Large_10KB", 10240},
		{"XLarge_100KB", 102400},
		{"Huge_1MB", 1048576},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			data := generateLargeText(size.size)

			b.SetBytes(int64(size.size))

			for b.Loop() {
				_, err := hashFunc(data, nil)
				if err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Benchmark token encryption (sealed box)

func BenchmarkGetEncryptedTokenLibsodium(b *testing.B) {
	benchmarkGetEncryptedToken(b, GetEncryptedToken)
}

func BenchmarkGetEncryptedTokenNative(b *testing.B) {
	benchmarkGetEncryptedToken(b, GetEncryptedTokenNative)
}

func benchmarkGetEncryptedToken(b *testing.B, tokenFunc func(string, string) (string, error)) {
	// Generate test public key
	publicKey := make([]byte, 32)
	for i := range publicKey {
		publicKey[i] = byte(i * 3)
	}
	publicKeyB64 := base64.StdEncoding.EncodeToString(publicKey)

	sizes := []struct {
		name string
		size int
	}{
		{"Small_32B", 32},
		{"Medium_256B", 256},
		{"Large_1KB", 1024},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			tokenData := generateLargeText(size.size)
			token := base64.URLEncoding.EncodeToString([]byte(tokenData))

			b.SetBytes(int64(size.size))

			for b.Loop() {
				_, err := tokenFunc(token, publicKeyB64)
				if err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Combined encryption/decryption cycle benchmark

func BenchmarkFullCycleLibsodium(b *testing.B) {
	benchmarkFullCycle(b, Encrypt, Decrypt)
}

func BenchmarkFullCycleNative(b *testing.B) {
	benchmarkFullCycle(b, EncryptNative, DecryptNative)
}

func benchmarkFullCycle(b *testing.B,
	encryptFunc func(string, []byte) (ente.EncryptionResult, error),
	decryptFunc func([]byte, []byte, []byte) (string, error)) {

	sizes := []struct {
		name string
		size int
	}{
		{"Small_32B", 32},
		{"Medium_1KB", 1024},
		{"Large_10KB", 10240},
		{"XLarge_100KB", 102400},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			data := generateLargeText(size.size)
			key := generateTestKey()

			b.SetBytes(int64(size.size * 2)) // Count both encrypt and decrypt

			for b.Loop() {
				encResult, err := encryptFunc(data, key)
				if err != nil {
					b.Fatal(err)
				}

				cipher := encResult.Cipher
				nonce := encResult.Nonce

				_, err = decryptFunc(cipher, key, nonce)
				if err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

// Memory allocation benchmarks

func BenchmarkMemoryAllocLibsodium(b *testing.B) {
	b.ReportAllocs()
	data := generateLargeText(1024)
	key := generateTestKey()

	for b.Loop() {
		_, _ = Encrypt(data, key)
	}
}

func BenchmarkMemoryAllocNative(b *testing.B) {
	b.ReportAllocs()
	data := generateLargeText(1024)
	key := generateTestKey()

	for b.Loop() {
		_, _ = EncryptNative(data, key)
	}
}

// Parallel benchmarks to test concurrent performance

func BenchmarkParallelEncryptLibsodium(b *testing.B) {
	data := generateLargeText(1024)
	key := generateTestKey()

	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			_, _ = Encrypt(data, key)
		}
	})
}

func BenchmarkParallelEncryptNative(b *testing.B) {
	data := generateLargeText(1024)
	key := generateTestKey()

	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			_, _ = EncryptNative(data, key)
		}
	})
}
