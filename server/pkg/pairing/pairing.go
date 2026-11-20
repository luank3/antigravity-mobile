package pairing

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/libp2p/go-libp2p/core/peer"
	qrcode "github.com/skip2/go-qrcode"
)

var sasEmojis = []string{
	"🛰️", "🔐", "⚡", "🧭",
	"🚀", "🛡️", "🌊", "🔥",
	"🔮", "📡", "💎", "🌙",
	"⚙️", "🗝️", "🧊", "🌟",
}

// ComputeSAS derives a deterministic 6-digit + 3-emoji Short Authentication String.
func ComputeSAS(hostPeerID, clientPeerID, token string) (string, string) {
	h := sha256.New()
	h.Write([]byte(hostPeerID))
	h.Write([]byte("|"))
	h.Write([]byte(clientPeerID))
	h.Write([]byte("|"))
	h.Write([]byte(token))
	sum := h.Sum(nil)

	num := binary.BigEndian.Uint32(sum[:4]) % 1000000
	digits := fmt.Sprintf("%03d-%03d", num/1000, num%1000)

	e1 := sasEmojis[int(sum[4])%len(sasEmojis)]
	e2 := sasEmojis[int(sum[5])%len(sasEmojis)]
	e3 := sasEmojis[int(sum[6])%len(sasEmojis)]
	return digits, e1 + " " + e2 + " " + e3
}

// ActiveToken represents an ephemeral pairing invitation.
type ActiveToken struct {
	Token      string
	Pin        string
	TrustNext  bool
	ExpiresAt  time.Time
	consumed   bool
}

// PendingSession holds an in-flight /agy/pair/1.0.0 handshake waiting for SAS confirmation.
type PendingSession struct {
	SessionID    string
	ClientPeerID peer.ID
	DeviceName   string
	Token        string
	SASDigits    string
	SASEmojis    string
	TrustAuto    bool
	CreatedAt    time.Time
	DecisionCh   chan bool
}

// Manager issues single-use pairing tokens and tracks active SAS verification sessions.
type Manager struct {
	mu       sync.Mutex
	tokens   map[string]*ActiveToken
	sessions map[string]*PendingSession
	allow    *Allowlist
	onSAS    func(PendingSession)
}

// NewManager creates a pairing Manager backed by allow.
func NewManager(allow *Allowlist) *Manager {
	return &Manager{
		tokens:   make(map[string]*ActiveToken),
		sessions: make(map[string]*PendingSession),
		allow:    allow,
	}
}

// SetSASObserver sets an optional callback invoked when a remote client starts SAS confirmation.
func (m *Manager) SetSASObserver(fn func(PendingSession)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onSAS = fn
}

// CreateToken issues a single-use 256-bit token and 6-digit PIN valid for ttl.
func (m *Manager) CreateToken(ttl time.Duration, trustNext bool) (*ActiveToken, error) {
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return nil, err
	}
	var pinRaw [4]byte
	if _, err := rand.Read(pinRaw[:]); err != nil {
		return nil, err
	}
	pinNum := binary.BigEndian.Uint32(pinRaw[:]) % 1000000

	tok := &ActiveToken{
		Token:     hex.EncodeToString(raw[:]),
		Pin:       fmt.Sprintf("%06d", pinNum),
		TrustNext: trustNext,
		ExpiresAt: time.Now().UTC().Add(ttl),
	}

	m.mu.Lock()
	m.pruneLocked(time.Now().UTC())
	m.tokens[tok.Token] = tok
	m.mu.Unlock()
	return tok, nil
}

func (m *Manager) pruneLocked(now time.Time) {
	for k, t := range m.tokens {
		if t.consumed || now.After(t.ExpiresAt) {
			delete(m.tokens, k)
		}
	}
	for k, s := range m.sessions {
		if now.Sub(s.CreatedAt) > 10*time.Minute {
			delete(m.sessions, k)
		}
	}
}

