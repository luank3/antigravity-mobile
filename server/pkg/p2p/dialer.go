package p2p

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	libp2pproto "github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	ma "github.com/multiformats/go-multiaddr"
	manet "github.com/multiformats/go-multiaddr/net"
)

// OpenStream opens a protocol stream and explicitly permits relayed (Limited) connections
// so symmetric NAT sessions over Circuit Relay v2 do not fail with ErrLimitedConn.
func OpenStream(ctx context.Context, h host.Host, target peer.ID, protoID string) (network.Stream, error) {
	streamCtx := network.WithAllowLimitedConn(ctx, protoID)
	return h.NewStream(streamCtx, target, libp2pproto.ID(protoID))
}

// SplitMultiaddrs parses string multiaddrs into clean transport addresses (without trailing /p2p/<target>).
func SplitMultiaddrs(target peer.ID, rawAddrs []string) ([]ma.Multiaddr, error) {
	out := make([]ma.Multiaddr, 0, len(rawAddrs))
	for _, raw := range rawAddrs {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		m, err := ma.NewMultiaddr(raw)
		if err != nil {
			return nil, fmt.Errorf("invalid multiaddr %q: %w", raw, err)
		}
		if pi, err := peer.AddrInfoFromP2pAddr(m); err == nil && pi.ID == target {
			out = append(out, pi.Addrs...)
		} else {
			out = append(out, m)
		}
	}
	return out, nil
}

// BuildRelayCircuitAddrs builds /p2p/<Relay>/p2p-circuit addresses for dialing target via relays.
// Each relayAddr may be either a full circuit multiaddr (.../p2p/<Relay>/p2p-circuit[/p2p/<Target>])
// or a base relay multiaddr (.../p2p/<Relay>).
func BuildRelayCircuitAddrs(target peer.ID, relayAddrs []string) (relayInfos []peer.AddrInfo, circuitAddrs []ma.Multiaddr, err error) {
	for _, raw := range relayAddrs {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		baseStr := raw
		if idx := strings.Index(raw, "/p2p-circuit"); idx != -1 {
			baseStr = raw[:idx]
		}
		baseMA, parseErr := ma.NewMultiaddr(baseStr)
		if parseErr != nil {
			return nil, nil, fmt.Errorf("invalid relay multiaddr %q: %w", raw, parseErr)
		}
		ri, infoErr := peer.AddrInfoFromP2pAddr(baseMA)
		if infoErr != nil {
			return nil, nil, fmt.Errorf("relay multiaddr missing peer ID %q: %w", raw, infoErr)
		}
		relayInfos = append(relayInfos, *ri)

		circMA, circErr := ma.NewMultiaddr(fmt.Sprintf("%s/p2p-circuit", baseMA.String()))
		if circErr != nil {
			return nil, nil, circErr
		}
		circuitAddrs = append(circuitAddrs, circMA)
	}
	return relayInfos, circuitAddrs, nil
}

// RaceDial connects to target preferring direct LAN/WAN addresses and transparently falling
// back to Circuit Relay v2 addresses when direct connectivity is blocked by NAT/firewalls.
func RaceDial(ctx context.Context, h host.Host, target peer.ID, directRaw []string, relayRaw []string) (*protocol.ConnDiagnostics, error) {
	if len(h.Network().ConnsToPeer(target)) > 0 {
		diag := InspectConnection(ctx, h, target)
		return &diag, nil
	}

	directMAs, err := SplitMultiaddrs(target, directRaw)
	if err != nil {
		return nil, err
	}
	if len(directMAs) > 0 {
		h.Peerstore().AddAddrs(target, directMAs, peerstore.TempAddrTTL)
		directCtx, cancel := context.WithTimeout(ctx, 2500*time.Millisecond)
		err := h.Connect(directCtx, peer.AddrInfo{ID: target, Addrs: directMAs})
		cancel()
		if err == nil {
			diag := InspectConnection(ctx, h, target)
			return &diag, nil
		}
	}

	// Fallback: connect to relays and dial over /p2p-circuit.
	relayInfos, circuitMAs, err := BuildRelayCircuitAddrs(target, relayRaw)
	if err != nil {
		return nil, err
	}
	if len(circuitMAs) == 0 {
		// Still check Peerstore in case mDNS populated addresses concurrently.
		if err := h.Connect(ctx, peer.AddrInfo{ID: target}); err != nil {
			return nil, fmt.Errorf("connect peer %s: %w", target, err)
		}
		diag := InspectConnection(ctx, h, target)
		return &diag, nil
	}

	for _, ri := range relayInfos {
		rCtx, cancel := context.WithTimeout(ctx, 6*time.Second)
		_ = h.Connect(rCtx, ri)
		cancel()
	}

	h.Peerstore().AddAddrs(target, circuitMAs, peerstore.TempAddrTTL)
	if err := h.Connect(ctx, peer.AddrInfo{ID: target, Addrs: circuitMAs}); err != nil {
		return nil, fmt.Errorf("circuit relay connect %s: %w", target, err)
	}

	diag := InspectConnection(ctx, h, target)
	return &diag, nil
}

