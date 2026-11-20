package daemon

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/acp"
	"github.com/antigravity/antigravity-mobile/server/pkg/p2p"
	"github.com/antigravity/antigravity-mobile/server/pkg/pairing"
	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/antigravity/antigravity-mobile/server/pkg/workspace"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

// Config configures an agyd host daemon instance.
type Config struct {
	ConfigDir         string
	ListenAddrs       []string
	StaticRelays      []string
	WorkspaceRoots    []string
	AgyBinary         string
	AgyArgs           []string
	EnableMDNS        bool
	ForcePrivate      bool
	AgyVersion        string
	ControlSocketPath string
	BrainDir          string
	UploadsDir        string
}

// Daemon coordinates libp2p networking, pairing allowlists, ACP sessions, and staged uploads.
type Daemon struct {
	cfg        Config
	hostname   string
	p2pHost    *p2p.ManagedHost
	allowlist  *pairing.Allowlist
	pairingMgr *pairing.Manager
	workspace  *workspace.Manager
	uploads    *workspace.UploadManager
	acp        *acp.Bridge

	ctrlListener net.Listener
	ctrlServer   *http.Server
	cancel       context.CancelFunc
}

// Start initializes all subsystems and begins accepting libp2p streams.
func Start(ctx context.Context, cfg Config) (*Daemon, error) {
	if cfg.ConfigDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		cfg.ConfigDir = filepath.Join(home, ".config", "agyd")
	}
	if err := os.MkdirAll(cfg.ConfigDir, 0o700); err != nil {
		return nil, err
	}
	if cfg.AgyVersion == "" {
		cfg.AgyVersion = "agy v1.5.13"
	}

	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "antigravity-host"
	}

	allowlist, err := pairing.NewAllowlist(filepath.Join(cfg.ConfigDir, "authorized_peers.json"))
	if err != nil {
		return nil, err
	}
	pairingMgr := pairing.NewManager(allowlist)

	wsMgr, err := workspace.NewManager(cfg.WorkspaceRoots, cfg.BrainDir)
	if err != nil {
		return nil, err
	}

	uploadsMgr, err := workspace.NewUploadManager(cfg.UploadsDir, 0, 0)
	if err != nil {
		return nil, err
	}

	mh, err := p2p.NewHost(ctx, p2p.HostConfig{
		IdentityPath:       filepath.Join(cfg.ConfigDir, "identity.key"),
		ListenAddrs:        cfg.ListenAddrs,
		StaticRelays:       cfg.StaticRelays,
		EnableMDNS:         cfg.EnableMDNS,
		EnableHolePunching: true,
		EnableNATPortMap:   true,
		ForcePrivate:       cfg.ForcePrivate,
	})
	if err != nil {
		return nil, err
	}

	bridge := acp.NewBridge(acp.Config{
		BinaryPath: cfg.AgyBinary,
		Args:       cfg.AgyArgs,
		Uploads:    uploadsMgr,
		Workspace:  wsMgr,
	})
	initCtx, initCancel := context.WithTimeout(ctx, 20*time.Second)
	err = bridge.Start(initCtx)
	initCancel()
	if err != nil {
		_ = mh.Close()
		return nil, fmt.Errorf("start acp bridge: %w", err)
	}

	runCtx, cancel := context.WithCancel(ctx)
	d := &Daemon{
		cfg:        cfg,
		hostname:   hostname,
		p2pHost:    mh,
		allowlist:  allowlist,
		pairingMgr: pairingMgr,
		workspace:  wsMgr,
		uploads:    uploadsMgr,
		acp:        bridge,
		cancel:     cancel,
	}

	mh.Host.SetStreamHandler(protocol.ProtoPair, d.handlePairStream)
	mh.Host.SetStreamHandler(protocol.ProtoRPC, d.handleRPCStream)
	mh.Host.SetStreamHandler(protocol.ProtoEvents, d.handleEventsStream)
	mh.Host.SetStreamHandler(protocol.ProtoBlob, d.handleBlobStream)

	go uploadsMgr.StartReaper(runCtx, workspace.DefaultUploadTTL)

	if cfg.ControlSocketPath != "" {
		if err := d.startControlSocket(cfg.ControlSocketPath); err != nil {
			_ = d.Close()
			return nil, err
		}
	}

	return d, nil
}

