package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/antigravity/antigravity-mobile/server/pkg/p2p"
	"github.com/antigravity/antigravity-mobile/server/pkg/pairing"
	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

type nodeStartCfg struct {
	IdentityPath       string   `json:"identityPath"`
	StaticRelays       []string `json:"staticRelays"`
	EnableMDNS         bool     `json:"enableMdns"`
	ForcePrivate       bool     `json:"forcePrivate"`
	EnableHolePunching bool     `json:"enableHolePunching"`
}

type connectParams struct {
	PeerID      string   `json:"peerId"`
	DirectAddrs []string `json:"directAddrs"`
	RelayAddrs  []string `json:"relayAddrs"`
}

type pairStartParams struct {
	URI         string   `json:"uri"`
	HostPeerID  string   `json:"hostPeerId"`
	DirectAddrs []string `json:"directAddrs"`
	RelayAddrs  []string `json:"relayAddrs"`
	Token       string   `json:"token"`
	Pin         string   `json:"pin"`
	DeviceName  string   `json:"deviceName"`
}

type peerRPCClient struct {
	mu     sync.Mutex
	stream network.Stream
}

type bridgeState struct {
	mu          sync.Mutex
	ctx         context.Context
	cancel      context.CancelFunc
	mh          *p2p.ManagedHost
	rpcClients  map[peer.ID]*peerRPCClient
	evCancels   map[peer.ID]context.CancelFunc
	pairStreams map[string]network.Stream
	eventsCh    chan string
	rpcSeq      atomic.Uint64
}

var globalBridge = &bridgeState{
	rpcClients:  make(map[peer.ID]*peerRPCClient),
	evCancels:   make(map[peer.ID]context.CancelFunc),
	pairStreams: make(map[string]network.Stream),
}

func toCJSON(v any) *C.char {
	b, err := json.Marshal(v)
	if err != nil {
		b = []byte(fmt.Sprintf(`{"ok":false,"error":%q}`, err.Error()))
	}
	return C.CString(string(b))
}

func errC(msg string) *C.char {
	return toCJSON(map[string]any{"ok": false, "error": msg})
}

func (b *bridgeState) pushEvent(ev any) {
	raw, err := json.Marshal(ev)
	if err != nil {
		return
	}
	b.mu.Lock()
	ch := b.eventsCh
	b.mu.Unlock()
	if ch == nil {
		return
	}
	select {
	case ch <- string(raw):
	default:
	}
}

func (b *bridgeState) getHost() (*p2p.ManagedHost, context.Context, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.mh == nil || b.ctx == nil {
		return nil, nil, errors.New("libp2p node not started")
	}
	return b.mh, b.ctx, nil
}

//export AgyFreeString
func AgyFreeString(ptr *C.char) {
	if ptr != nil {
		C.free(unsafe.Pointer(ptr))
	}
}

//export AgyNodeStart
func AgyNodeStart(configJSON *C.char) *C.char {
	var cfg nodeStartCfg
	if configJSON != nil {
		raw := C.GoString(configJSON)
		if raw != "" {
			if err := json.Unmarshal([]byte(raw), &cfg); err != nil {
				return errC("invalid config JSON: " + err.Error())
			}
		}
	}

	globalBridge.mu.Lock()
	if globalBridge.mh != nil {
		id := globalBridge.mh.Host.ID().String()
		addrs := globalBridge.mh.DirectAddrs()
		globalBridge.mu.Unlock()
		return toCJSON(map[string]any{
			"ok":     true,
			"peerId": id,
			"addrs":  addrs,
		})
	}

	ctx, cancel := context.WithCancel(context.Background())
	mh, err := p2p.NewHost(ctx, p2p.HostConfig{
		IdentityPath:       cfg.IdentityPath,
		StaticRelays:       cfg.StaticRelays,
		EnableMDNS:         cfg.EnableMDNS,
		EnableHolePunching: cfg.EnableHolePunching,
		EnableNATPortMap:   true,
		ForcePrivate:       cfg.ForcePrivate,
	})
	if err != nil {
		cancel()
		globalBridge.mu.Unlock()
		return errC(err.Error())
	}

	globalBridge.ctx = ctx
	globalBridge.cancel = cancel
	globalBridge.mh = mh
	globalBridge.eventsCh = make(chan string, 4096)
	globalBridge.rpcClients = make(map[peer.ID]*peerRPCClient)
	globalBridge.evCancels = make(map[peer.ID]context.CancelFunc)
	globalBridge.pairStreams = make(map[string]network.Stream)
	globalBridge.mu.Unlock()

	return toCJSON(map[string]any{
		"ok":     true,
		"peerId": mh.Host.ID().String(),
		"addrs":  mh.DirectAddrs(),
	})
}

