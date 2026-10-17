//go:build linux && !android

package linuxipc

import (
	"context"
	"errors"
	"fmt"
	"net"
)

// DialRootService connects to a pinned root-owned Unix socket beneath trusted
// directories. It follows the inspected inode through procfs, never a path
// reopened after inspection. The caller owns both returned resources.
func DialRootService(ctx context.Context, path string) (connection *net.UnixConn, peer *Peer, result error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	file, err := openRootPath(path, true)
	if err != nil {
		return nil, nil, err
	}
	defer func() {
		if err := file.Close(); err != nil {
			result = errors.Join(result, err)
			if peer != nil {
				result = errors.Join(result, peer.Close())
				peer = nil
			}
			if connection != nil {
				result = errors.Join(result, connection.Close())
				connection = nil
			}
		}
	}()
	var dialer net.Dialer
	transport, err := dialer.DialContext(ctx, "unix", fmt.Sprintf("/proc/self/fd/%d", file.Fd()))
	if err != nil {
		return nil, nil, err
	}
	var ok bool
	connection, ok = transport.(*net.UnixConn)
	if !ok {
		return nil, nil, errors.Join(errors.New("private transport is not a Unix stream"), transport.Close())
	}
	peer, err = InspectRootService(connection)
	if err != nil {
		return nil, nil, errors.Join(err, connection.Close())
	}
	if err = ctx.Err(); err != nil {
		return nil, nil, errors.Join(err, peer.Close(), connection.Close())
	}
	return connection, peer, nil
}
