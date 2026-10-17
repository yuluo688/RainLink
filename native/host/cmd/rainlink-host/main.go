package main

import (
	"fmt"
	"os"
	"strconv"

	"rainlink.local/host/internal/cli"
	"rainlink.local/host/internal/coreprocess"
	"rainlink.local/host/internal/session"
)

func main() {
	if len(os.Args) == 2 && (os.Args[1] == "install-tun" || os.Args[1] == "uninstall-tun" || os.Args[1] == "recover-tun-install") {
		if err := manageTUNInstallation(os.Args[1]); err != nil {
			fmt.Fprintln(os.Stderr, "TUN service installation:", err)
			os.Exit(1)
		}
		fmt.Fprintln(os.Stdout, "TUN service installation operation completed")
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "serve-tun" {
		if err := runTUNService(); err != nil {
			fmt.Fprintln(os.Stderr, "TUN permission session closed with a transport, core, or recovery error")
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 2 && (os.Args[1] == "recover-tun" || os.Args[1] == "recover-tun-service") {
		if err := recoverTUNService(os.Args[1] == "recover-tun-service"); err != nil {
			fmt.Fprintln(os.Stderr, "TUN recovery remains pending")
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 5 && os.Args[1] == "watch-tun" {
		if err := runTUNWatcher(os.Args[2:]); err != nil {
			// Watchdog errors contain resource identities only, never core config.
			fmt.Fprintln(os.Stderr, "TUN watchdog:", err)
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 4 && os.Args[1] == "tun-core" {
		pid, err := strconv.Atoi(os.Args[3])
		if err != nil || pid < 1 {
			os.Exit(2)
		}
		if err = coreprocess.RunElevated(os.Args[2], pid); err != nil {
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "serve-test" {
		if err := session.ServeIsolated(os.Stdin, os.Stdout, session.CorePath()); err != nil {
			fmt.Fprintln(os.Stderr, "isolated test closed with a cleanup or transport error")
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "serve" {
		if err := session.Serve(os.Stdin, os.Stdout, session.CorePath(), ""); err != nil {
			fmt.Fprintln(os.Stderr, "session closed with a recovery or transport error")
			os.Exit(1)
		}
		return
	}
	if len(os.Args) == 4 && os.Args[1] == "watch-proxy" {
		pid, err := strconv.Atoi(os.Args[3])
		if err != nil || pid < 1 {
			os.Exit(2)
		}
		if err = session.WatchProxy(os.Args[2], pid); err != nil {
			os.Exit(1)
		}
		return
	}
	os.Exit(cli.Run(os.Args[1:], os.Stdout, os.Stderr))
}
