// Package tunconfig defines the addresses shared by the controlled compiler
// and platform-specific TUN resource recovery.
package tunconfig

const (
	// IPv4Address is the interface address, including its prefix length.
	IPv4Address = "172.29.255.1/30"
	// IPv6Address captures literal IPv6 traffic even with IPv6 DNS disabled.
	IPv6Address = "fdfe:dcba:9876::1/126"
	// RuleProtocol distinguishes managed Linux rules during kernel deletion.
	// The locked Linux core uses the same explicit nonzero protocol.
	RuleProtocol = 242
)
