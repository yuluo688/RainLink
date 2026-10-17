//go:build linux && !android

package linuxipc

import (
	"errors"
	"testing"
)

func TestPermissionCommandHasFixedMethodsAndExactEnvelope(t *testing.T) {
	for _, raw := range []string{
		`{"version":1,"id":1,"method":"start","payload":{"tun":true}}`,
		`{"version":1,"id":2,"method":"stop"}`,
		`{"version":1,"id":1,"method":"idle"}`,
		`{"version":1,"id":1,"method":"hello"}`,
		`{"version":1,"id":1,"method":"hello-logs"}`,
	} {
		if _, err := ParseCommand([]byte(raw)); err != nil {
			t.Fatal("valid controlled command rejected", err)
		}
	}
	for _, raw := range []string{
		`null`, `[]`, `{}`, `{"version":2,"id":1,"method":"stop"}`,
		`{"version":1,"id":0,"method":"stop"}`, `{"version":1,"id":2147483648,"method":"stop"}`,
		`{"version":1,"id":1.5,"method":"stop"}`, `{"version":1,"ID":1,"method":"stop"}`,
		`{"version":1,"id":1,"id":2,"method":"stop"}`, `{"version":1,"id":1,"method":"run","payload":{"path":"/tmp/untrusted"}}`,
		`{"version":1,"id":1,"method":"start"}`, `{"version":1,"id":1,"method":"start","payload":null}`,
		`{"version":1,"id":1,"method":"start","payload":[]}`, `{"version":1,"id":1,"method":"stop","payload":{}}`,
		`{"version":1,"id":1,"method":"stop","uid":0}`, `{"version":1,"id":1,"method":"stop"} {}`,
		`{"version":1,"id":1,"method":"idle","payload":{}}`, `{"version":1,"id":1,"method":"recover"}`,
		`{"version":1,"id":1,"method":"hello","payload":{}}`,
		`{"version":1,"id":1,"method":"hello-logs","payload":{}}`,
	} {
		if _, err := ParseCommand([]byte(raw)); !errors.Is(err, ErrCommand) {
			t.Fatal("unexpected command accepted", err)
		}
	}
}
