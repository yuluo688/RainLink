// Package cli implements the host's bounded, one-shot diagnostic commands.
package cli

import (
	"encoding/json"
	"fmt"
	"io"

	"rainlink.local/host/internal/host"
)

// Run writes protocol results only to stdout and diagnostics only to stderr.
func Run(args []string, stdout, stderr io.Writer) int {
	if len(args) != 1 {
		fmt.Fprintln(stderr, "usage: rainlink-host status | --version")
		return 2
	}
	switch args[0] {
	case "status":
		if err := json.NewEncoder(stdout).Encode(host.Inspect()); err != nil {
			fmt.Fprintf(stderr, "encode host status: %v\n", err)
			return 1
		}
	case "--version":
		if _, err := fmt.Fprintf(stdout, "rainlink-host %s\n", host.Version); err != nil {
			fmt.Fprintf(stderr, "write host version: %v\n", err)
			return 1
		}
	default:
		// Do not echo arbitrary arguments that could contain configuration secrets.
		fmt.Fprintln(stderr, "unsupported command")
		return 2
	}
	return 0
}
