package p2p

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/pairing"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/discovery/mdns"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	ma "github.com/multiformats/go-multiaddr"
)

const DefaultMDNSServiceTag = "agy-mobile-mdns"

// HostConfig configures a libp2p host (used by both agyd and mobilebridge).
type HostConfig struct {
	IdentityPath       string
	ListenAddrs        []string
	StaticRelays       []string
	EnableMDNS         bool
	EnableHolePunching bool
	EnableNATPortMap   bool
	ForcePrivate       bool
	ServiceTag         string
}

// LANDiscoveredPeer records a peer found on the local subnet via mDNS.
type LANDiscoveredPeer struct {
	PeerID    string    `json:"peerId"`
	Addrs     []string  `json:"addrs"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// ManagedHost wraps a go-libp2p host with relay reservation upkeep and LAN discovery.
type ManagedHost struct {
	Host   host.Host
	Relays []peer.AddrInfo

	cancel context.CancelFunc
	mdns   mdns.Service

	mu          sync.RWMutex
	lanPeers    map[peer.ID]LANDiscoveredPeer
	activeRelay map[peer.ID][]ma.Multiaddr
	natStatus   string
}

type mdnsNotifee struct {
	mh *ManagedHost
}

func (n *mdnsNotifee) HandlePeerFound(pi peer.AddrInfo) {
	if pi.ID == n.mh.Host.ID() {
		return
	}
	n.mh.Host.Peerstore().AddAddrs(pi.ID, pi.Addrs, 10*time.Minute)
	strs := make([]string, 0, len(pi.Addrs))
	for _, a := range pi.Addrs {
		strs = append(strs, a.String())
	}
	n.mh.mu.Lock()
	n.mh.lanPeers[pi.ID] = LANDiscoveredPeer{
		PeerID:    pi.ID.String(),
		Addrs:     strs,
		UpdatedAt: time.Now().UTC(),
	}
	n.mh.mu.Unlock()
}

// ParseRelayAddrInfos parses multiaddrs containing /p2p/<RelayPeerID> into AddrInfos.
func ParseRelayAddrInfos(addrs []string) ([]peer.AddrInfo, error) {
	byPeer := make(map[peer.ID][]ma.Multiaddr)
	order := make([]peer.ID, 0, len(addrs))
	for _, raw := range addrs {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		maddr, err := ma.NewMultiaddr(raw)
		if err != nil {
			return nil, fmt.Errorf("invalid relay multiaddr %q: %w", raw, err)
		}
		pi, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			return nil, fmt.Errorf("relay multiaddr missing /p2p/<id> %q: %w", raw, err)
		}
		if _, exists := byPeer[pi.ID]; !exists {
			order = append(order, pi.ID)
		}
		byPeer[pi.ID] = append(byPeer[pi.ID], pi.Addrs...)
	}
	out := make([]peer.AddrInfo, 0, len(order))
	for _, id := range order {
		out = append(out, peer.AddrInfo{ID: id, Addrs: byPeer[id]})
	}
	return out, nil
}

// NewHost initializes a go-libp2p host configured for LAN mDNS, WAN/DCUtR, and Circuit Relay v2.
func NewHost(ctx context.Context, cfg HostConfig) (*ManagedHost, error) {
	priv, err := pairing.LoadOrCreateIdentity(cfg.IdentityPath)
	if err != nil {
		return nil, err
	}

	listenAddrs := cfg.ListenAddrs
	if len(listenAddrs) == 0 {
		listenAddrs = []string{
			"/ip4/0.0.0.0/tcp/0",
			"/ip4/0.0.0.0/udp/0/quic-v1",
		}
	}

	relayInfos, err := ParseRelayAddrInfos(cfg.StaticRelays)
	if err != nil {
		return nil, err
	}

	opts := []libp2p.Option{
		libp2p.Identity(priv),
		libp2p.ListenAddrStrings(listenAddrs...),
		libp2p.EnableRelay(),
		libp2p.UserAgent("antigravity-mobile/0.1"),
	}
	if cfg.EnableNATPortMap {
		opts = append(opts, libp2p.NATPortMap())
	}
	if cfg.EnableHolePunching {
		opts = append(opts, libp2p.EnableHolePunching())
	}
	if cfg.ForcePrivate {
		opts = append(opts, libp2p.ForceReachabilityPrivate())
	}
	if len(relayInfos) > 0 {
		opts = append(opts, libp2p.EnableAutoRelayWithStaticRelays(relayInfos))
	}

	h, err := libp2p.New(opts...)
	if err != nil {
		return nil, fmt.Errorf("create libp2p host: %w", err)
	}

	loopCtx, cancel := context.WithCancel(ctx)
	mh := &ManagedHost{
		Host:        h,
		Relays:      relayInfos,
		cancel:      cancel,
		lanPeers:    make(map[peer.ID]LANDiscoveredPeer),
		activeRelay: make(map[peer.ID][]ma.Multiaddr),
		natStatus:   "Detecting",
	}
	if cfg.ForcePrivate {
		mh.natStatus = "Private (Relay Active)"
	}

	if cfg.EnableMDNS {
		tag := cfg.ServiceTag
		if tag == "" {
			tag = DefaultMDNSServiceTag
		}
		svc := mdns.NewMdnsService(h, tag, &mdnsNotifee{mh: mh})
		if err := svc.Start(); err != nil {
			// Non-fatal on restricted environments (e.g. Android emulator without multicast lock)
			_ = err
		} else {
			mh.mdns = svc
		}
	}

	if len(relayInfos) > 0 {
		go mh.reserveRelaysLoop(loopCtx)
	}

	return mh, nil
}

func (m *ManagedHost) reserveRelaysLoop(ctx context.Context) {
	reserveAll := func() {
		for _, relayInfo := range m.Relays {
			rCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
			_ = m.Host.Connect(rCtx, relayInfo)
			res, err := client.Reserve(rCtx, m.Host, relayInfo)
			cancel()
			if err != nil {
				continue
			}
			m.mu.Lock()
			m.activeRelay[relayInfo.ID] = res.Addrs
			m.natStatus = "Relay Reserved"
			m.mu.Unlock()
		}
	}

	reserveAll()
	ticker := time.NewTicker(45 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			reserveAll()
		}
	}
}

// RelayCircuitAddrs returns full /p2p/<Relay>/p2p-circuit/p2p/<Self> multiaddrs for configured relays.
func (m *ManagedHost) RelayCircuitAddrs() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	selfID := m.Host.ID().String()
	var out []string
	seen := make(map[string]struct{})

	for _, ri := range m.Relays {
		for _, base := range ri.Addrs {
			full := fmt.Sprintf("%s/p2p/%s/p2p-circuit/p2p/%s", base.String(), ri.ID.String(), selfID)
			if _, ok := seen[full]; !ok {
				seen[full] = struct{}{}
				out = append(out, full)
			}
		}
	}
	return out
}

// DirectAddrs returns all non-relayed listen multiaddrs including /p2p/<Self>.
func (m *ManagedHost) DirectAddrs() []string {
	self := m.Host.ID().String()
	var out []string
	for _, a := range m.Host.Addrs() {
		s := a.String()
		if strings.Contains(s, "/p2p-circuit") ||
			strings.HasPrefix(s, "/ip4/127.") ||
			strings.HasPrefix(s, "/ip4/0.0.0.0/") ||
			strings.HasPrefix(s, "/ip6/::1/") ||
			strings.HasPrefix(s, "/ip6/::/") ||
			strings.HasPrefix(s, "/ip6/fe80:") {
			continue
		}
		out = append(out, fmt.Sprintf("%s/p2p/%s", s, self))
	}
	return out
}

// LANDiscovered returns currently cached mDNS LAN peers.
func (m *ManagedHost) LANDiscovered() []LANDiscoveredPeer {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]LANDiscoveredPeer, 0, len(m.lanPeers))
	for _, p := range m.lanPeers {
		out = append(out, p)
	}
	return out
}

// NATStatus returns a human-readable NAT/relay status string.
func (m *ManagedHost) NATStatus() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.natStatus
}

// Close shuts down mDNS, background reservation loops, and the libp2p host.
func (m *ManagedHost) Close() error {
	if m.cancel != nil {
		m.cancel()
	}
	if m.mdns != nil {
		_ = m.mdns.Close()
	}
	return m.Host.Close()
}