//export AgyNodeStop
func AgyNodeStop() *C.char {
	globalBridge.mu.Lock()
	if globalBridge.cancel != nil {
		globalBridge.cancel()
	}
	for _, fn := range globalBridge.evCancels {
		fn()
	}
	for _, rc := range globalBridge.rpcClients {
		rc.mu.Lock()
		if rc.stream != nil {
			_ = rc.stream.Reset()
			rc.stream = nil
		}
		rc.mu.Unlock()
	}
	for _, ps := range globalBridge.pairStreams {
		_ = ps.Reset()
	}
	mh := globalBridge.mh
	globalBridge.mh = nil
	globalBridge.cancel = nil
	globalBridge.ctx = nil
	globalBridge.eventsCh = nil
	globalBridge.mu.Unlock()

	if mh != nil {
		_ = mh.Close()
	}
	return toCJSON(map[string]any{"ok": true})
}

//export AgyConnectHost
func AgyConnectHost(paramsJSON *C.char) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	var p connectParams
	if paramsJSON == nil {
		return errC("missing params")
	}
	if err := json.Unmarshal([]byte(C.GoString(paramsJSON)), &p); err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(p.PeerID)
	if err != nil {
		return errC("invalid peerId: " + err.Error())
	}

	dialCtx, cancel := context.WithTimeout(baseCtx, 20*time.Second)
	defer cancel()
	diag, err := p2p.RaceDial(dialCtx, mh.Host, pid, p.DirectAddrs, p.RelayAddrs)
	if err != nil {
		return errC(err.Error())
	}
	return toCJSON(map[string]any{
		"ok":          true,
		"diagnostics": diag,
	})
}

//export AgyDisconnectHost
func AgyDisconnectHost(peerIDPtr *C.char) *C.char {
	mh, _, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(C.GoString(peerIDPtr))
	if err != nil {
		return errC(err.Error())
	}

	globalBridge.mu.Lock()
	if cancelFn, ok := globalBridge.evCancels[pid]; ok {
		cancelFn()
		delete(globalBridge.evCancels, pid)
	}
	if rc, ok := globalBridge.rpcClients[pid]; ok {
		rc.mu.Lock()
		if rc.stream != nil {
			_ = rc.stream.Reset()
			rc.stream = nil
		}
		rc.mu.Unlock()
		delete(globalBridge.rpcClients, pid)
	}
	globalBridge.mu.Unlock()

	_ = mh.Host.Network().ClosePeer(pid)
	return toCJSON(map[string]any{"ok": true})
}

//export AgyDiagnostics
func AgyDiagnostics(peerIDPtr *C.char) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(C.GoString(peerIDPtr))
	if err != nil {
		return errC(err.Error())
	}
	ctx, cancel := context.WithTimeout(baseCtx, 4*time.Second)
	defer cancel()
	diag := p2p.InspectConnection(ctx, mh.Host, pid)
	return toCJSON(map[string]any{
		"ok":          true,
		"diagnostics": diag,
	})
}

//export AgyRetryHolePunch
func AgyRetryHolePunch(peerIDPtr *C.char) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(C.GoString(peerIDPtr))
	if err != nil {
		return errC(err.Error())
	}
	ctx, cancel := context.WithTimeout(baseCtx, 6*time.Second)
	defer cancel()

	// Filter non-circuit peerstore addresses and attempt direct upgrade.
	var direct []peer.AddrInfo
	var directAddrs []string
	for _, a := range mh.Host.Peerstore().Addrs(pid) {
		if len(a.String()) > 0 && !containsCircuit(a.String()) {
			directAddrs = append(directAddrs, a.String())
		}
	}
	_ = direct
	if len(directAddrs) > 0 {
		if _, err := p2p.RaceDial(ctx, mh.Host, pid, directAddrs, nil); err == nil {
			diag := p2p.InspectConnection(ctx, mh.Host, pid)
			return toCJSON(map[string]any{
				"ok":          true,
				"diagnostics": diag,
				"message":     "Hole-punch check completed (" + diag.PathType + ")",
			})
		}
	}
	diag := p2p.InspectConnection(ctx, mh.Host, pid)
	return toCJSON(map[string]any{
		"ok":          true,
		"diagnostics": diag,
		"message":     "Direct hole-punch blocked by NAT; maintaining Circuit Relay v2",
	})
}

