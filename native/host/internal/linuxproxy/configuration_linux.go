//go:build linux && !android

package linuxproxy

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

func configRoot() (string, error) {
	root := os.Getenv("XDG_CONFIG_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		root = filepath.Join(home, ".config")
	}
	if !filepath.IsAbs(root) || strings.ContainsAny(root, "\x00\r\n") {
		return "", errors.New("invalid desktop configuration directory")
	}
	return filepath.Clean(root), nil
}

func configurationBinding(cascade bool) (string, error) {
	root, err := configRoot()
	if err != nil {
		return "", err
	}
	paths := []string{root}
	if cascade {
		directories := os.Getenv("XDG_CONFIG_DIRS")
		if directories == "" {
			directories = "/etc/xdg"
		}
		for _, directory := range filepath.SplitList(directories) {
			if !filepath.IsAbs(directory) || strings.ContainsAny(directory, "\x00\r\n") {
				return "", errors.New("invalid desktop default configuration directory")
			}
			paths = append(paths, filepath.Clean(directory))
		}
	}
	encoded, err := json.Marshal(paths)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}
