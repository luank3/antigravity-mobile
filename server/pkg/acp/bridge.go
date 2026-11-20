package acp

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/antigravity/antigravity-mobile/server/pkg/workspace"
)

const (
	defaultRingCapacity = 2000
	maxScannerTokenSize = 16 << 20
	maxInlineImageBytes = 5 << 20
)

// Config configures the agy acp stdio process bridge.
type Config struct {
	BinaryPath string
	Args       []string
	ExtraEnv   []string
	Uploads    *workspace.UploadManager
	Workspace  *workspace.Manager
}

type jsonRPCEnvelope struct {
	JSONRPC string             `json:"jsonrpc"`
	ID      json.RawMessage    `json:"id,omitempty"`
	Method  string             `json:"method,omitempty"`
	Params  json.RawMessage    `json:"params,omitempty"`
	Result  json.RawMessage    `json:"result,omitempty"`
	Error   *protocol.RPCError `json:"error,omitempty"`
}

// PendingPermission tracks an unresolved session/request_permission RPC from agy.
type PendingPermission struct {
	PermID    string          `json:"permId"`
	SessionID string          `json:"sessionId"`
	ToolCall  json.RawMessage `json:"toolCall,omitempty"`
	Options   json.RawMessage `json:"options,omitempty"`
	CreatedAt time.Time       `json:"createdAt"`
	rpcID     json.RawMessage
}

// PromptParams defines the mobile->agyd parameters for session/prompt.
type PromptParams struct {
	SessionID string   `json:"sessionId"`
	Text      string   `json:"text"`
	Files     []string `json:"files,omitempty"`     // @workspace relative paths
	UploadIDs []string `json:"uploadIds,omitempty"` // staged /tmp upload IDs
	Sync      bool     `json:"sync,omitempty"`      // wait for turn completion if true
}

// Bridge supervises a long-lived `agy acp --stdio` subprocess, ring-buffered event stream,
// startup auth-settling retries, and durable permission prompts.
type Bridge struct {
	cfg Config

	mu          sync.Mutex
	cmd         *exec.Cmd
	stdin       io.WriteCloser
	started     bool
	authReady   bool
	agentInfo   json.RawMessage
	nextRPCID   atomic.Uint64
	pendingRPCs map[string]chan jsonRPCEnvelope

	permMu       sync.Mutex
	pendingPerms map[string]*PendingPermission

	evMu        sync.RWMutex
	nextSeq     atomic.Uint64
	ring        []protocol.EventEnvelope
	ringCap     int
	subscribers map[uint64]chan protocol.EventEnvelope
	nextSubID   atomic.Uint64

	closed chan struct{}
}

// NewBridge creates an ACP Bridge (call Start to spawn the subprocess and initialize).
func NewBridge(cfg Config) *Bridge {
	if cfg.BinaryPath == "" {
		cfg.BinaryPath = "agy"
	}
	if len(cfg.Args) == 0 {
		cfg.Args = []string{"acp", "--stdio", "--process-per-session"}
	}
	return &Bridge{
		cfg:          cfg,
		pendingRPCs:  make(map[string]chan jsonRPCEnvelope),
		pendingPerms: make(map[string]*PendingPermission),
		ringCap:      defaultRingCapacity,
		subscribers:  make(map[uint64]chan protocol.EventEnvelope),
		closed:       make(chan struct{}),
	}
}

