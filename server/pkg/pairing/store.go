package pairing

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
)

// LoadOrCreateIdentity loads a persistent Ed25519 private key from path or generates one.
func LoadOrCreateIdentity(path string) (crypto.PrivKey, error) {
	if path != "" {
		data, err := os.ReadFile(path)
		if err == nil {
			priv, unmarshalErr := crypto.UnmarshalPrivateKey(data)
			if unmarshalErr != nil {
				return nil, fmt.Errorf("unmarshal identity key %s: %w", path, unmarshalErr)
			}
			return priv, nil
		}
		if !errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("read identity key %s: %w", path, err)
		}
	}

	priv, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate ed25519 identity: %w", err)
	}

	if path != "" {
		raw, err := crypto.MarshalPrivateKey(priv)
		if err != nil {
			return nil, fmt.Errorf("marshal identity key: %w", err)
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			return nil, fmt.Errorf("mkdir identity dir: %w", err)
		}
		if err := os.WriteFile(path, raw, 0o600); err != nil {
			return nil, fmt.Errorf("write identity key %s: %w", path, err)
		}
	}
	return priv, nil
}

// Allowlist persists authorized client PeerIDs on disk with zero-trust lookup.
type Allowlist struct {
	mu    sync.RWMutex
	path  string
	peers map[peer.ID]protocol.AuthorizedPeer
}

// NewAllowlist loads or initializes an authorized peers JSON store at path (empty path = in-memory).
func NewAllowlist(path string) (*Allowlist, error) {
	a := &Allowlist{
		path:  path,
		peers: make(map[peer.ID]protocol.AuthorizedPeer),
	}
	if path != "" {
		if err := a.load(); err != nil {
			return nil, err
		}
	}
	return a, nil
}

func (a *Allowlist) load() error {
	data, err := os.ReadFile(a.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read allowlist %s: %w", a.path, err)
	}
	if len(data) == 0 {
		return nil
	}
	var list []protocol.AuthorizedPeer
	if err := json.Unmarshal(data, &list); err != nil {
		return fmt.Errorf("decode allowlist %s: %w", a.path, err)
	}
	for _, entry := range list {
		pid, err := peer.Decode(entry.PeerID)
		if err != nil {
			continue
		}
		a.peers[pid] = entry
	}
	return nil
}

func (a *Allowlist) saveLocked() error {
	if a.path == "" {
		return nil
	}
	list := make([]protocol.AuthorizedPeer, 0, len(a.peers))
	for _, entry := range a.peers {
		list = append(list, entry)
	}
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(a.path), 0o700); err != nil {
		return err
	}
	tmp := a.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, a.path)
}

// IsAllowed returns true if pid is currently paired and authorized.
func (a *Allowlist) IsAllowed(pid peer.ID) bool {
	a.mu.RLock()
	defer a.mu.RUnlock()
	_, ok := a.peers[pid]
	return ok
}

// Add authorizes pid and persists it to disk.
func (a *Allowlist) Add(pid peer.ID, deviceName string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	now := time.Now().UTC()
	if existing, ok := a.peers[pid]; ok {
		if deviceName != "" {
			existing.DeviceName = deviceName
		}
		existing.LastSeenAt = now
		a.peers[pid] = existing
	} else {
		if deviceName == "" {
			deviceName = "Android Device"
		}
		a.peers[pid] = protocol.AuthorizedPeer{
			PeerID:     pid.String(),
			DeviceName: deviceName,
			PairedAt:   now,
			LastSeenAt: now,
		}
	}
	return a.saveLocked()
}

// Touch updates the last-seen timestamp for an authorized peer.
func (a *Allowlist) Touch(pid peer.ID) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if entry, ok := a.peers[pid]; ok {
		entry.LastSeenAt = time.Now().UTC()
		a.peers[pid] = entry
		_ = a.saveLocked()
	}
}

// Revoke removes pid from the allowlist. Returns true if the peer existed.
func (a *Allowlist) Revoke(pid peer.ID) (bool, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, ok := a.peers[pid]; !ok {
		return false, nil
	}
	delete(a.peers, pid)
	return true, a.saveLocked()
}

// List returns a snapshot of all authorized peers.
func (a *Allowlist) List() []protocol.AuthorizedPeer {
	a.mu.RLock()
	defer a.mu.RUnlock()
	out := make([]protocol.AuthorizedPeer, 0, len(a.peers))
	for _, entry := range a.peers {
		out = append(out, entry)
	}
	return out
}
