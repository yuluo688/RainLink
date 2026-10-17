// mobile_cgo_tool selects the reviewed cgo generator for mobile builds only.
package main

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "mobile cgo tool requires a Go tool command")
		os.Exit(2)
	}
	command := os.Args[1]
	if strings.TrimSuffix(filepath.Base(command), ".exe") == "cgo" {
		self, err := os.Executable()
		if err != nil {
			fmt.Fprintln(os.Stderr, "cannot locate the mobile cgo tool")
			os.Exit(2)
		}
		suffix := filepath.Ext(self)
		command = filepath.Join(filepath.Dir(self), "cgo"+suffix)
		if len(os.Args) == 3 && os.Args[2] == "-V=full" {
			binary, err := os.ReadFile(command)
			if err != nil {
				fmt.Fprintln(os.Stderr, "cannot read the mobile cgo tool")
				os.Exit(2)
			}
			// Keep generated objects from reusing a cache entry from stock cgo.
			fmt.Printf("cgo version devel rainlink-aligned buildID=%x\n", sha256.Sum256(binary))
			return
		}
	}
	process := exec.Command(command, os.Args[2:]...)
	process.Stdin, process.Stdout, process.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := process.Run(); err != nil {
		var failure *exec.ExitError
		if errors.As(err, &failure) {
			os.Exit(failure.ExitCode())
		}
		fmt.Fprintln(os.Stderr, "cannot start the mobile build tool")
		os.Exit(2)
	}
}