// Host returns the underlying ManagedHost.
func (d *Daemon) Host() *p2p.ManagedHost { return d.p2pHost }

// Allowlist returns the peer allowlist store.
func (d *Daemon) Allowlist() *pairing.Allowlist { return d.allowlist }

// PairingManager returns the pairing manager.
func (d *Daemon) PairingManager() *pairing.Manager { return d.pairingMgr }

// HostInfo builds a HostInfo snapshot.
func (d *Daemon) HostInfo() protocol.HostInfo {
	cpuPct, ramPct := ReadSystemUsage()
	return protocol.HostInfo{
		HostPeerID:     d.p2pHost.Host.ID().String(),
		Hostname:       d.hostname,
		OS:             runtime.GOOS,
		Arch:           runtime.GOARCH,
		AgyVersion:     d.cfg.AgyVersion,
		WorkspaceRoots: d.workspace.Roots(),
		ListenAddrs:    d.p2pHost.DirectAddrs(),
		RelayAddrs:     d.p2pHost.RelayCircuitAddrs(),
		NATStatus:      d.p2pHost.NATStatus(),
		CPUPercent:     cpuPct,
		RAMPercent:     ramPct,
		AuthReady:      d.acp.AuthReady(),
	}
}

// CreatePairInvite issues a single-use pairing invite + QR URI.
func (d *Daemon) CreatePairInvite(ttl time.Duration, trustNext bool) (*protocol.PairInvite, error) {
	tok, err := d.pairingMgr.CreateToken(ttl, trustNext)
	if err != nil {
		return nil, err
	}
	relays := d.p2pHost.RelayCircuitAddrs()
	direct := d.p2pHost.DirectAddrs()
	uri := pairing.BuildPairURI(d.p2pHost.Host.ID().String(), d.hostname, tok.Token, relays, direct)
	return &protocol.PairInvite{
		Token:      tok.Token,
		Pin:        tok.Pin,
		URI:        uri,
		HostPeerID: d.p2pHost.Host.ID().String(),
		HostName:   d.hostname,
		RelayAddrs: relays,
		LANAddrs:   direct,
		ExpiresAt:  tok.ExpiresAt.Format(time.RFC3339),
	}, nil
}

func (d *Daemon) handlePairStream(s network.Stream) {
	defer s.Close()
	_ = s.SetDeadline(time.Now().Add(3 * time.Minute))

	var req protocol.PairRequest
	if err := protocol.ReadJSON(s, &req); err != nil {
		return
	}

	remote := s.Conn().RemotePeer()
	sess, err := d.pairingMgr.StartHandshake(d.p2pHost.Host.ID(), remote, req)
	if err != nil {
		_ = protocol.WriteJSON(s, protocol.PairChallenge{Error: err.Error()})
		return
	}

	err = protocol.WriteJSON(s, protocol.PairChallenge{
		SessionID:  sess.SessionID,
		HostPeerID: d.p2pHost.Host.ID().String(),
		HostName:   d.hostname,
		SASDigits:  sess.SASDigits,
		SASEmojis:  sess.SASEmojis,
	})
	if err != nil {
		return
	}

	var confirm protocol.PairConfirm
	if err := protocol.ReadJSON(s, &confirm); err != nil {
		return
	}
	ok, err := d.pairingMgr.CompleteHandshake(sess.SessionID, confirm.Accept, 2*time.Minute)
	if err != nil {
		_ = protocol.WriteJSON(s, protocol.PairResult{Paired: false, Error: err.Error()})
		return
	}
	if !ok {
		_ = protocol.WriteJSON(s, protocol.PairResult{Paired: false, Error: "pairing rejected"})
		return
	}

	_ = protocol.WriteJSON(s, protocol.PairResult{
		Paired:     true,
		HostPeerID: d.p2pHost.Host.ID().String(),
		HostName:   d.hostname,
		HostOS:     runtime.GOOS + " · " + runtime.GOARCH,
		AgyVersion: d.cfg.AgyVersion,
		RelayAddrs: d.p2pHost.RelayCircuitAddrs(),
	})
}

