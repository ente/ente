package internal

import (
	"bufio"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/ente/cli/internal/api"
	"golang.org/x/term"
)

func GetSensitiveField(label string) (string, error) {
	fmt.Printf("%s: ", label)
	input, err := term.ReadPassword(int(os.Stdin.Fd()))
	if err != nil {
		return "", err
	}
	return string(input), nil
}

func GetUserInput(label string) (string, error) {
	fmt.Printf("%s: ", label)
	var input string
	reader := bufio.NewReader(os.Stdin)
	input, err := reader.ReadString('\n')
	//_, err := fmt.Scanln(&input)
	if err != nil {
		return "", err
	}
	input = strings.TrimSpace(input)
	if input == "" {
		return "", errors.New("input cannot be empty")
	}
	return input, nil
}

func WaitForEnter(prompt string) error {
	fmt.Println(prompt)
	// Create a new reader from standard input.
	reader := bufio.NewReader(os.Stdin)
	_, err := reader.ReadString('\n')
	if err != nil {
		return err
	}
	return nil
}

func GetAppType() api.App {
	for {
		app, err := GetUserInput("Enter app type (default: photos)")
		if err != nil {
			fmt.Printf("Use default app type: %s\n", api.AppPhotos)
			return api.AppPhotos
		}
		switch app {
		case "photos":
			return api.AppPhotos
		case "auth":
			return api.AppAuth
		case "locker":
			return api.AppLocker
		case "":
			return api.AppPhotos
		default:
			fmt.Println("invalid app type")
			continue
		}
	}
}

func GetCode(promptText string, length int) (string, error) {
	for {
		ott, err := GetUserInput(promptText)
		if err != nil {
			return "", err
		}
		if ott == "" {
			log.Fatal("no OTP entered")
			return "", errors.New("no OTP entered")
		}
		if ott == "c" {
			return "", errors.New("OTP entry cancelled")
		}
		if len(ott) != length {
			fmt.Printf("OTP must be %d digits", length)
			continue
		}
		return ott, nil
	}
}

// parseStorageSize parses a string representing a storage size (e.g., "500MB", "2GB") into bytes.
func parseStorageSize(input string) (int64, error) {
	units := map[string]int64{
		"MB": 1 << 20,
		"GB": 1 << 30,
		"TB": 1 << 40,
	}
	re := regexp.MustCompile(`(?i)^(\d+(?:\.\d+)?)(MB|GB|TB)$`)
	matches := re.FindStringSubmatch(input)

	if matches == nil {
		return 0, errors.New("invalid format")
	}

	number, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return 0, fmt.Errorf("invalid number: %s", matches[1])
	}

	unit := strings.ToUpper(matches[2])
	bytes := int64(number * float64(units[unit]))

	return bytes, nil
}

func ConfirmAction(promptText string) (bool, error) {
	for {
		input, err := GetUserInput(promptText)
		if err != nil {
			return false, err
		}
		if input == "" {
			log.Fatal("No input entered")
			return false, errors.New("invalid input. Please enter 'y' or 'n'")
		}
		if input == "c" {
			return false, errors.New("cancelled")
		}
		if input == "y" {
			return true, nil
		}
		if input == "n" {
			return false, nil
		}
		fmt.Println("Invalid input. Please enter 'y' or 'n'.")
	}
}

// GetStorageSize prompts the user for a storage size and returns the size in bytes.
func GetStorageSize(promptText string) (int64, error) {
	for {
		input, err := GetUserInput(promptText)
		if err != nil {
			return 0, err
		}
		if input == "" {
			log.Fatal("No storage size entered")
			return 0, errors.New("no storage size entered")
		}
		if input == "c" {
			return 0, errors.New("storage size entry cancelled")
		}

		bytes, err := parseStorageSize(input)
		if err != nil {
			fmt.Println("Invalid storage size format. Please use a valid format like '500MB', '2GB'.")
			continue
		}

		return bytes, nil
	}
}

func GetExportDir() string {
	for {
		exportDir, err := GetUserInput("Enter export directory")
		if err != nil {
			log.Printf("invalid export directory input: %s\n", err)
			return ""
		}
		if exportDir == "" {
			log.Printf("invalid export directory: %s\n", err)
			continue
		}
		exportDir, err = ResolvePath(exportDir)
		if err != nil {
			log.Printf("invalid export directory: %s\n", err)
			continue
		}
		_, err = ValidateDirForWrite(exportDir)
		if err != nil {
			log.Printf("invalid export directory: %s\n", err)
			continue
		}

		return exportDir
	}
}

func ValidateDirForWrite(dir string) (bool, error) {
	// Check if the path exists
	fileInfo, err := os.Stat(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return false, fmt.Errorf("path does not exist: %s", dir)
		}
		return false, err
	}

	// Check if the path is a directory
	if !fileInfo.IsDir() {
		return false, fmt.Errorf("path is not a directory")
	}

	// Check for write permission
	// Check for write permission by creating a temp file
	tempFile, err := os.CreateTemp(dir, "write_test_")
	if err != nil {
		return false, fmt.Errorf("write permission denied: %v", err)
	}

	if tempErr := tempFile.Close(); tempErr != nil {
		return false, fmt.Errorf("failed to close temp file: %v", tempErr)
	}
	if tempErr := os.Remove(tempFile.Name()); tempErr != nil {
		return false, fmt.Errorf("failed to remove temp file: %v", tempErr)
	}

	return true, nil
}

func ResolvePath(path string) (string, error) {
	// Expand home directory if path starts with ~
	if strings.HasPrefix(path, "~") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		if len(path) == 1 {
			path = home
		} else if strings.HasPrefix(path, "~/") {
			path = filepath.Join(home, path[2:])
		}
	}

	// Convert to absolute path
	absPath, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}

	return absPath, nil
}