// Start launches the ACP worker subprocess and executes the initialize handshake.
func (b *Bridge) Start(ctx context.Context) error {
	b.mu.Lock()
	if b.started {
		b.mu.Unlock()
		return nil
	}

	cmd := exec.Command(b.cfg.BinaryPath, b.cfg.Args...)
	if len(b.cfg.ExtraEnv) > 0 {
		cmd.Env = append(os.Environ(), b.cfg.ExtraEnv...)
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		b.mu.Unlock()
		return fmt.Errorf("acp stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		b.mu.Unlock()
		return fmt.Errorf("acp stdout pipe: %w", err)
	}
	cmd.Stderr = io.Discard

	if err := cmd.Start(); err != nil {
		b.mu.Unlock()
		return fmt.Errorf("start %s %v: %w", b.cfg.BinaryPath, b.cfg.Args, err)
	}

	b.cmd = cmd
	b.stdin = stdin
	b.started = true
	b.mu.Unlock()

	go b.readLoop(stdout)
	go b.waitLoop(cmd)

	initParams := map[string]any{
		"protocolVersion": 1,
		"clientCapabilities": map[string]any{
			"fs": map[string]any{
				"readTextFile":  false,
				"writeTextFile": false,
			},
			"terminal": false,
		},
		"clientInfo": map[string]any{
			"name":    "agyd",
			"title":   "Antigravity Mobile Host Daemon",
			"version": "0.1.0",
		},
	}
	res, err := b.CallRaw(ctx, "initialize", initParams)
	if err != nil {
		_ = b.Close()
		return fmt.Errorf("acp initialize: %w", err)
	}

	b.mu.Lock()
	b.agentInfo = res
	b.mu.Unlock()
	return nil
}

func (b *Bridge) waitLoop(cmd *exec.Cmd) {
	_ = cmd.Wait()
	b.mu.Lock()
	b.started = false
	for id, ch := range b.pendingRPCs {
		select {
		case ch <- jsonRPCEnvelope{
			Error: &protocol.RPCError{Code: -32001, Message: "ACP subprocess exited"},
		}:
		default:
		}
		delete(b.pendingRPCs, id)
	}
	b.mu.Unlock()
}

func (b *Bridge) readLoop(stdout io.Reader) {
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), maxScannerTokenSize)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var env jsonRPCEnvelope
		if err := json.Unmarshal([]byte(line), &env); err != nil {
			continue
		}
		b.handleIncoming(env)
	}
}

func (b *Bridge) handleIncoming(env jsonRPCEnvelope) {
	// Notification from agent -> client
	if env.Method != "" && len(env.ID) == 0 {
		switch env.Method {
		case "session/update":
			var p struct {
				SessionID string          `json:"sessionId"`
				Update    json.RawMessage `json:"update"`
			}
			_ = json.Unmarshal(env.Params, &p)
			b.emitEvent(p.SessionID, "session_update", env.Params)
		default:
			b.emitEvent("", env.Method, env.Params)
		}
		return
	}

	// Inbound JSON-RPC request from agent -> client (e.g. session/request_permission)
	if env.Method != "" && len(env.ID) > 0 {
		if env.Method == "session/request_permission" {
			b.handlePermissionRequest(env)
			return
		}
		_ = b.writeLine(map[string]any{
			"jsonrpc": "2.0",
			"id":      json.RawMessage(env.ID),
			"error": map[string]any{
				"code":    -32601,
				"message": "unsupported client method: " + env.Method,
			},
		})
		return
	}

	// Response to our outbound request
	if len(env.ID) > 0 {
		key := string(env.ID)
		b.mu.Lock()
		ch, ok := b.pendingRPCs[key]
		if ok {
			delete(b.pendingRPCs, key)
		}
		b.mu.Unlock()
		if ok {
			ch <- env
		}
	}
}

func (b *Bridge) handlePermissionRequest(env jsonRPCEnvelope) {
	var params struct {
		SessionID string          `json:"sessionId"`
		ToolCall  json.RawMessage `json:"toolCall"`
		Options   json.RawMessage `json:"options"`
	}
	_ = json.Unmarshal(env.Params, &params)

	var rawID [8]byte
	_, _ = rand.Read(rawID[:])
	permID := "perm_" + hex.EncodeToString(rawID[:])

	perm := &PendingPermission{
		PermID:    permID,
		SessionID: params.SessionID,
		ToolCall:  params.ToolCall,
		Options:   params.Options,
		CreatedAt: time.Now().UTC(),
		rpcID:     append(json.RawMessage(nil), env.ID...),
	}

	b.permMu.Lock()
	b.pendingPerms[permID] = perm
	b.permMu.Unlock()

	payload, _ := json.Marshal(perm)
	b.emitEvent(params.SessionID, "permission_request", payload)
}

