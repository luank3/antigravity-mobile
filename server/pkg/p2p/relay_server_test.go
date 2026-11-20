package p2p

import (
	"crypto/rand"
	"os"
	"path/filepath"
	"testing"

	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func genTestPeerID(t *testing.T) peer.ID {
	t.Helper()
	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("gen key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(priv)
	if err != nil {
		t.Fatalf("peer ID: %v", err)
	}
	return pid
}

func TestLoadPeerAllowFile(t *testing.T) {
	p1 := genTestPeerID(t)
	p2 := genTestPeerID(t)

	dir := t.TempDir()
	path := filepath.Join(dir, "allowed_peers.txt")
	content := "# Remote agyd hosts\n" +
		"  " + p1.String() + "  # home-workstation\n" +
		"\n" +
		p2.String() + "\n" +
		p1.String() + " # duplicate ignored\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write allow file: %v", err)
	}

	got, err := LoadPeerAllowFile(path)
	if err != nil {
		t.Fatalf("LoadPeerAllowFile failed: %v", err)
	}
	if len(got) != 2 || got[0] != p1.String() || got[1] != p2.String() {
		t.Fatalf("unexpected peers: %v", got)
	}

	badPath := filepath.Join(dir, "bad_peers.txt")
	_ = os.WriteFile(badPath, []byte("not-a-valid-peer-id\n"), 0o600)
	if _, err := LoadPeerAllowFile(badPath); err == nil {
		t.Fatal("expected error on invalid peer ID in allow file")
	}
}

func TestRelayACLHotReload(t *testing.T) {
	p1 := genTestPeerID(t)
	p2 := genTestPeerID(t)
	dummyMA, _ := ma.NewMultiaddr("/ip4/127.0.0.1/tcp/4001")

	srv, err := StartRelay(RelayConfig{
		IdentityPath: filepath.Join(t.TempDir(), "relay.key"),
		ListenAddrs:  []string{"/ip4/127.0.0.1/tcp/0"},
		EnableACL:    true,
		Infinite:     true,
	})
	if err != nil {
		t.Fatalf("StartRelay: %v", err)
	}
	defer srv.Close()

	// Empty enforced ACL must fail closed.
	if srv.ACLAllows(p1) || srv.acl.AllowReserve(p1, dummyMA) || srv.acl.AllowConnect(p1, dummyMA, p2) {
		t.Fatal("expected empty ACL to deny all peers initially")
	}

	// Hot-reload to allow p1.
	n, err := srv.ReloadAllowedPeers([]string{p1.String()})
	if err != nil || n != 1 {
		t.Fatalf("ReloadAllowedPeers failed: n=%d err=%v", n, err)
	}
	if !srv.ACLAllows(p1) || !srv.acl.AllowReserve(p1, dummyMA) || !srv.acl.AllowConnect(p2, dummyMA, p1) {
		t.Fatal("expected p1 and connections targeting p1 to be allowed after reload")
	}
	if srv.ACLAllows(p2) || srv.acl.AllowReserve(p2, dummyMA) {
		t.Fatal("expected unlisted peer p2 to remain denied for reserve")
	}

	// Revoke p1 and switch to p2 without restarting relay.
	n, err = srv.ReloadAllowedPeers([]string{p2.String()})
	if err != nil || n != 1 {
		t.Fatalf("second ReloadAllowedPeers failed: n=%d err=%v", n, err)
	}
	if srv.ACLAllows(p1) || !srv.ACLAllows(p2) {
		t.Fatal("expected ACL to reflect revoked p1 and newly allowed p2")
	}
}