func containsCircuit(s string) bool {
	return len(s) >= 12 && (func() bool {
		for i := 0; i+12 <= len(s); i++ {
			if s[i:i+12] == "/p2p-circuit" {
				return true
			}
		}
		return false
	})()
}

//export AgyDiscoverLAN
func AgyDiscoverLAN(timeoutMs C.int) *C.char {
	mh, _, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	if timeoutMs > 0 {
		time.Sleep(time.Duration(timeoutMs) * time.Millisecond)
	}
	return toCJSON(map[string]any{
		"ok":    true,
		"peers": mh.LANDiscovered(),
	})
}

//export AgyPairStart
func AgyPairStart(paramsJSON *C.char) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	var p pairStartParams
	if paramsJSON == nil {
		return errC("missing pair params")
	}
	if err := json.Unmarshal([]byte(C.GoString(paramsJSON)), &p); err != nil {
		return errC(err.Error())
	}

	if p.URI != "" {
		parsed, err := pairing.ParsePairURI(p.URI)
		if err != nil {
			return errC(err.Error())
		}
		p.HostPeerID = parsed.HostPeerID
		p.Token = parsed.Token
		p.RelayAddrs = append(p.RelayAddrs, parsed.RelayAddrs...)
		p.DirectAddrs = append(p.DirectAddrs, parsed.DirectAddrs...)
	}

	hostPID, err := peer.Decode(p.HostPeerID)
	if err != nil {
		return errC("invalid hostPeerId: " + err.Error())
	}
	if p.DeviceName == "" {
		p.DeviceName = "Android Device"
	}

	ctx, cancel := context.WithTimeout(baseCtx, 25*time.Second)
	defer cancel()
	if _, err := p2p.RaceDial(ctx, mh.Host, hostPID, p.DirectAddrs, p.RelayAddrs); err != nil {
		return errC(err.Error())
	}

	s, err := p2p.OpenStream(ctx, mh.Host, hostPID, protocol.ProtoPair)
	if err != nil {
		return errC("open pair stream: " + err.Error())
	}
	_ = s.SetDeadline(time.Now().Add(3 * time.Minute))

	if err := protocol.WriteJSON(s, protocol.PairRequest{
		Token:      p.Token,
		DeviceName: p.DeviceName,
		Pin:        p.Pin,
	}); err != nil {
		_ = s.Reset()
		return errC("send pair request: " + err.Error())
	}

	var chal protocol.PairChallenge
	if err := protocol.ReadJSON(s, &chal); err != nil {
		_ = s.Reset()
		return errC("read pair challenge: " + err.Error())
	}
	if chal.Error != "" {
		_ = s.Reset()
		return errC(chal.Error)
	}

	globalBridge.mu.Lock()
	globalBridge.pairStreams[chal.SessionID] = s
	globalBridge.mu.Unlock()

	return toCJSON(map[string]any{
		"ok":        true,
		"challenge": chal,
	})
}

//export AgyPairConfirm
func AgyPairConfirm(pairSessionPtr *C.char, accept C.int) *C.char {
	sid := C.GoString(pairSessionPtr)
	globalBridge.mu.Lock()
	s, ok := globalBridge.pairStreams[sid]
	if ok {
		delete(globalBridge.pairStreams, sid)
	}
	globalBridge.mu.Unlock()
	if !ok {
		return errC("pairing session not found")
	}
	defer s.Close()

	if err := protocol.WriteJSON(s, protocol.PairConfirm{
		SessionID: sid,
		Accept:    accept != 0,
	}); err != nil {
		return errC(err.Error())
	}

	var res protocol.PairResult
	if err := protocol.ReadJSON(s, &res); err != nil {
		return errC(err.Error())
	}
	if res.Error != "" {
		return errC(res.Error)
	}
	return toCJSON(map[string]any{
		"ok":     true,
		"result": res,
	})
}