func (d *Daemon) handleRPCStream(s network.Stream) {
	defer s.Close()
	remote := s.Conn().RemotePeer()
	if !d.allowlist.IsAllowed(remote) {
		_ = s.Reset()
		return
	}
	d.allowlist.Touch(remote)

	for {
		var req protocol.RPCRequest
		if err := protocol.ReadJSON(s, &req); err != nil {
			return
		}
		resp := d.dispatchRPC(req)
		if err := protocol.WriteJSON(s, resp); err != nil {
			return
		}
	}
}

func (d *Daemon) dispatchRPC(req protocol.RPCRequest) protocol.RPCResponse {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	makeErr := func(code int, msg string) protocol.RPCResponse {
		return protocol.RPCResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Error:   &protocol.RPCError{Code: code, Message: msg},
		}
	}
	makeOK := func(v any) protocol.RPCResponse {
		if raw, ok := v.(json.RawMessage); ok {
			return protocol.RPCResponse{JSONRPC: "2.0", ID: req.ID, Result: raw}
		}
		b, err := json.Marshal(v)
		if err != nil {
			return makeErr(-32603, err.Error())
		}
		return protocol.RPCResponse{JSONRPC: "2.0", ID: req.ID, Result: b}
	}

	switch req.Method {
	case "host/info":
		return makeOK(d.HostInfo())

	case "session/list":
		res, err := d.acp.ListSessions(ctx, req.Params)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(res)

	case "session/new":
		var params map[string]any
		_ = json.Unmarshal(req.Params, &params)
		res, err := d.acp.NewSession(ctx, params)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(res)

	case "session/load", "session/resume":
		var params map[string]any
		_ = json.Unmarshal(req.Params, &params)
		res, err := d.acp.LoadOrResumeSession(ctx, req.Method, params)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(res)

	case "session/close":
		var p struct {
			SessionID string `json:"sessionId"`
		}
		_ = json.Unmarshal(req.Params, &p)
		res, err := d.acp.CloseSession(ctx, p.SessionID)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(res)

	case "session/set_mode", "session/set_model", "session/set_config_option", "session/cancel":
		var params map[string]any
		_ = json.Unmarshal(req.Params, &params)
		res, err := d.acp.CallWithAuthRetry(ctx, req.Method, params)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(res)

	case "session/prompt":
		var p acp.PromptParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return makeErr(-32602, err.Error())
		}
		res, err := d.acp.Prompt(ctx, p)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(res)

	case "session/respond_permission":
		var p struct {
			PermID    string `json:"permId"`
			OptionID  string `json:"optionId"`
			Cancelled bool   `json:"cancelled"`
		}
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return makeErr(-32602, err.Error())
		}
		if err := d.acp.RespondPermission(p.PermID, p.OptionID, p.Cancelled); err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]bool{"ok": true})

	case "session/pending_permissions":
		var p struct {
			SessionID string `json:"sessionId"`
		}
		_ = json.Unmarshal(req.Params, &p)
		return makeOK(map[string]any{"permissions": d.acp.PendingPermissions(p.SessionID)})

	case "workspace/tree":
		var p struct {
			Root string `json:"root"`
			Path string `json:"path"`
		}
		_ = json.Unmarshal(req.Params, &p)
		entries, err := d.workspace.ListTree(p.Root, p.Path)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]any{"entries": entries})

	case "workspace/read_file":
		var p struct {
			Root     string `json:"root"`
			Path     string `json:"path"`
			MaxBytes int64  `json:"maxBytes"`
		}
		_ = json.Unmarshal(req.Params, &p)
		content, truncated, err := d.workspace.ReadFile(p.Root, p.Path, p.MaxBytes)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]any{"content": content, "truncated": truncated})

	case "workspace/git_status":
		var p struct {
			Cwd string `json:"cwd"`
		}
		_ = json.Unmarshal(req.Params, &p)
		changes, err := d.workspace.GitStatus(ctx, p.Cwd)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]any{"changes": changes})

	case "workspace/git_diff":
		var p struct {
			Cwd  string `json:"cwd"`
			Path string `json:"path"`
		}
		_ = json.Unmarshal(req.Params, &p)
		diff, err := d.workspace.GitDiff(ctx, p.Cwd, p.Path)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]any{"diff": diff})

	case "workspace/list_tmp_files":
		var p struct {
			SessionID string `json:"sessionId"`
		}
		_ = json.Unmarshal(req.Params, &p)
		return makeOK(map[string]any{"files": d.uploads.List(p.SessionID)})

	case "workspace/delete_tmp_file":
		var p struct {
			SessionID string `json:"sessionId"`
			UploadID  string `json:"uploadId"`
		}
		_ = json.Unmarshal(req.Params, &p)
		if err := d.uploads.Delete(p.SessionID, p.UploadID); err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]bool{"deleted": true})

	case "artifacts/list":
		var p struct {
			SessionID string `json:"sessionId"`
		}
		_ = json.Unmarshal(req.Params, &p)
		items, err := d.workspace.ListArtifacts(p.SessionID)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]any{"artifacts": items})

	case "artifacts/read":
		var p struct {
			SessionID string `json:"sessionId"`
			Name      string `json:"name"`
		}
		_ = json.Unmarshal(req.Params, &p)
		content, err := d.workspace.ReadArtifact(p.SessionID, p.Name)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		return makeOK(map[string]any{"content": content})

	case "peers/list":
		return makeOK(map[string]any{"peers": d.allowlist.List()})

	case "peers/revoke":
		var p struct {
			PeerID string `json:"peerId"`
		}
		_ = json.Unmarshal(req.Params, &p)
		pid, err := peer.Decode(p.PeerID)
		if err != nil {
			return makeErr(-32602, err.Error())
		}
		removed, err := d.allowlist.Revoke(pid)
		if err != nil {
			return makeErr(-32000, err.Error())
		}
		if removed {
			_ = d.p2pHost.Host.Network().ClosePeer(pid)
		}
		return makeOK(map[string]bool{"revoked": removed})

	default:
		return makeErr(-32601, "unknown RPC method: "+req.Method)
	}
}