// InspectConnection inspects the active connection(s) to target and measures live RTT.
func InspectConnection(ctx context.Context, h host.Host, target peer.ID) protocol.ConnDiagnostics {
	conns := h.Network().ConnsToPeer(target)
	if len(conns) == 0 {
		return protocol.ConnDiagnostics{
			PeerID:    target.String(),
			Connected: false,
			PathType:  "disconnected",
		}
	}

	// Prefer non-relayed / non-limited connection when multiple exist (e.g. after DCUtR upgrade).
	chosen := conns[0]
	for _, c := range conns {
		if !c.Stat().Limited && !strings.Contains(c.RemoteMultiaddr().String(), "/p2p-circuit") {
			chosen = c
			break
		}
	}

	remoteStr := chosen.RemoteMultiaddr().String()
	isRelayed := chosen.Stat().Limited || strings.Contains(remoteStr, "/p2p-circuit")

	pathType := "direct"
	relayPeerID := ""
	if isRelayed {
		pathType = "relay"
		relayPeerID = extractRelayPeerID(remoteStr)
	} else if isPrivateAddr(chosen.RemoteMultiaddr()) {
		pathType = "lan"
	}

	transport := "TCP · Noise · Yamux"
	if strings.Contains(remoteStr, "/quic") {
		transport = "QUIC v1 · Noise"
	}
	if isRelayed {
		transport = "Circuit Relay v2 · " + transport
	}

	rttMs := measurePingRTT(ctx, h, target)

	return protocol.ConnDiagnostics{
		PeerID:      target.String(),
		Connected:   true,
		PathType:    pathType,
		Transport:   transport,
		RemoteAddr:  remoteStr,
		RelayPeerID: relayPeerID,
		RTTMs:       rttMs,
		IsRelayed:   isRelayed,
	}
}

func extractRelayPeerID(addr string) string {
	idx := strings.Index(addr, "/p2p-circuit")
	if idx <= 0 {
		return ""
	}
	prefix := addr[:idx]
	parts := strings.Split(prefix, "/p2p/")
	if len(parts) < 2 {
		return ""
	}
	return parts[len(parts)-1]
}

func isPrivateAddr(maddr ma.Multiaddr) bool {
	ip, err := manet.ToIP(maddr)
	if err != nil || ip == nil {
		return false
	}
	return ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || net.IPv4(100, 64, 0, 0).Equal(ip.Mask(net.CIDRMask(10, 32)))
}

func measurePingRTT(ctx context.Context, h host.Host, target peer.ID) int64 {
	pCtx, cancel := context.WithTimeout(network.WithAllowLimitedConn(ctx, "ping"), 2*time.Second)
	defer cancel()
	ch := ping.Ping(pCtx, h, target)
	select {
	case res, ok := <-ch:
		if ok && res.Error == nil {
			ms := res.RTT.Milliseconds()
			if ms == 0 {
				ms = 1
			}
			return ms
		}
	case <-pCtx.Done():
	}
	return 0
}