// StartHandshake validates a token or PIN and creates a PendingSession with SAS.
func (m *Manager) StartHandshake(hostPeerID peer.ID, clientPeerID peer.ID, req protocol.PairRequest) (*PendingSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now().UTC()
	m.pruneLocked(now)

	var matched *ActiveToken
	if req.Token != "" {
		if t, ok := m.tokens[req.Token]; ok && !t.consumed && now.Before(t.ExpiresAt) {
			matched = t
		}
	} else if req.Pin != "" {
		for _, t := range m.tokens {
			if !t.consumed && now.Before(t.ExpiresAt) && t.Pin == req.Pin {
				matched = t
				break
			}
		}
	}
	if matched == nil {
		return nil, errors.New("invalid or expired pairing token")
	}
	matched.consumed = true

	var sidRaw [16]byte
	if _, err := rand.Read(sidRaw[:]); err != nil {
		return nil, err
	}
	sid := hex.EncodeToString(sidRaw[:])
	digits, emojis := ComputeSAS(hostPeerID.String(), clientPeerID.String(), matched.Token)

	sess := &PendingSession{
		SessionID:    sid,
		ClientPeerID: clientPeerID,
		DeviceName:   req.DeviceName,
		Token:        matched.Token,
		SASDigits:    digits,
		SASEmojis:    emojis,
		TrustAuto:    matched.TrustNext,
		CreatedAt:    now,
		DecisionCh:   make(chan bool, 1),
	}
	if sess.TrustAuto {
		sess.DecisionCh <- true
	}
	m.sessions[sid] = sess
	observer := m.onSAS
	if observer != nil {
		go observer(*sess)
	}
	return sess, nil
}

// ApproveHostDecision records an interactive host-side approval decision for a pending session.
func (m *Manager) ApproveHostDecision(sessionID string, accept bool) error {
	m.mu.Lock()
	sess, ok := m.sessions[sessionID]
	m.mu.Unlock()
	if !ok {
		return errors.New("pairing session not found")
	}
	select {
	case sess.DecisionCh <- accept:
	default:
	}
	return nil
}

// CompleteHandshake waits for host-side SAS confirmation (if interactive) and finalizes allowlist insertion.
func (m *Manager) CompleteHandshake(sessionID string, clientAccept bool, waitTimeout time.Duration) (bool, error) {
	m.mu.Lock()
	sess, ok := m.sessions[sessionID]
	m.mu.Unlock()
	if !ok {
		return false, errors.New("pairing session not found")
	}
	defer func() {
		m.mu.Lock()
		delete(m.sessions, sessionID)
		m.mu.Unlock()
	}()

	if !clientAccept {
		return false, nil
	}

	if !sess.TrustAuto {
		timer := time.NewTimer(waitTimeout)
		defer timer.Stop()
		select {
		case hostAccept := <-sess.DecisionCh:
			if !hostAccept {
				return false, nil
			}
		case <-timer.C:
			return false, errors.New("host SAS confirmation timed out")
		}
	}

	if err := m.allow.Add(sess.ClientPeerID, sess.DeviceName); err != nil {
		return false, err
	}
	return true, nil
}

// ParsedPairURI contains decoded fields from an agy://pair?... invitation.
type ParsedPairURI struct {
	HostPeerID string   `json:"hostPeerId"`
	HostName   string   `json:"hostName"`
	Token      string   `json:"token"`
	RelayAddrs []string `json:"relayAddrs"`
	DirectAddrs []string `json:"directAddrs"`
}

// BuildPairURI encodes an agy://pair URI for QR or clipboard sharing.
func BuildPairURI(hostPeerID, hostName, token string, relayAddrs, directAddrs []string) string {
	q := url.Values{}
	q.Set("peer", hostPeerID)
	if hostName != "" {
		q.Set("name", hostName)
	}
	q.Set("token", token)
	for _, r := range relayAddrs {
		if r != "" {
			q.Add("relay", r)
		}
	}
	for _, a := range directAddrs {
		if a != "" {
			q.Add("addr", a)
		}
	}
	return "agy://pair?" + q.Encode()
}

// ParsePairURI decodes an agy://pair?... string.
func ParsePairURI(raw string) (*ParsedPairURI, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return nil, fmt.Errorf("parse pairing URI: %w", err)
	}
	if u.Scheme != "agy" || u.Host != "pair" {
		return nil, errors.New("invalid pairing URI scheme (expected agy://pair)")
	}
	q := u.Query()
	peerID := strings.TrimSpace(q.Get("peer"))
	token := strings.TrimSpace(q.Get("token"))
	if peerID == "" || token == "" {
		return nil, errors.New("pairing URI missing peer or token")
	}
	if _, err := peer.Decode(peerID); err != nil {
		return nil, fmt.Errorf("invalid peer ID in URI: %w", err)
	}
	return &ParsedPairURI{
		HostPeerID:  peerID,
		HostName:    q.Get("name"),
		Token:       token,
		RelayAddrs:  q["relay"],
		DirectAddrs: q["addr"],
	}, nil
}

// RenderTerminalQR builds an ASCII QR code suitable for terminal display.
func RenderTerminalQR(uri string) (string, error) {
	qr, err := qrcode.New(uri, qrcode.Medium)
	if err != nil {
		return "", err
	}
	return qr.ToSmallString(false), nil
}
