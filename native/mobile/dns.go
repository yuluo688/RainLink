package mobile

import (
	"context"
	"net"
	"syscall"
	"time"

	"github.com/sagernet/sing-box/experimental/libbox"
	"rainlink.local/host/mobileconfig"
)

// DNSProbe owns a cancellable, capture-free test of the selected DNS settings.
type DNSProbe struct {
	ctx      context.Context
	cancel   context.CancelFunc
	request  string
	platform libbox.PlatformInterface
}

// NewDNSProbe receives validated settings; Android replaces system mode with
// the actual physical network's DNS IP before calling this constructor.
func NewDNSProbe(request string, platform libbox.PlatformInterface) *DNSProbe {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	return &DNSProbe{ctx: ctx, cancel: cancel, request: request, platform: platform}
}

// Run returns real addresses from the configured resolver, never fixture values.
func (p *DNSProbe) Run() (string, error) {
	defer p.cancel()
	dialer := &net.Dialer{Timeout: 6 * time.Second, Control: func(network, address string, connection syscall.RawConn) error {
		var protected error
		if err := connection.Control(func(fd uintptr) { protected = p.platform.AutoDetectInterfaceControl(int32(fd)) }); err != nil {
			return err
		}
		return protected
	}}
	return mobileconfig.TestDNS(p.ctx, p.request, dialer)
}

// Cancel releases in-flight resolver/HTTPS requests without changing a session.
func (p *DNSProbe) Cancel() { p.cancel() }
