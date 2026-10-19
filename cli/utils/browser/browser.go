package browser

import (
	"errors"
	"os/exec"
	"runtime"
	"strings"
)

func OpenURL(url string) error {
	var cmd string
	var args []string

	switch runtime.GOOS {
	case "windows":
		cmd = "cmd"
		args = []string{"/c", "start"}
	case "darwin":
		cmd = "open"
		args = []string{url}
	default: // "linux", "freebsd", "openbsd", "netbsd"
		if isWSL() {
			return errors.New("automatic browser opening is unavailable under WSL; open the printed URL manually")
		} else {
			cmd = "xdg-open"
			args = []string{url}
		}
	}
	if len(args) > 1 {
		// start treats its first quoted argument as a window title.
		args = append(args[:1], append([]string{""}, args[1:]...)...)
	}
	return exec.Command(cmd, args...).Start()
}

func isWSL() bool {
	releaseData, err := exec.Command("uname", "-r").Output()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(releaseData)), "microsoft")
}