func (d *Daemon) handleEventsStream(s network.Stream) {
	defer s.Close()
	remote := s.Conn().RemotePeer()
	if !d.allowlist.IsAllowed(remote) {
		_ = s.Reset()
		return
	}
	d.allowlist.Touch(remote)

	var subReq protocol.EventsSubscribeRequest
	if err := protocol.ReadJSON(s, &subReq); err != nil {
		return
	}

	backlog, ch, unsub := d.acp.Subscribe(subReq.SinceSeq, subReq.SessionIDs)
	defer unsub()

	for _, ev := range backlog {
		if err := protocol.WriteJSON(s, ev); err != nil {
			return
		}
	}

	// Ensure unresolved pending permissions are re-emitted on reconnect even if older than sinceSeq.
	for _, perm := range d.acp.PendingPermissions("") {
		payload, _ := json.Marshal(perm)
		if err := protocol.WriteJSON(s, protocol.EventEnvelope{
			Seq:       0,
			SessionID: perm.SessionID,
			Timestamp: time.Now().UTC(),
			Kind:      "permission_request",
			Payload:   payload,
		}); err != nil {
			return
		}
	}

	if err := protocol.WriteJSON(s, protocol.EventEnvelope{
		Timestamp: time.Now().UTC(),
		Kind:      "replay_complete",
	}); err != nil {
		return
	}

	heartbeat := time.NewTicker(15 * time.Second)
	defer heartbeat.Stop()

	for {
		select {
		case ev, ok := <-ch:
			if !ok {
				return
			}
			if err := protocol.WriteJSON(s, ev); err != nil {
				return
			}
		case <-heartbeat.C:
			if err := protocol.WriteJSON(s, protocol.EventEnvelope{
				Timestamp: time.Now().UTC(),
				Kind:      "heartbeat",
			}); err != nil {
				return
			}
		}
	}
}

