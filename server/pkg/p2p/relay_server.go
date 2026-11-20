package p2p

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"

	"github.com/antigravity/antigravity-mobile/server/pkg/pairing"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"
	ma "github.com/multiformats/go-multiaddr"
)

// RelayConfig configures a self-hosted agy-relay Circuit Relay v2 + AutoNAT server.
type RelayConfig struct {
	IdentityPath string
	ListenAddrs  []string
	AllowedPeers []string // Optional PeerID ACL; if EnableACL is false and empty, relays for any peer.
	EnableACL    bool     // Enforce fail-closed ACL even when AllowedPeers starts empty.
	Infinite     bool
}

type peerACL struct {
	mu      sync.RWMutex
	allowed map[peer.ID]struct{}
}

func parsePeerIDMap(ids []string) (map[peer.ID]struct{}, error) {
	m := make(map[peer.ID]struct{}, len(ids))
	for _, raw := range ids {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			continue
		}
		pid, err := peer.Decode(trimmed)
		if err != nil {
			return nil, fmt.Errorf("invalid allowed peer ID %q: %w", trimmed, err)
		}
		m[pid] = struct{}{}
	}
	return m, nil
}

func newPeerACL(ids []string, enforceEmpty bool) (*peerACL, error) {
	m, err := parsePeerIDMap(ids)
	if err != nil {
		return nil, err
	}
	if !enforceEmpty && len(m) == 0 {
		return nil, nil
	}
	return &peerACL{allowed: m}, nil
}

func (a *peerACL) SetAllowed(ids []string) (int, error) {
	next, err := parsePeerIDMap(ids)
	if err != nil {
		return 0, err
	}
	a.mu.Lock()
	a.allowed = next
	a.mu.Unlock()
	return len(next), nil
}

func (a *peerACL) Allows(p peer.ID) bool {
	a.mu.RLock()
	defer a.mu.RUnlock()
	_, ok := a.allowed[p]
	return ok
}

func (a *peerACL) AllowReserve(p peer.ID, _ ma.Multiaddr) bool {
	return a.Allows(p)
}

func (a *peerACL) AllowConnect(src peer.ID, _ ma.Multiaddr, dest peer.ID) bool {
	return a.Allows(src) || a.Allows(dest)
}

// LoadPeerAllowFile reads newline-delimited libp2p PeerIDs from path.
// Blank lines and `#` comments are ignored.
func LoadPeerAllowFile(path string) ([]string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read allow file %s: %w", path, err)
	}
	lines := strings.Split(strings.ReplaceAll(string(raw), "\r\n", "\n"), "\n")
	out := make([]string, 0, len(lines))
	seen := make(map[string]struct{})
	for i, line := range lines {
		if idx := strings.IndexByte(line, '#'); idx != -1 {
			line = line[:idx]
		}
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if _, err := peer.Decode(trimmed); err != nil {
			return nil, fmt.Errorf("%s:%d: invalid peer ID %q: %w", path, i+1, trimmed, err)
		}
		if _, dup := seen[trimmed]; !dup {
			seen[trimmed] = struct{}{}
			out = append(out, trimmed)
		}
	}
	return out, nil
}

// RelayServer wraps a public Circuit Relay v2 hop + AutoNAT service host.
type RelayServer struct {
	Host  host.Host
	Relay *relay.Relay
	acl   *peerACL
}

// ReloadAllowedPeers atomically swaps the relay ACL allowlist without restarting the server.
func (s *RelayServer) ReloadAllowedPeers(ids []string) (int, error) {
	if s.acl == nil {
		return 0, errors.New("relay ACL is disabled (start with --allow-peer or --allow-file)")
	}
	return s.acl.SetAllowed(ids)
}

// ACLAllows reports whether p is currently permitted by the relay ACL (true if ACL is disabled).
func (s *RelayServer) ACLAllows(p peer.ID) bool {
	if s.acl == nil {
		return true
	}
	return s.acl.Allows(p)
}

// StartRelay launches a Circuit Relay v2 + AutoNAT server suitable for symmetric NAT traversal.
func StartRelay(cfg RelayConfig) (*RelayServer, error) {
	priv, err := pairing.LoadOrCreateIdentity(cfg.IdentityPath)
	if err != nil {
		return nil, err
	}

	acl, err := newPeerACL(cfg.AllowedPeers, cfg.EnableACL)
	if err != nil {
		return nil, err
	}

	listenAddrs := cfg.ListenAddrs
	if len(listenAddrs) == 0 {
		listenAddrs = []string{
			"/ip4/0.0.0.0/tcp/4001",
			"/ip4/0.0.0.0/udp/4001/quic-v1",
		}
	}

	h, err := libp2p.New(
		libp2p.Identity(priv),
		libp2p.ListenAddrStrings(listenAddrs...),
		libp2p.EnableNATService(),
		libp2p.ForceReachabilityPublic(),
		libp2p.UserAgent("agy-relay/0.1"),
	)
	if err != nil {
		return nil, fmt.Errorf("create relay host: %w", err)
	}

	var opts []relay.Option
	if cfg.Infinite {
		opts = append(opts, relay.WithInfiniteLimits())
	}
	if acl != nil {
		opts = append(opts, relay.WithACL(acl))
	}

	r, err := relay.New(h, opts...)
	if err != nil {
		_ = h.Close()
		return nil, fmt.Errorf("start circuit v2 relay: %w", err)
	}

	return &RelayServer{Host: h, Relay: r, acl: acl}, nil
}

// Addrs returns the full /p2p/<RelayPeerID> multiaddrs clients/hosts can pass to --relay.
func (s *RelayServer) Addrs() []string {
	self := s.Host.ID().String()
	out := make([]string, 0, len(s.Host.Addrs()))
	for _, a := range s.Host.Addrs() {
		out = append(out, fmt.Sprintf("%s/p2p/%s", a.String(), self))
	}
	return out
}

// Close closes the relay server and underlying libp2p host.
func (s *RelayServer) Close() error {
	if s.Relay != nil {
		_ = s.Relay.Close()
	}
	return s.Host.Close()
}
