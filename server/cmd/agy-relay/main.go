package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/antigravity/antigravity-mobile/server/pkg/p2p"
)

type stringSliceFlag []string

func (s *stringSliceFlag) String() string { return strings.Join(*s, ",") }
func (s *stringSliceFlag) Set(v string) error {
	*s = append(*s, v)
	return nil
}

func loadMergedAllowlist(cliPeers []string, allowFile string) ([]string, error) {
	seen := make(map[string]struct{})
	var out []string
	add := func(items []string) {
		for _, item := range items {
			item = strings.TrimSpace(item)
			if item == "" {
				continue
			}
			if _, ok := seen[item]; !ok {
				seen[item] = struct{}{}
				out = append(out, item)
			}
		}
	}
	add(cliPeers)
	if allowFile != "" {
		filePeers, err := p2p.LoadPeerAllowFile(allowFile)
		if err != nil {
			return nil, err
		}
		add(filePeers)
	}
	return out, nil
}

func main() {
	home, _ := os.UserHomeDir()
	defaultKey := filepath.Join(home, ".config", "agy-relay", "identity.key")

	var (
		identityPath string
		publicHost   string
		allowFile    string
		infinite     bool
		listenAddrs  stringSliceFlag
		allowedPeers stringSliceFlag
	)

	flag.StringVar(&identityPath, "identity", defaultKey, "Path to persistent Ed25519 identity key")
	flag.StringVar(&publicHost, "public-host", "", "Optional public DNS or IP to print copyable relay multiaddrs")
	flag.BoolVar(&infinite, "infinite", true, "Disable default 2m/128KB Circuit Relay v2 caps")
	flag.Var(&listenAddrs, "listen", "Listen multiaddr (repeatable; defaults to TCP :4001 & QUIC :4001)")
	flag.Var(&allowedPeers, "allow-peer", "Optional PeerID allowlist for relay reservations/connections (repeatable)")
	flag.StringVar(&allowFile, "allow-file", "", "Optional newline-delimited PeerID allowlist file (hot-reloaded on SIGHUP)")
	flag.Parse()

	initialACL, err := loadMergedAllowlist(allowedPeers, allowFile)
	if err != nil {
		log.Fatalf("load relay ACL: %v", err)
	}

	aclEnabled := len(allowedPeers) > 0 || allowFile != ""
	srv, err := p2p.StartRelay(p2p.RelayConfig{
		IdentityPath: identityPath,
		ListenAddrs:  listenAddrs,
		AllowedPeers: initialACL,
		EnableACL:    aclEnabled,
		Infinite:     infinite,
	})
	if err != nil {
		log.Fatalf("start relay: %v", err)
	}
	defer srv.Close()

	fmt.Printf("agy-relay running (PeerID: %s)\n", srv.Host.ID())
	for _, addr := range srv.Addrs() {
		fmt.Printf("  listen: %s\n", addr)
	}
	if aclEnabled {
		fmt.Printf("  ACL active: %d allowed PeerID(s)", len(initialACL))
		if allowFile != "" {
			fmt.Printf(" (allow-file: %s; send SIGHUP to hot-reload)", allowFile)
		}
		fmt.Println()
	} else {
		fmt.Println("  ACL disabled (open relay)")
	}
	if publicHost != "" {
		fmt.Printf("Recommended --relay multiaddr for agyd:\n")
		fmt.Printf("  /dns4/%s/udp/4001/quic-v1/p2p/%s\n", publicHost, srv.Host.ID())
		fmt.Printf("  /dns4/%s/tcp/4001/p2p/%s\n", publicHost, srv.Host.ID())
	}

	hupCh := make(chan os.Signal, 1)
	signal.Notify(hupCh, syscall.SIGHUP)
	stopHup := make(chan struct{})
	go func() {
		for {
			select {
			case <-stopHup:
				return
			case <-hupCh:
				nextACL, loadErr := loadMergedAllowlist(allowedPeers, allowFile)
				if loadErr != nil {
					log.Printf("ACL hot-reload failed (keeping previous list): %v", loadErr)
					continue
				}
				n, reloadErr := srv.ReloadAllowedPeers(nextACL)
				if reloadErr != nil {
					log.Printf("ACL hot-reload failed: %v", reloadErr)
					continue
				}
				log.Printf("ACL hot-reloaded: %d allowed PeerID(s)", n)
			}
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh
	close(stopHup)
	fmt.Println("\nshutting down agy-relay...")
}
