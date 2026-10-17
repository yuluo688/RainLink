//go:build !windows

package update

import "os"

func noReparse(string) error { return nil }

func replaceStateFile(source, destination string, exclusive bool) error {
	if exclusive {
		if err := os.Link(source, destination); err != nil {
			return err
		}
		return os.Remove(source)
	}
	return os.Rename(source, destination)
}
