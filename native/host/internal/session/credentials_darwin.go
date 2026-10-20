package session

import (
	"context"
	"os"
	"path/filepath"

	"rainlink.local/host/internal/securestore"
)

func macCredentialStore() securestore.Store {
	executable, err := os.Executable()
	if err != nil {
		return securestore.NewMacStore("")
	}
	return securestore.NewMacStore(filepath.Join(filepath.Dir(executable), "rainlink-keychain"))
}

func seal(ctx context.Context, plain []byte, id string) (string, error) {
	return macCredentialStore().Seal(ctx, plain, id)
}

func unseal(ctx context.Context, cipher, id string) ([]byte, error) {
	return macCredentialStore().Unseal(ctx, cipher, id)
}
