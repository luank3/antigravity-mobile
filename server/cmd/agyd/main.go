package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/daemon"
	"github.com/antigravity/antigravity-mobile/server/pkg/pairing"
	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
)

type stringList []string

func (s *stringList) String() string { return strings.Join(*s, ",") }
func (s *stringList) Set(v string) error {
	*s = append(*s, v)
	return nil
}

func defaultConfigDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "agyd")
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "run":
		runCmd(os.Args[2:])
	case "pair":
		pairCmd(os.Args[2:])
	case "peers":
		peersCmd(os.Args[2:])
	case "status":
		statusCmd(os.Args[2:])
	case "install-service":
		installServiceCmd(os.Args[2:])
	case "uninstall-service":
		uninstallServiceCmd(os.Args[2:])
	default:
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("Usage: agyd <subcommand> [flags]")
	fmt.Println("Subcommands:")
	fmt.Println("  run                Start the libp2p + ACP host daemon")
	fmt.Println("  pair               Generate a single-use QR / URI / PIN pairing invitation")
	fmt.Println("  peers list         List authorized mobile devices")
	fmt.Println("  peers revoke       Revoke a paired mobile PeerID")
	fmt.Println("  status             Show running daemon PeerID, NAT, and relay addresses")
	fmt.Println("  install-service    Install & start systemd --user service unit for agyd")
	fmt.Println("  uninstall-service  Stop, disable, and remove the agyd systemd --user unit")
}

func runCmd(args []string) {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	var (
		configDir    string
		agyBin       string
		enableMDNS   bool
		forcePrivate bool
		relays       stringList
		workspaces   stringList
		listenAddrs  stringList
	)
	fs.StringVar(&configDir, "config-dir", defaultConfigDir(), "Daemon state directory")
	fs.StringVar(&agyBin, "agy", "agy", "Path to Antigravity CLI binary")
	fs.BoolVar(&enableMDNS, "mdns", true, "Enable local LAN mDNS discovery")
	fs.BoolVar(&forcePrivate, "force-private", false, "Force private reachability (immediately reserve relays)")
	fs.Var(&relays, "relay", "Circuit Relay v2 multiaddr (repeatable)")
	fs.Var(&workspaces, "workspace", "Allowed workspace root directory (repeatable)")
	fs.Var(&listenAddrs, "listen", "Listen multiaddr (repeatable)")
	_ = fs.Parse(args)

	sockPath := filepath.Join(configDir, "control.sock")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	d, err := daemon.Start(ctx, daemon.Config{
		ConfigDir:         configDir,
		ListenAddrs:       listenAddrs,
		StaticRelays:      relays,
		WorkspaceRoots:    workspaces,
		AgyBinary:         agyBin,
		EnableMDNS:        enableMDNS,
		ForcePrivate:      forcePrivate,
		ControlSocketPath: sockPath,
	})
	if err != nil {
		log.Fatalf("agyd start: %v", err)
	}
	defer d.Close()

	d.PairingManager().SetSASObserver(func(s pairing.PendingSession) {
		fmt.Printf("\n[PAIRING] Device %q (%s)\n  SAS: %s  %s\n",
			s.DeviceName, s.ClientPeerID, s.SASDigits, s.SASEmojis)
		if s.TrustAuto {
			fmt.Println("  Auto-trusted (--trust-next)")
		} else {
			fmt.Printf("  Approve with: agyd pair approve --session %s\n", s.SessionID)
		}
	})

	info := d.HostInfo()
	fmt.Printf("agyd running on %s\n", info.Hostname)
	fmt.Printf("  PeerID: %s\n", info.HostPeerID)
	for _, a := range info.ListenAddrs {
		fmt.Printf("  Direct: %s\n", a)
	}
	for _, r := range info.RelayAddrs {
		fmt.Printf("  Relay:  %s\n", r)
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh
	fmt.Println("\nshutting down agyd...")
}

func unixClient(sockPath string) *http.Client {
	return &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				var d net.Dialer
				return d.DialContext(ctx, "unix", sockPath)
			},
		},
	}
}