// RespondPermission resolves a pending session/request_permission call from mobile.
func (b *Bridge) RespondPermission(permID, optionID string, cancelled bool) error {
	b.permMu.Lock()
	perm, ok := b.pendingPerms[permID]
	if ok {
		delete(b.pendingPerms, permID)
	}
	b.permMu.Unlock()
	if !ok {
		return errors.New("pending permission request not found")
	}

	outcome := map[string]any{
		"outcome":  "selected",
		"optionId": optionID,
	}
	if cancelled || optionID == "" {
		outcome = map[string]any{
			"outcome": "cancelled",
		}
	}

	err := b.writeLine(map[string]any{
		"jsonrpc": "2.0",
		"id":      json.RawMessage(perm.rpcID),
		"result": map[string]any{
			"outcome": outcome,
		},
	})
	if err != nil {
		return err
	}

	resolvedPayload, _ := json.Marshal(map[string]any{
		"permId":    permID,
		"sessionId": perm.SessionID,
		"optionId":  optionID,
		"cancelled": cancelled,
	})
	b.emitEvent(perm.SessionID, "permission_resolved", resolvedPayload)
	return nil
}

// PendingPermissions returns unresolved permission prompts (optionally filtered by sessionID).
func (b *Bridge) PendingPermissions(sessionID string) []PendingPermission {
	b.permMu.Lock()
	defer b.permMu.Unlock()
	var out []PendingPermission
	for _, p := range b.pendingPerms {
		if sessionID == "" || p.SessionID == sessionID {
			out = append(out, *p)
		}
	}
	return out
}

func (b *Bridge) writeLine(v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	data = append(data, '\n')

	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.started || b.stdin == nil {
		return errors.New("acp bridge is not running")
	}
	_, err = b.stdin.Write(data)
	return err
}

// CallRaw sends an arbitrary JSON-RPC request to the agy acp subprocess and awaits its result.
func (b *Bridge) CallRaw(ctx context.Context, method string, params any) (json.RawMessage, error) {
	idNum := b.nextRPCID.Add(1)
	idRaw := json.RawMessage(fmt.Sprintf("%d", idNum))
	idKey := string(idRaw)

	ch := make(chan jsonRPCEnvelope, 1)
	b.mu.Lock()
	if !b.started {
		b.mu.Unlock()
		return nil, errors.New("acp subprocess not started")
	}
	b.pendingRPCs[idKey] = ch
	b.mu.Unlock()

	req := map[string]any{
		"jsonrpc": "2.0",
		"id":      idNum,
		"method":  method,
		"params":  params,
	}
	if params == nil {
		req["params"] = map[string]any{}
	}
	if err := b.writeLine(req); err != nil {
		b.mu.Lock()
		delete(b.pendingRPCs, idKey)
		b.mu.Unlock()
		return nil, err
	}

	select {
	case resp := <-ch:
		if resp.Error != nil {
			return nil, fmt.Errorf("acp %s (%d): %s", method, resp.Error.Code, resp.Error.Message)
		}
		if method != "initialize" {
			b.mu.Lock()
			b.authReady = true
			b.mu.Unlock()
		}
		return resp.Result, nil
	case <-ctx.Done():
		b.mu.Lock()
		delete(b.pendingRPCs, idKey)
		b.mu.Unlock()
		return nil, ctx.Err()
	}
}

// CallWithAuthRetry retries transient -32000 "Authentication required" errors right after startup.
func (b *Bridge) CallWithAuthRetry(ctx context.Context, method string, params any) (json.RawMessage, error) {
	var lastErr error
	for attempt := 0; attempt < 5; attempt++ {
		res, err := b.CallRaw(ctx, method, params)
		if err == nil {
			return res, nil
		}
		lastErr = err
		if !strings.Contains(err.Error(), "Authentication required") {
			return nil, err
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(400 * time.Millisecond):
		}
	}
	return nil, lastErr
}

// ListSessions calls ACP session/list and registers discovered session cwds in workspace manager.
func (b *Bridge) ListSessions(ctx context.Context, params json.RawMessage) (json.RawMessage, error) {
	var p any = map[string]any{}
	if len(params) > 0 {
		_ = json.Unmarshal(params, &p)
	}
	res, err := b.CallWithAuthRetry(ctx, "session/list", p)
	if err != nil {
		return nil, err
	}
	if b.cfg.Workspace != nil {
		var parsed struct {
			Sessions []struct {
				Cwd string `json:"cwd"`
			} `json:"sessions"`
		}
		if json.Unmarshal(res, &parsed) == nil {
			for _, s := range parsed.Sessions {
				if s.Cwd != "" {
					b.cfg.Workspace.AddRoot(s.Cwd)
				}
			}
		}
	}
	return res, nil
}