func (b *bridgeState) getRPCClient(pid peer.ID) *peerRPCClient {
	b.mu.Lock()
	defer b.mu.Unlock()
	rc, ok := b.rpcClients[pid]
	if !ok {
		rc = &peerRPCClient{}
		b.rpcClients[pid] = rc
	}
	return rc
}

//export AgyRPCCall
func AgyRPCCall(peerIDPtr *C.char, methodPtr *C.char, paramsJSONPtr *C.char) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(C.GoString(peerIDPtr))
	if err != nil {
		return errC("invalid peerId: " + err.Error())
	}
	method := C.GoString(methodPtr)
	var rawParams json.RawMessage
	if paramsJSONPtr != nil {
		s := C.GoString(paramsJSONPtr)
		if s != "" {
			rawParams = json.RawMessage(s)
		}
	}

	rc := globalBridge.getRPCClient(pid)
	rc.mu.Lock()
	defer rc.mu.Unlock()

	id := globalBridge.rpcSeq.Add(1)
	req := protocol.RPCRequest{
		JSONRPC: "2.0",
		ID:      id,
		Method:  method,
		Params:  rawParams,
	}

	var resp protocol.RPCResponse
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		if rc.stream == nil {
			sCtx, cancel := context.WithTimeout(baseCtx, 12*time.Second)
			s, openErr := p2p.OpenStream(sCtx, mh.Host, pid, protocol.ProtoRPC)
			cancel()
			if openErr != nil {
				lastErr = openErr
				continue
			}
			rc.stream = s
		}

		rpcTimeout := 45 * time.Second
		if method == "session/load" || method == "session/resume" {
			rpcTimeout = 120 * time.Second
		}
		_ = rc.stream.SetDeadline(time.Now().Add(rpcTimeout))
		if err := protocol.WriteJSON(rc.stream, req); err != nil {
			_ = rc.stream.Reset()
			rc.stream = nil
			lastErr = err
			continue
		}
		if err := protocol.ReadJSON(rc.stream, &resp); err != nil {
			_ = rc.stream.Reset()
			rc.stream = nil
			lastErr = err
			if method == "session/load" || method == "session/resume" {
				break
			}
			continue
		}
		lastErr = nil
		break
	}

	if lastErr != nil {
		return errC(lastErr.Error())
	}
	if resp.Error != nil {
		return errC(resp.Error.Message)
	}
	return toCJSON(map[string]any{
		"ok":     true,
		"result": resp.Result,
	})
}

//export AgySubscribeEvents
func AgySubscribeEvents(peerIDPtr *C.char, sinceSeq C.ulonglong) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(C.GoString(peerIDPtr))
	if err != nil {
		return errC(err.Error())
	}

	globalBridge.mu.Lock()
	if prevCancel, ok := globalBridge.evCancels[pid]; ok {
		prevCancel()
	}
	subCtx, cancel := context.WithCancel(baseCtx)
	globalBridge.evCancels[pid] = cancel
	globalBridge.mu.Unlock()

	s, err := p2p.OpenStream(subCtx, mh.Host, pid, protocol.ProtoEvents)
	if err != nil {
		cancel()
		return errC(err.Error())
	}
	if err := protocol.WriteJSON(s, protocol.EventsSubscribeRequest{
		SinceSeq: uint64(sinceSeq),
	}); err != nil {
		_ = s.Reset()
		cancel()
		return errC(err.Error())
	}

	go func() {
		defer s.Close()
		defer cancel()
		for {
			select {
			case <-subCtx.Done():
				return
			default:
			}
			_ = s.SetReadDeadline(time.Now().Add(45 * time.Second))
			var ev protocol.EventEnvelope
			if err := protocol.ReadJSON(s, &ev); err != nil {
				if subCtx.Err() == nil {
					globalBridge.pushEvent(map[string]any{
						"type":   "events_disconnected",
						"peerId": pid.String(),
						"error":  err.Error(),
					})
				}
				return
			}
			globalBridge.pushEvent(map[string]any{
				"type":   "acp_event",
				"peerId": pid.String(),
				"event":  ev,
			})
		}
	}()

	return toCJSON(map[string]any{"ok": true})
}