func pairCmd(args []string) {
	if len(args) > 0 && args[0] == "approve" {
		fs := flag.NewFlagSet("pair approve", flag.ExitOnError)
		configDir := fs.String("config-dir", defaultConfigDir(), "Daemon state directory")
		sessionID := fs.String("session", "", "Pairing session ID")
		reject := fs.Bool("reject", false, "Reject instead of approving")
		_ = fs.Parse(args[1:])
		if *sessionID == "" {
			log.Fatal("--session is required")
		}
		accept := "1"
		if *reject {
			accept = "0"
		}
		client := unixClient(filepath.Join(*configDir, "control.sock"))
		resp, err := client.Post("http://unix/pair/approve?session="+*sessionID+"&accept="+accept, "application/json", nil)
		if err != nil {
			log.Fatalf("contact agyd daemon: %v", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			log.Fatalf("approve failed: status %d", resp.StatusCode)
		}
		fmt.Println("Pairing decision sent.")
		return
	}

	fs := flag.NewFlagSet("pair", flag.ExitOnError)
	configDir := fs.String("config-dir", defaultConfigDir(), "Daemon state directory")
	trustNext := fs.Bool("trust-next", true, "Automatically approve matching token handshake without second prompt")
	_ = fs.Parse(args)

	trustParam := "0"
	if *trustNext {
		trustParam = "1"
	}
	client := unixClient(filepath.Join(*configDir, "control.sock"))
	resp, err := client.Get("http://unix/pair?trust=" + trustParam)
	if err != nil {
		log.Fatalf("cannot reach running agyd daemon (start with `agyd run`): %v", err)
	}
	defer resp.Body.Close()

	var inv protocol.PairInvite
	if err := json.NewDecoder(resp.Body).Decode(&inv); err != nil {
		log.Fatalf("decode invite: %v", err)
	}

	if qr, err := pairing.RenderTerminalQR(inv.URI); err == nil {
		fmt.Println(qr)
	}
	fmt.Printf("Host:    %s (%s)\n", inv.HostName, inv.HostPeerID)
	fmt.Printf("LAN PIN: %s\n", inv.Pin)
	fmt.Printf("Expires: %s\n", inv.ExpiresAt)
	fmt.Printf("URI:\n%s\n", inv.URI)
}

func peersCmd(args []string) {
	if len(args) < 1 {
		log.Fatal("usage: agyd peers <list|revoke>")
	}
	switch args[0] {
	case "list":
		fs := flag.NewFlagSet("peers list", flag.ExitOnError)
		configDir := fs.String("config-dir", defaultConfigDir(), "Daemon state directory")
		_ = fs.Parse(args[1:])
		client := unixClient(filepath.Join(*configDir, "control.sock"))
		resp, err := client.Get("http://unix/peers")
		if err != nil {
			log.Fatalf("contact agyd: %v", err)
		}
		defer resp.Body.Close()
		var peers []protocol.AuthorizedPeer
		_ = json.NewDecoder(resp.Body).Decode(&peers)
		if len(peers) == 0 {
			fmt.Println("No authorized peers.")
			return
		}
		for _, p := range peers {
			fmt.Printf("%s  %s  (paired %s)\n", p.PeerID, p.DeviceName, p.PairedAt.Format(time.RFC3339))
		}
	case "revoke":
		fs := flag.NewFlagSet("peers revoke", flag.ExitOnError)
		configDir := fs.String("config-dir", defaultConfigDir(), "Daemon state directory")
		_ = fs.Parse(args[1:])
		if fs.NArg() < 1 {
			log.Fatal("usage: agyd peers revoke <peer-id>")
		}
		client := unixClient(filepath.Join(*configDir, "control.sock"))
		resp, err := client.Post("http://unix/peers/revoke?peer="+fs.Arg(0), "application/json", nil)
		if err != nil {
			log.Fatalf("contact agyd: %v", err)
		}
		defer resp.Body.Close()
		fmt.Println("Peer revoked.")
	default:
		log.Fatal("usage: agyd peers <list|revoke>")
	}
}

func statusCmd(args []string) {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	configDir := fs.String("config-dir", defaultConfigDir(), "Daemon state directory")
	_ = fs.Parse(args)

	client := unixClient(filepath.Join(*configDir, "control.sock"))
	resp, err := client.Get("http://unix/status")
	if err != nil {
		log.Fatalf("agyd not reachable: %v", err)
	}
	defer resp.Body.Close()

	var info protocol.HostInfo
	_ = json.NewDecoder(resp.Body).Decode(&info)
	out, _ := json.MarshalIndent(info, "", "  ")
	fmt.Println(string(out))
}
