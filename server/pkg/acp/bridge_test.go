package acp

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/workspace"
)

func writeMockACPScript(t *testing.T, dir string) string {
	t.Helper()
	scriptPath := filepath.Join(dir, "mock_agy.py")
	script := `#!/usr/bin/env python3
import json, sys

list_calls = 0
perm_seq = 1000

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    mid = msg.get("id")
    method = msg.get("method")
    params = msg.get("params") or {}

    if method == "initialize":
        print(json.dumps({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "protocolVersion": 1,
                "agentCapabilities": {"loadSession": True, "promptCapabilities": {"image": True}},
                "agentInfo": {"name": "Mock ACP", "version": "1.0"}
            }
        }), flush=True)
    elif method == "session/list":
        list_calls += 1
        if list_calls == 1:
            print(json.dumps({
                "jsonrpc": "2.0",
                "id": mid,
                "error": {"code": -32000, "message": "Authentication required"}
            }), flush=True)
        else:
            print(json.dumps({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {
                    "sessions": [{"sessionId": "sess-1", "cwd": "/tmp", "title": "Mock Session", "updatedAt": "2026-11-20T05:00:00Z"}]
                }
            }), flush=True)
    elif method == "session/new":
        print(json.dumps({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {"sessionId": "sess-new", "additionalDirectories": params.get("additionalDirectories", [])}
        }), flush=True)
    elif method == "session/prompt":
        sid = params.get("sessionId")
        # Emit a session/update chunk
        print(json.dumps({
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": {"sessionId": sid, "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Checking uploaded file..."}}}
        }), flush=True)
        # Send permission request and wait for client response
        perm_seq += 1
        pid = perm_seq
        print(json.dumps({
            "jsonrpc": "2.0",
            "id": pid,
            "method": "session/request_permission",
            "params": {
                "sessionId": sid,
                "toolCall": {"toolCallId": "tc_1", "title": "go test ./...", "kind": "execute"},
                "options": [{"optionId": "allow-once", "name": "Allow once", "kind": "allow_once"}]
            }
        }), flush=True)
        resp_line = sys.stdin.readline()
        resp = json.loads(resp_line)
        opt = resp.get("result", {}).get("outcome", {}).get("optionId", "")
        print(json.dumps({
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": {"sessionId": sid, "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": f"Permission outcome: {opt}"}}}
        }), flush=True)
        print(json.dumps({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {"stopReason": "end_turn", "blocks": len(params.get("prompt", []))}
        }), flush=True)
    elif method == "session/close":
        print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": {}}), flush=True)
`
	if err := os.WriteFile(scriptPath, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return scriptPath
}

func TestACPBridgeAuthRetryPromptUploadsAndPermissions(t *testing.T) {
	dir := t.TempDir()
	script := writeMockACPScript(t, dir)

	um, err := workspace.NewUploadManager(filepath.Join(dir, "uploads"), 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	ws, err := workspace.NewManager([]string{dir}, "")
	if err != nil {
		t.Fatal(err)
	}

	b := NewBridge(Config{
		BinaryPath: "python3",
		Args:       []string{script},
		Uploads:    um,
		Workspace:  ws,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := b.Start(ctx); err != nil {
		t.Fatalf("bridge start: %v", err)
	}
	defer b.Close()

	// Auth retry test: first session/list returns -32000, retry succeeds.
	listRaw, err := b.ListSessions(ctx, nil)
	if err != nil {
		t.Fatalf("list sessions with retry: %v", err)
	}
	if !strings.Contains(string(listRaw), "sess-1") {
		t.Fatalf("unexpected session/list: %s", listRaw)
	}

	// NewSession must attach upload staging dir as additionalDirectories.
	newRaw, err := b.NewSession(ctx, map[string]any{"cwd": dir})
	if err != nil {
		t.Fatalf("new session: %v", err)
	}
	if !strings.Contains(string(newRaw), um.BaseDir()) {
		t.Fatalf("expected upload base dir in additionalDirectories: %s", newRaw)
	}

	// Upload a PNG image into /tmp staging and send prompt referencing it.
	imgBytes := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 1, 2, 3}
	up, err := um.SaveStream("sess-new", "shot.png", "image/png", strings.NewReader(string(imgBytes)), "")
	if err != nil {
		t.Fatal(err)
	}

	_, ch, unsub := b.Subscribe(0, []string{"sess-new"})
	defer unsub()

	if _, err := b.Prompt(ctx, PromptParams{
		SessionID: "sess-new",
		Text:      "Check attached screenshot",
		UploadIDs: []string{up.UploadID},
	}); err != nil {
		t.Fatalf("prompt failed: %v", err)
	}

	// Wait for permission_request event and approve it.
	var permID string
	deadline := time.After(5 * time.Second)
	for permID == "" {
		select {
		case ev := <-ch:
			if ev.Kind == "permission_request" {
				var p PendingPermission
				_ = json.Unmarshal(ev.Payload, &p)
				permID = p.PermID
			}
		case <-deadline:
			t.Fatal("timed out waiting for permission_request")
		}
	}

	if err := b.RespondPermission(permID, "allow-once", false); err != nil {
		t.Fatalf("respond permission: %v", err)
	}

	// Expect turn_complete event and replay verification.
	var sawComplete bool
	var lastSeq uint64
	deadline2 := time.After(5 * time.Second)
	for !sawComplete {
		select {
		case ev := <-ch:
			lastSeq = ev.Seq
			if ev.Kind == "turn_complete" {
				sawComplete = true
			}
		case <-deadline2:
			t.Fatal("timed out waiting for turn_complete")
		}
	}

	backlog, _, unsub2 := b.Subscribe(1, []string{"sess-new"})
	unsub2()
	if len(backlog) == 0 || backlog[len(backlog)-1].Seq != lastSeq {
		t.Fatalf("expected ring buffer replay from seq 1 up to %d, got %d items", lastSeq, len(backlog))
	}

	// CloseSession must delete staged uploads.
	if _, err := b.CloseSession(ctx, "sess-new"); err != nil {
		t.Fatalf("close session: %v", err)
	}
	if _, err := os.Stat(up.RemotePath); !os.IsNotExist(err) {
		t.Fatal("expected CloseSession to delete staged upload")
	}
}
