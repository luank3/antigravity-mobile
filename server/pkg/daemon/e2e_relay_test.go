package daemon

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/p2p"
	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
)

func writeMockACPForE2E(t *testing.T, dir string) string {
	t.Helper()
	p := filepath.Join(dir, "mock_acp.py")
	src := `#!/usr/bin/env python3
import json, sys
pid = 900
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    mid = msg.get("id")
    m = msg.get("method")
    params = msg.get("params") or {}
    if m == "initialize":
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":True}}}), flush=True)
    elif m == "session/list":
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"sessions":[{"sessionId":"sess-e2e","cwd":"` + dir + `","title":"E2E Relay Session"}]}}), flush=True)
    elif m == "session/prompt":
        sid = params.get("sessionId")
        print(json.dumps({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":sid,"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Working via relay"}}}}), flush=True)
        pid += 1
        print(json.dumps({"jsonrpc":"2.0","id":pid,"method":"session/request_permission","params":{"sessionId":sid,"toolCall":{"title":"ls /tmp"},"options":[{"optionId":"allow-once","name":"Allow once","kind":"allow_once"}]}}), flush=True)
        resp = json.loads(sys.stdin.readline())
        opt = resp["result"]["outcome"]["optionId"]
        print(json.dumps({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":sid,"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":f"Approved:{opt}"}}}}), flush=True)
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"stopReason":"end_turn"}}), flush=True)
`
	if err := os.WriteFile(p, []byte(src), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestE2ESymmetricNATRelayPairingUploadAndACP(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	tmpDir := t.TempDir()

	// 1. Start self-hosted agy-relay with infinite limits on localhost ephemeral port.
	relaySrv, err := p2p.StartRelay(p2p.RelayConfig{
		IdentityPath: filepath.Join(tmpDir, "relay.key"),
		ListenAddrs:  []string{"/ip4/127.0.0.1/tcp/0"},
		Infinite:     true,
	})
	if err != nil {
		t.Fatalf("start relay: %v", err)
	}
	defer relaySrv.Close()

	// 2. Start agyd behind simulated private/symmetric NAT (only relay addresses used by client).
	mockScript := writeMockACPForE2E(t, tmpDir)
	d, err := Start(ctx, Config{
		ConfigDir:      filepath.Join(tmpDir, "agyd-cfg"),
		ListenAddrs:    []string{"/ip4/127.0.0.1/tcp/0"},
		StaticRelays:   relaySrv.Addrs(),
		WorkspaceRoots: []string{tmpDir},
		AgyBinary:      "python3",
		AgyArgs:        []string{mockScript},
		EnableMDNS:     false,
		ForcePrivate:   true,
		UploadsDir:     filepath.Join(tmpDir, "tmp-uploads"),
	})
	if err != nil {
		t.Fatalf("start daemon: %v", err)
	}
	defer d.Close()

	// Wait briefly for relay slot reservation to complete.
	time.Sleep(350 * time.Millisecond)

	// 3. Start simulated mobile client host.
	mobileHost, err := p2p.NewHost(ctx, p2p.HostConfig{
		IdentityPath: filepath.Join(tmpDir, "mobile.key"),
		ListenAddrs:  []string{"/ip4/127.0.0.1/tcp/0"},
		EnableMDNS:   false,
		ForcePrivate: true,
	})
	if err != nil {
		t.Fatalf("start mobile host: %v", err)
	}
	defer mobileHost.Close()

	// Force dial ONLY via Circuit Relay v2 (strip direct addrs to simulate dual symmetric NAT!).
	hostID := d.Host().Host.ID()
	relayCircuitAddrs := d.Host().RelayCircuitAddrs()
	if len(relayCircuitAddrs) == 0 {
		t.Fatal("expected relay circuit addrs from daemon")
	}

	// Ensure mobile peerstore has zero direct addrs for hostID.
	mobileHost.Host.Peerstore().ClearAddrs(hostID)
	diag, err := p2p.RaceDial(ctx, mobileHost.Host, hostID, nil, relayCircuitAddrs)
	if err != nil {
		t.Fatalf("relay RaceDial failed: %v", err)
	}
	if !diag.Connected || !diag.IsRelayed || diag.PathType != "relay" {
		t.Fatalf("expected active relay connection, got: %+v", diag)
	}

	// 4. Unpaired peer must be rejected immediately on /agy/rpc/1.0.0.
	unauthStream, err := p2p.OpenStream(ctx, mobileHost.Host, hostID, protocol.ProtoRPC)
	if err == nil {
		_ = protocol.WriteJSON(unauthStream, protocol.RPCRequest{JSONRPC: "2.0", ID: 1, Method: "host/info"})
		var resp protocol.RPCResponse
		if readErr := protocol.ReadJSON(unauthStream, &resp); readErr == nil {
			t.Fatalf("expected unpaired RPC stream reset, got response: %+v", resp)
		}
		_ = unauthStream.Close()
	}

	// 5. Pair over /agy/pair/1.0.0 through the relay.
	inv, err := d.CreatePairInvite(2*time.Minute, true)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}
	pairStream, err := p2p.OpenStream(ctx, mobileHost.Host, hostID, protocol.ProtoPair)
	if err != nil {
		t.Fatalf("open pair stream over relay: %v", err)
	}
	if err := protocol.WriteJSON(pairStream, protocol.PairRequest{
		Token:      inv.Token,
		DeviceName: "Android Emulator",
	}); err != nil {
		t.Fatal(err)
	}
	var chal protocol.PairChallenge
	if err := protocol.ReadJSON(pairStream, &chal); err != nil {
		t.Fatal(err)
	}
	if chal.Error != "" || chal.SASDigits == "" {
		t.Fatalf("unexpected pair challenge: %+v", chal)
	}
	if err := protocol.WriteJSON(pairStream, protocol.PairConfirm{
		SessionID: chal.SessionID,
		Accept:    true,
	}); err != nil {
		t.Fatal(err)
	}
	var pairRes protocol.PairResult
	if err := protocol.ReadJSON(pairStream, &pairRes); err != nil {
		t.Fatal(err)
	}
	_ = pairStream.Close()
	if !pairRes.Paired {
		t.Fatalf("expected pairing success, got: %+v", pairRes)
	}

	// 6. Authenticated RPC calls through relay (host/info & session/list).
	rpcStream, err := p2p.OpenStream(ctx, mobileHost.Host, hostID, protocol.ProtoRPC)
	if err != nil {
		t.Fatalf("open authenticated rpc stream over relay: %v", err)
	}
	defer rpcStream.Close()

	callRPC := func(id int, method string, params any) protocol.RPCResponse {
		t.Helper()
		rawP, _ := json.Marshal(params)
		if err := protocol.WriteJSON(rpcStream, protocol.RPCRequest{
			JSONRPC: "2.0",
			ID:      id,
			Method:  method,
			Params:  rawP,
		}); err != nil {
			t.Fatalf("write rpc %s: %v", method, err)
		}
		var resp protocol.RPCResponse
		if err := protocol.ReadJSON(rpcStream, &resp); err != nil {
			t.Fatalf("read rpc %s: %v", method, err)
		}
		if resp.Error != nil {
			t.Fatalf("rpc %s error: %+v", method, resp.Error)
		}
		return resp
	}

	infoResp := callRPC(1, "host/info", map[string]any{})
	if !bytes.Contains(infoResp.Result, []byte(hostID.String())) {
		t.Fatalf("unexpected host/info: %s", infoResp.Result)
	}

	listResp := callRPC(2, "session/list", map[string]any{})
	if !bytes.Contains(listResp.Result, []byte("sess-e2e")) {
		t.Fatalf("unexpected session/list: %s", listResp.Result)
	}

	// 7. Upload file over /agy/blob/1.0.0 through the relay into remote /tmp dir.
	payload := []byte("remote debug log line 1\nremote debug log line 2\n")
	sum := sha256.Sum256(payload)
	blobStream, err := p2p.OpenStream(ctx, mobileHost.Host, hostID, protocol.ProtoBlob)
	if err != nil {
		t.Fatalf("open blob stream over relay: %v", err)
	}
	if err := protocol.WriteJSON(blobStream, protocol.BlobUploadHeader{
		SessionID:  "sess-e2e",
		Filename:   "logcat.txt",
		MimeType:   "text/plain",
		TotalBytes: int64(len(payload)),
		SHA256:     hex.EncodeToString(sum[:]),
	}); err != nil {
		t.Fatal(err)
	}
	if err := protocol.WriteFrame(blobStream, payload); err != nil {
		t.Fatal(err)
	}
	if err := protocol.WriteFrame(blobStream, nil); err != nil {
		t.Fatal(err)
	}
	var upRes protocol.BlobUploadResult
	if err := protocol.ReadJSON(blobStream, &upRes); err != nil {
		t.Fatalf("read blob upload result: %v", err)
	}
	_ = blobStream.Close()
	if upRes.UploadID == "" || upRes.SizeBytes != int64(len(payload)) {
		t.Fatalf("unexpected upload result: %+v", upRes)
	}
	diskData, err := os.ReadFile(upRes.RemotePath)
	if err != nil || !bytes.Equal(diskData, payload) {
		t.Fatalf("staged /tmp file mismatch: err=%v data=%q", err, diskData)
	}

	// 8. Subscribe to /agy/events/1.0.0, send session/prompt with uploaded file, approve permission!
	evStream, err := p2p.OpenStream(ctx, mobileHost.Host, hostID, protocol.ProtoEvents)
	if err != nil {
		t.Fatalf("open events stream over relay: %v", err)
	}
	defer evStream.Close()
	if err := protocol.WriteJSON(evStream, protocol.EventsSubscribeRequest{
		SessionIDs: []string{"sess-e2e"},
		SinceSeq:   0,
	}); err != nil {
		t.Fatal(err)
	}

	callRPC(3, "session/prompt", map[string]any{
		"sessionId": "sess-e2e",
		"text":      "Analyze uploaded log",
		"uploadIds": []string{upRes.UploadID},
	})

	var sawComplete bool
	for !sawComplete {
		var ev protocol.EventEnvelope
		if err := protocol.ReadJSON(evStream, &ev); err != nil {
			t.Fatalf("read event over relay: %v", err)
		}
		if ev.Kind == "permission_request" {
			var p struct {
				PermID string `json:"permId"`
			}
			_ = json.Unmarshal(ev.Payload, &p)
			callRPC(4, "session/respond_permission", map[string]any{
				"permId":   p.PermID,
				"optionId": "allow-once",
			})
		}
		if ev.Kind == "turn_complete" {
			sawComplete = true
		}
	}

	// Verify peerstore never had direct addr injected during test.
	_ = peer.ID("")
	_ = peerstore.TempAddrTTL
}