// NewSession starts a new ACP session with optional upload staging additionalDirectories.
func (b *Bridge) NewSession(ctx context.Context, params map[string]any) (json.RawMessage, error) {
	if params == nil {
		params = map[string]any{}
	}
	if cwd, _ := params["cwd"].(string); cwd != "" && b.cfg.Workspace != nil {
		b.cfg.Workspace.AddRoot(cwd)
	}
	if b.cfg.Uploads != nil {
		addDirs := toStringSlice(params["additionalDirectories"])
		addDirs = appendUnique(addDirs, b.cfg.Uploads.BaseDir())
		params["additionalDirectories"] = addDirs
	}
	if _, ok := params["mcpServers"]; !ok {
		params["mcpServers"] = []any{}
	}
	return b.CallWithAuthRetry(ctx, "session/new", params)
}

// LoadOrResumeSession forwards session/load or session/resume while attaching staging directories.
func (b *Bridge) LoadOrResumeSession(ctx context.Context, method string, params map[string]any) (json.RawMessage, error) {
	if params == nil {
		params = map[string]any{}
	}
	if cwd, _ := params["cwd"].(string); cwd != "" && b.cfg.Workspace != nil {
		b.cfg.Workspace.AddRoot(cwd)
	}
	if sid, _ := params["sessionId"].(string); sid != "" && b.cfg.Uploads != nil {
		if dir, err := b.cfg.Uploads.SessionDir(sid); err == nil {
			addDirs := toStringSlice(params["additionalDirectories"])
			addDirs = appendUnique(addDirs, dir)
			params["additionalDirectories"] = addDirs
		}
	}
	if _, ok := params["mcpServers"]; !ok {
		params["mcpServers"] = []any{}
	}
	return b.CallWithAuthRetry(ctx, method, params)
}

// CloseSession closes an ACP session and cleans up its staged /tmp uploads.
func (b *Bridge) CloseSession(ctx context.Context, sessionID string) (json.RawMessage, error) {
	res, err := b.CallWithAuthRetry(ctx, "session/close", map[string]any{"sessionId": sessionID})
	if b.cfg.Uploads != nil && sessionID != "" {
		_ = b.cfg.Uploads.CleanupSession(sessionID)
	}
	return res, err
}

// Prompt formats mobile text, @files, and staged /tmp uploads into ACP ContentBlocks.
func (b *Bridge) Prompt(ctx context.Context, req PromptParams) (json.RawMessage, error) {
	if req.SessionID == "" {
		return nil, errors.New("sessionId is required")
	}

	var sb strings.Builder
	sb.WriteString(strings.TrimSpace(req.Text))

	for _, f := range req.Files {
		f = strings.TrimSpace(f)
		if f != "" {
			sb.WriteString("\n\n[Attached workspace file: ")
			sb.WriteString(f)
			sb.WriteString("]")
		}
	}

	blocks := make([]map[string]any, 0, 1+len(req.UploadIDs))
	imageBlocks := make([]map[string]any, 0)

	if b.cfg.Uploads != nil {
		for _, uid := range req.UploadIDs {
			res, ok := b.cfg.Uploads.Get(req.SessionID, uid)
			if !ok {
				continue
			}
			sb.WriteString(fmt.Sprintf(
				"\n\n[Uploaded file staged in /tmp: %s (name: %s, size: %d bytes, mime: %s)]",
				res.RemotePath, res.Filename, res.SizeBytes, res.MimeType,
			))
			if res.IsImage && res.SizeBytes > 0 && res.SizeBytes <= maxInlineImageBytes {
				if raw, err := os.ReadFile(res.RemotePath); err == nil {
					imageBlocks = append(imageBlocks, map[string]any{
						"type":     "image",
						"data":     base64.StdEncoding.EncodeToString(raw),
						"mimeType": res.MimeType,
					})
				}
			}
		}
	}

	blocks = append(blocks, map[string]any{
		"type": "text",
		"text": strings.TrimSpace(sb.String()),
	})
	blocks = append(blocks, imageBlocks...)

	acpParams := map[string]any{
		"sessionId": req.SessionID,
		"prompt":    blocks,
	}

	if req.Sync {
		return b.CallWithAuthRetry(ctx, "session/prompt", acpParams)
	}

	var idRaw [6]byte
	_, _ = rand.Read(idRaw[:])
	turnID := "turn_" + hex.EncodeToString(idRaw[:])

	go func() {
		turnCtx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
		defer cancel()
		startPayload, _ := json.Marshal(map[string]any{"turnId": turnID})
		b.emitEvent(req.SessionID, "turn_started", startPayload)

		res, err := b.CallWithAuthRetry(turnCtx, "session/prompt", acpParams)
		if err != nil {
			errPayload, _ := json.Marshal(map[string]any{"turnId": turnID, "error": err.Error()})
			b.emitEvent(req.SessionID, "turn_error", errPayload)
			return
		}
		donePayload, _ := json.Marshal(map[string]any{"turnId": turnID, "result": json.RawMessage(res)})
		b.emitEvent(req.SessionID, "turn_complete", donePayload)
	}()

	ack, _ := json.Marshal(map[string]any{
		"accepted": true,
		"turnId":   turnID,
	})
	return ack, nil
}

