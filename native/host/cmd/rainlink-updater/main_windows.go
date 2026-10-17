//go:build windows

// rainlink-updater accepts bounded local JSON over a private stdio pipe. No
// shell, URL, or arbitrary command is ever accepted.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"rainlink.local/host/internal/update"
)

func decode(line string, value any) error {
	decoder := json.NewDecoder(strings.NewReader(line))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("trailing input")
	}
	return nil
}

func run() error {
	input := make(chan string, 1)
	go func() {
		defer close(input)
		scanner := bufio.NewScanner(os.Stdin)
		scanner.Buffer(make([]byte, 1024), 16384)
		for scanner.Scan() {
			input <- scanner.Text()
		}
	}()
	var request update.Request
	select {
	case line, open := <-input:
		if !open || decode(line, &request) != nil {
			return errors.New("invalid request")
		}
	case <-time.After(30 * time.Second):
		return errors.New("request timed out")
	}
	lease, err := update.AcquireLock(request.Target)
	if err != nil {
		return err
	}
	defer lease.Close()
	parent, err := update.OpenParent(request)
	if err != nil {
		return err
	}
	defer parent.Close()
	prepareContext, cancelPrepare := context.WithTimeout(context.Background(), 2*time.Minute)
	transaction, err := update.Prepare(prepareContext, request)
	cancelPrepare()
	if err != nil {
		return err
	}
	if _, err := fmt.Fprintln(os.Stdout, `{"status":"ready"}`); err != nil {
		return errors.Join(err, transaction.Abort())
	}
	select {
	case line, open := <-input:
		var command struct {
			Command string `json:"command"`
		}
		if !open || decode(line, &command) != nil || command.Command != "commit" {
			cleanupErr := transaction.Abort()
			_, responseErr := fmt.Fprintln(os.Stdout, `{"status":"aborted"}`)
			return errors.Join(cleanupErr, responseErr)
		}
	case <-time.After(2 * time.Minute):
		return errors.Join(errors.New("preparation expired"), transaction.Abort())
	}
	// Commit only promises to wait for the app. An abort remains possible while
	// that process is alive (e.g. if destroying its window fails).
	waitContext, cancelWait := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancelWait()
	go func() {
		select {
		case line, open := <-input:
			if open && line == `{"command":"abort"}` {
				cancelWait()
			}
		case <-waitContext.Done():
		}
	}()
	if _, err := fmt.Fprintln(os.Stdout, `{"status":"committed"}`); err != nil {
		return errors.Join(err, transaction.Abort())
	}
	if err := parent.Wait(waitContext); err != nil {
		cleanupErr := transaction.Abort()
		_, responseErr := fmt.Fprintln(os.Stdout, `{"status":"aborted"}`)
		return errors.Join(err, cleanupErr, responseErr)
	}
	installContext, cancelInstall := context.WithTimeout(context.Background(), 45*time.Second)
	outcome, installErr := transaction.Apply(installContext, &update.ProcessRuntime{})
	cancelInstall()
	if outcome.Status == "installed" {
		consumeContext, cancelConsume := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancelConsume()
		return errors.Join(installErr, transaction.WaitConsumed(consumeContext))
	}
	return installErr
}

func main() {
	if err := run(); err != nil {
		// Paths, internal errors and user data stay out of process output.
		fmt.Fprintln(os.Stdout, `{"status":"failed"}`)
		os.Exit(1)
	}
}
