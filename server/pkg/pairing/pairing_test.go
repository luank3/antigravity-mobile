package pairing

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/libp2p/go-libp2p/core/peer"
)

func TestIdentityAndAllowlistPersistence(t *testing.T) {
	dir := t.TempDir()
	keyPath := filepath.Join(dir, "identity.key")

	priv1, err := LoadOrCreateIdentity(keyPath)
	if err != nil {
		t.Fatalf("create identity: %v", err)
	}
	priv2, err := LoadOrCreateIdentity(keyPath)
	if err != nil {
		t.Fatalf("reload identity: %v", err)
	}
	id1, _ := peer.IDFromPrivateKey(priv1)
	id2, _ := peer.IDFromPrivateKey(priv2)
	if id1 != id2 {
		t.Fatalf("expected identical peer ID, got %s vs %s", id1, id2)
	}

	aclPath := filepath.Join(dir, "authorized_peers.json")
	acl, err := NewAllowlist(aclPath)
	if err != nil {
		t.Fatalf("new allowlist: %v", err)
	}
	if acl.IsAllowed(id1) {
		t.Fatal("unexpected peer allowed initially")
	}
	if err := acl.Add(id1, "Pixel 9"); err != nil {
		t.Fatalf("add peer: %v", err)
	}

	reloaded, err := NewAllowlist(aclPath)
	if err != nil {
		t.Fatalf("reload allowlist: %v", err)
	}
	if !reloaded.IsAllowed(id1) {
		t.Fatal("expected peer to be allowed after reload")
	}

	ok, err := reloaded.Revoke(id1)
	if err != nil || !ok {
		t.Fatalf("revoke failed: ok=%v err=%v", ok, err)
	}
	if reloaded.IsAllowed(id1) {
		t.Fatal("expected peer disallowed after revoke")
	}
}

func TestPairURIAndSingleUseTokenSAS(t *testing.T) {
	hostPriv, _ := LoadOrCreateIdentity("")
	clientPriv, _ := LoadOrCreateIdentity("")
	hostID, _ := peer.IDFromPrivateKey(hostPriv)
	clientID, _ := peer.IDFromPrivateKey(clientPriv)

	acl, _ := NewAllowlist("")
	mgr := NewManager(acl)

	tok, err := mgr.CreateToken(2*time.Minute, true)
	if err != nil {
		t.Fatalf("create token: %v", err)
	}

	uri := BuildPairURI(
		hostID.String(),
		"workstation",
		tok.Token,
		[]string{"/dns4/relay.example.com/udp/4001/quic-v1/p2p/" + hostID.String()},
		[]string{"/ip4/192.168.1.10/tcp/4001/p2p/" + hostID.String()},
	)
	parsed, err := ParsePairURI(uri)
	if err != nil {
		t.Fatalf("parse uri: %v", err)
	}
	if parsed.HostPeerID != hostID.String() || parsed.Token != tok.Token || parsed.HostName != "workstation" {
		t.Fatalf("unexpected parsed URI: %+v", parsed)
	}

	sess, err := mgr.StartHandshake(hostID, clientID, protocol.PairRequest{
		Token:      tok.Token,
		DeviceName: "Android Emulator",
	})
	if err != nil {
		t.Fatalf("start handshake: %v", err)
	}
	d1, e1 := ComputeSAS(hostID.String(), clientID.String(), tok.Token)
	if sess.SASDigits != d1 || sess.SASEmojis != e1 {
		t.Fatalf("SAS mismatch: %s %s vs %s %s", sess.SASDigits, sess.SASEmojis, d1, e1)
	}

	// Single-use token cannot be reused.
	if _, err := mgr.StartHandshake(hostID, clientID, protocol.PairRequest{
		Token:      tok.Token,
		DeviceName: "Replay",
	}); err == nil {
		t.Fatal("expected single-use token replay to fail")
	}

	ok, err := mgr.CompleteHandshake(sess.SessionID, true, time.Second)
	if err != nil || !ok {
		t.Fatalf("complete handshake: ok=%v err=%v", ok, err)
	}
	if !acl.IsAllowed(clientID) {
		t.Fatal("expected client peer ID in allowlist")
	}
}