// AuthReady returns whether ACP authenticated calls have succeeded.
func (b *Bridge) AuthReady() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.authReady
}

func (b *Bridge) emitEvent(sessionID, kind string, payload json.RawMessage) {
	seq := b.nextSeq.Add(1)
	ev := protocol.EventEnvelope{
		Seq:       seq,
		SessionID: sessionID,
		Timestamp: time.Now().UTC(),
		Kind:      kind,
		Payload:   payload,
	}

	b.evMu.Lock()
	b.ring = append(b.ring, ev)
	if len(b.ring) > b.ringCap {
		b.ring = append([]protocol.EventEnvelope(nil), b.ring[len(b.ring)-b.ringCap:]...)
	}
	for _, ch := range b.subscribers {
		select {
		case ch <- ev:
		default:
		}
	}
	b.evMu.Unlock()
}

// Subscribe returns buffered events with Seq > sinceSeq plus a live channel and unsubscribe callback.
func (b *Bridge) Subscribe(sinceSeq uint64, sessionIDs []string) ([]protocol.EventEnvelope, <-chan protocol.EventEnvelope, func()) {
	filter := make(map[string]struct{}, len(sessionIDs))
	for _, s := range sessionIDs {
		if s != "" {
			filter[s] = struct{}{}
		}
	}
	matches := func(ev protocol.EventEnvelope) bool {
		if len(filter) == 0 || ev.SessionID == "" {
			return true
		}
		_, ok := filter[ev.SessionID]
		return ok
	}

	subID := b.nextSubID.Add(1)
	ch := make(chan protocol.EventEnvelope, 128)

	b.evMu.Lock()
	var backlog []protocol.EventEnvelope
	for _, ev := range b.ring {
		if ev.Seq > sinceSeq && matches(ev) {
			backlog = append(backlog, ev)
		}
	}
	b.subscribers[subID] = ch
	b.evMu.Unlock()

	unsub := func() {
		b.evMu.Lock()
		delete(b.subscribers, subID)
		b.evMu.Unlock()
		close(ch)
	}
	return backlog, ch, unsub
}

// Close shuts down the ACP bridge and subprocess.
func (b *Bridge) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.stdin != nil {
		_ = b.stdin.Close()
		b.stdin = nil
	}
	if b.cmd != nil && b.cmd.Process != nil {
		_ = b.cmd.Process.Kill()
	}
	b.started = false
	return nil
}

func toStringSlice(v any) []string {
	raw, ok := v.([]any)
	if !ok {
		if ss, ok2 := v.([]string); ok2 {
			return append([]string(nil), ss...)
		}
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		if s, ok := item.(string); ok && s != "" {
			out = append(out, s)
		}
	}
	return out
}

func appendUnique(slice []string, val string) []string {
	for _, item := range slice {
		if item == val {
			return slice
		}
	}
	return append(slice, val)
}