//export AgyPollEvent
func AgyPollEvent(timeoutMs C.int) *C.char {
	globalBridge.mu.Lock()
	ch := globalBridge.eventsCh
	globalBridge.mu.Unlock()
	if ch == nil {
		return C.CString("")
	}
	d := time.Duration(timeoutMs) * time.Millisecond
	if d <= 0 {
		d = 250 * time.Millisecond
	}
	timer := time.NewTimer(d)
	defer timer.Stop()

	select {
	case msg := <-ch:
		return C.CString(msg)
	case <-timer.C:
		return C.CString("")
	}
}

//export AgyUploadFile
func AgyUploadFile(peerIDPtr *C.char, sessionIDPtr *C.char, localPathPtr *C.char, filenamePtr *C.char, mimePtr *C.char) *C.char {
	mh, baseCtx, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	pid, err := peer.Decode(C.GoString(peerIDPtr))
	if err != nil {
		return errC("invalid peerId: " + err.Error())
	}
	sessionID := C.GoString(sessionIDPtr)
	localPath := C.GoString(localPathPtr)
	filename := C.GoString(filenamePtr)
	mimeType := C.GoString(mimePtr)
	if filename == "" {
		filename = filepath.Base(localPath)
	}

	f, err := os.Open(localPath)
	if err != nil {
		return errC("open file: " + err.Error())
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return errC("stat file: " + err.Error())
	}
	hasher := sha256.New()
	if _, err := io.Copy(hasher, f); err != nil {
		return errC("hash file: " + err.Error())
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return errC("rewind file: " + err.Error())
	}
	shaHex := hex.EncodeToString(hasher.Sum(nil))

	sCtx, cancel := context.WithTimeout(baseCtx, 5*time.Minute)
	defer cancel()
	s, err := p2p.OpenStream(sCtx, mh.Host, pid, protocol.ProtoBlob)
	if err != nil {
		return errC("open blob stream: " + err.Error())
	}
	defer s.Close()
	_ = s.SetDeadline(time.Now().Add(5 * time.Minute))

	hdr := protocol.BlobUploadHeader{
		SessionID:  sessionID,
		Filename:   filename,
		MimeType:   mimeType,
		TotalBytes: info.Size(),
		SHA256:     shaHex,
	}
	if err := protocol.WriteJSON(s, hdr); err != nil {
		return errC("send blob header: " + err.Error())
	}

	buf := make([]byte, 64*1024)
	var sent int64
	for {
		n, readErr := f.Read(buf)
		if n > 0 {
			if err := protocol.WriteFrame(s, buf[:n]); err != nil {
				return errC("write chunk: " + err.Error())
			}
			sent += int64(n)
			globalBridge.pushEvent(map[string]any{
				"type":       "upload_progress",
				"sessionId":  sessionID,
				"filename":   filename,
				"sentBytes":  sent,
				"totalBytes": info.Size(),
			})
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return errC("read local file: " + readErr.Error())
		}
	}

	// Send zero-length EOF marker frame.
	if err := protocol.WriteFrame(s, nil); err != nil {
		return errC("finalize blob stream: " + err.Error())
	}

	var rawResp json.RawMessage
	if err := protocol.ReadJSON(s, &rawResp); err != nil {
		return errC("read blob upload result: " + err.Error())
	}
	var errCheck struct {
		Error string `json:"error"`
	}
	_ = json.Unmarshal(rawResp, &errCheck)
	if errCheck.Error != "" {
		return errC(errCheck.Error)
	}

	return toCJSON(map[string]any{
		"ok":     true,
		"result": rawResp,
	})
}

//export AgyNetworkChanged
func AgyNetworkChanged() *C.char {
	mh, _, err := globalBridge.getHost()
	if err != nil {
		return errC(err.Error())
	}
	globalBridge.mu.Lock()
	for _, rc := range globalBridge.rpcClients {
		rc.mu.Lock()
		if rc.stream != nil {
			_ = rc.stream.Reset()
			rc.stream = nil
		}
		rc.mu.Unlock()
	}
	globalBridge.mu.Unlock()

	globalBridge.pushEvent(map[string]any{
		"type":   "network_changed",
		"peerId": mh.Host.ID().String(),
	})
	return toCJSON(map[string]any{"ok": true})
}

func main() {}