func (d *Daemon) handleBlobStream(s network.Stream) {
	defer s.Close()
	remote := s.Conn().RemotePeer()
	if !d.allowlist.IsAllowed(remote) {
		_ = s.Reset()
		return
	}
	d.allowlist.Touch(remote)

	var hdr protocol.BlobUploadHeader
	if err := protocol.ReadJSON(s, &hdr); err != nil {
		return
	}

	pr, pw := io.Pipe()
	go func() {
		defer pw.Close()
		for {
			chunk, err := protocol.ReadFrame(s)
			if err != nil {
				_ = pw.CloseWithError(err)
				return
			}
			if len(chunk) == 0 {
				return
			}
			if _, wErr := pw.Write(chunk); wErr != nil {
				return
			}
		}
	}()

	res, err := d.uploads.SaveStream(hdr.SessionID, hdr.Filename, hdr.MimeType, pr, hdr.SHA256)
	if err != nil {
		_ = protocol.WriteJSON(s, map[string]string{"error": err.Error()})
		return
	}
	_ = protocol.WriteJSON(s, res)
}

func (d *Daemon) startControlSocket(sockPath string) error {
	if err := os.MkdirAll(filepath.Dir(sockPath), 0o700); err != nil {
		return err
	}
	_ = os.Remove(sockPath)
	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return err
	}
	_ = os.Chmod(sockPath, 0o600)

	mux := http.NewServeMux()
	mux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(d.HostInfo())
	})
	mux.HandleFunc("/pair", func(w http.ResponseWriter, r *http.Request) {
		trustNext := r.URL.Query().Get("trust") == "1"
		inv, err := d.CreatePairInvite(5*time.Minute, trustNext)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		_ = json.NewEncoder(w).Encode(inv)
	})
	mux.HandleFunc("/pair/approve", func(w http.ResponseWriter, r *http.Request) {
		sid := r.URL.Query().Get("session")
		accept := r.URL.Query().Get("accept") == "1"
		if err := d.pairingMgr.ApproveHostDecision(sid, accept); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	})
	mux.HandleFunc("/peers", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(d.allowlist.List())
	})
	mux.HandleFunc("/peers/revoke", func(w http.ResponseWriter, r *http.Request) {
		pidStr := strings.TrimSpace(r.URL.Query().Get("peer"))
		pid, err := peer.Decode(pidStr)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		ok, err := d.allowlist.Revoke(pid)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		if ok {
			_ = d.p2pHost.Host.Network().ClosePeer(pid)
		}
		_ = json.NewEncoder(w).Encode(map[string]bool{"revoked": ok})
	})

	srv := &http.Server{Handler: mux}
	d.ctrlListener = ln
	d.ctrlServer = srv
	go func() {
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			_ = err
		}
	}()
	return nil
}

// Close shuts down the control socket, ACP bridge, and libp2p host.
func (d *Daemon) Close() error {
	if d.cancel != nil {
		d.cancel()
	}
	if d.ctrlServer != nil {
		_ = d.ctrlServer.Close()
	}
	if d.ctrlListener != nil {
		_ = d.ctrlListener.Close()
	}
	if d.cfg.ControlSocketPath != "" {
		_ = os.Remove(d.cfg.ControlSocketPath)
	}
	if d.acp != nil {
		_ = d.acp.Close()
	}
	if d.p2pHost != nil {
		_ = d.p2pHost.Close()
	}
	return nil
}
