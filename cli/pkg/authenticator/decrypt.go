package authenticator

import (
	"encoding/json"
	"fmt"
	"github.com/ente/cli/internal"
	eCrypto "github.com/ente/cli/internal/crypto"
	"os"
)

type _Export struct {
	Version         int    `json:"version"`
	KDFParams       _KDF   `json:"kdfParams"`
	EncryptedData   string `json:"encryptedData"`
	EncryptionNonce string `json:"encryptionNonce"`
}

type _KDF struct {
	MemLimit int    `json:"memLimit"`
	OpsLimit int    `json:"opsLimit"`
	Salt     string `json:"salt"`
}

func DecryptExport(inputPath string, outputPath string, password string) error {
	exportFile, err := internal.ResolvePath(inputPath)
	if err != nil {
		return fmt.Errorf("error resolving exportFile path (in): %v", err)
	}
	outputFile, err := internal.ResolvePath(outputPath)
	if err != nil {
		return fmt.Errorf("error resolving outputFile path (out): %v", err)
	} // Implement your decryption logic here

	data, err := os.ReadFile(exportFile)
	if err != nil {
		return fmt.Errorf("error reading file: %v", err)
	}

	var export _Export
	if err := json.Unmarshal(data, &export); err != nil {
		return fmt.Errorf("error parsing JSON: %v", err)
	}

	if export.Version != 1 {
		return fmt.Errorf("unsupported export version: %d", export.Version)
	}

	if password == "" {
		password, err = internal.GetSensitiveField("Enter password to decrypt export")
		if err != nil {
			return err
		}
	}

	fmt.Printf("\n....")
	key, err := eCrypto.DeriveArgonKey(password, export.KDFParams.Salt, export.KDFParams.MemLimit, export.KDFParams.OpsLimit)
	if err != nil {
		return fmt.Errorf("error deriving key: %v", err)
	}

	_, decryptedData, err := eCrypto.DecryptChaChaBase64Auth(export.EncryptedData, key, export.EncryptionNonce)
	if err != nil {
		fmt.Printf("\nerror decrypting data %v", err)
		fmt.Println("\nPlease check your password and try again")
		return nil
	}

	if err := os.WriteFile(outputFile, decryptedData, 0644); err != nil {
		return fmt.Errorf("error writing file: %v", err)
	}

	fmt.Printf("\nExport decrypted successfully to %s\n", outputFile)
	return nil
}
