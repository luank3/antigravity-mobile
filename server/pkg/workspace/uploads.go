package workspace

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
)

const (
	DefaultMaxFileBytes    int64 = 50 << 20  // 50 MiB per file
	DefaultMaxSessionBytes int64 = 250 << 20 // 250 MiB per session
	DefaultUploadTTL             = 24 * time.Hour
)

// UploadManager stages mobile-uploaded files into an isolated /tmp directory per session.
type UploadManager struct {
	baseDir         string
	maxFileBytes    int64
	maxSessionBytes int64

	mu    sync.RWMutex
	files map[string]map[string]protocol.BlobUploadResult // sessionID -> uploadID -> result
}

// NewUploadManager creates an UploadManager under baseDir (defaults to <os.TempDir()>/agyd-uploads).
func NewUploadManager(baseDir string, maxFileBytes, maxSessionBytes int64) (*UploadManager, error) {
	if baseDir == "" {
		baseDir = filepath.Join(os.TempDir(), "agyd-uploads")
	}
	if maxFileBytes <= 0 {
		maxFileBytes = DefaultMaxFileBytes
	}
	if maxSessionBytes <= 0 {
		maxSessionBytes = DefaultMaxSessionBytes
	}
	if err := os.MkdirAll(baseDir, 0o700); err != nil {
		return nil, fmt.Errorf("create upload staging dir %s: %w", baseDir, err)
	}
	return &UploadManager{
		baseDir:         baseDir,
		maxFileBytes:    maxFileBytes,
		maxSessionBytes: maxSessionBytes,
		files:           make(map[string]map[string]protocol.BlobUploadResult),
	}, nil
}

// BaseDir returns the root staging directory.
func (u *UploadManager) BaseDir() string {
	return u.baseDir
}

// SessionDir returns the staged /tmp directory for sessionID (created with 0700 on demand).
func (u *UploadManager) SessionDir(sessionID string) (string, error) {
	safeSession := sanitizeSegment(sessionID)
	if safeSession == "" {
		safeSession = "default"
	}
	dir := filepath.Join(u.baseDir, safeSession)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}

// SaveStream writes a streamed file into <baseDir>/<sessionID>/<id>_<filename>, verifying size and optional SHA-256.
func (u *UploadManager) SaveStream(sessionID, filename, mimeType string, r io.Reader, expectedSHA256 string) (*protocol.BlobUploadResult, error) {
	if sessionID == "" {
		sessionID = "default"
	}
	dir, err := u.SessionDir(sessionID)
	if err != nil {
		return nil, err
	}

	cleanName := sanitizeFilename(filename)
	if cleanName == "" {
		cleanName = "upload.bin"
	}

	var idRaw [6]byte
	if _, err := rand.Read(idRaw[:]); err != nil {
		return nil, err
	}
	uploadID := hex.EncodeToString(idRaw[:])
	targetPath := filepath.Join(dir, uploadID+"_"+cleanName)

	u.mu.RLock()
	var used int64
	for _, f := range u.files[sessionID] {
		used += f.SizeBytes
	}
	u.mu.RUnlock()
	if used >= u.maxSessionBytes {
		return nil, fmt.Errorf("session upload quota (%d bytes) exceeded", u.maxSessionBytes)
	}

	f, err := os.OpenFile(targetPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return nil, err
	}

	hasher := sha256.New()
	limited := io.LimitReader(r, u.maxFileBytes+1)
	var sniff [512]byte
	sniffN := 0
	buf := make([]byte, 32*1024)
	var total int64

	cleanupOnErr := func(writeErr error) (*protocol.BlobUploadResult, error) {
		_ = f.Close()
		_ = os.Remove(targetPath)
		return nil, writeErr
	}

	for {
		n, readErr := limited.Read(buf)
		if n > 0 {
			total += int64(n)
			if total > u.maxFileBytes {
				return cleanupOnErr(fmt.Errorf("file exceeds max size of %d bytes", u.maxFileBytes))
			}
			if used+total > u.maxSessionBytes {
				return cleanupOnErr(fmt.Errorf("session upload quota (%d bytes) exceeded", u.maxSessionBytes))
			}
			if sniffN < len(sniff) {
				cp := copy(sniff[sniffN:], buf[:n])
				sniffN += cp
			}
			if _, err := f.Write(buf[:n]); err != nil {
				return cleanupOnErr(err)
			}
			_, _ = hasher.Write(buf[:n])
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return cleanupOnErr(readErr)
		}
	}

	if err := f.Close(); err != nil {
		_ = os.Remove(targetPath)
		return nil, err
	}

	actualSHA := hex.EncodeToString(hasher.Sum(nil))
	if expectedSHA256 != "" && !strings.EqualFold(strings.TrimSpace(expectedSHA256), actualSHA) {
		_ = os.Remove(targetPath)
		return nil, fmt.Errorf("sha256 mismatch: got %s want %s", actualSHA, expectedSHA256)
	}

	detectedMime := strings.TrimSpace(mimeType)
	if detectedMime == "" || detectedMime == "application/octet-stream" {
		if extMime := mime.TypeByExtension(filepath.Ext(cleanName)); extMime != "" {
			detectedMime = extMime
		} else if sniffN > 0 {
			detectedMime = http.DetectContentType(sniff[:sniffN])
		} else {
			detectedMime = "application/octet-stream"
		}
	}
	if idx := strings.Index(detectedMime, ";"); idx != -1 {
		detectedMime = strings.TrimSpace(detectedMime[:idx])
	}

	res := protocol.BlobUploadResult{
		UploadID:   uploadID,
		RemotePath: targetPath,
		Filename:   cleanName,
		MimeType:   detectedMime,
		SizeBytes:  total,
		SHA256:     actualSHA,
		IsImage:    isSupportedImageMime(detectedMime),
	}

	u.mu.Lock()
	if u.files[sessionID] == nil {
		u.files[sessionID] = make(map[string]protocol.BlobUploadResult)
	}
	u.files[sessionID][uploadID] = res
	u.mu.Unlock()

	return &res, nil
}

// Get returns a staged file record by sessionID and uploadID.
func (u *UploadManager) Get(sessionID, uploadID string) (protocol.BlobUploadResult, bool) {
	u.mu.RLock()
	defer u.mu.RUnlock()
	res, ok := u.files[sessionID][uploadID]
	return res, ok
}

// List returns all staged files for sessionID.
func (u *UploadManager) List(sessionID string) []protocol.BlobUploadResult {
	u.mu.RLock()
	defer u.mu.RUnlock()
	m := u.files[sessionID]
	out := make([]protocol.BlobUploadResult, 0, len(m))
	for _, r := range m {
		out = append(out, r)
	}
	return out
}

// Delete removes a single staged file from disk and tracking.
func (u *UploadManager) Delete(sessionID, uploadID string) error {
	u.mu.Lock()
	defer u.mu.Unlock()
	m := u.files[sessionID]
	if m == nil {
		return errors.New("upload not found")
	}
	res, ok := m[uploadID]
	if !ok {
		return errors.New("upload not found")
	}
	delete(m, uploadID)
	if err := os.Remove(res.RemotePath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

// CleanupSession deletes the entire staged /tmp folder for sessionID.
func (u *UploadManager) CleanupSession(sessionID string) error {
	u.mu.Lock()
	delete(u.files, sessionID)
	u.mu.Unlock()

	safeSession := sanitizeSegment(sessionID)
	if safeSession == "" {
		return nil
	}
	return os.RemoveAll(filepath.Join(u.baseDir, safeSession))
}

// StartReaper periodically deletes staged files older than ttl.
func (u *UploadManager) StartReaper(ctx context.Context, ttl time.Duration) {
	if ttl <= 0 {
		ttl = DefaultUploadTTL
	}
	ticker := time.NewTicker(30 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			u.ReapExpired(ttl)
		}
	}
}

// ReapExpired removes files and empty session dirs older than ttl.
func (u *UploadManager) ReapExpired(ttl time.Duration) {
	cutoff := time.Now().Add(-ttl)
	entries, err := os.ReadDir(u.baseDir)
	if err != nil {
		return
	}
	for _, sessEntry := range entries {
		if !sessEntry.IsDir() {
			continue
		}
		sessDir := filepath.Join(u.baseDir, sessEntry.Name())
		files, err := os.ReadDir(sessDir)
		if err != nil {
			continue
		}
		remaining := 0
		for _, fe := range files {
			info, err := fe.Info()
			if err != nil {
				continue
			}
			if info.ModTime().Before(cutoff) {
				_ = os.Remove(filepath.Join(sessDir, fe.Name()))
			} else {
				remaining++
			}
		}
		if remaining == 0 {
			_ = os.Remove(sessDir)
		}
	}
}

func sanitizeSegment(s string) string {
	s = filepath.Base(strings.TrimSpace(s))
	if s == "." || s == ".." || s == string(os.PathSeparator) {
		return ""
	}
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func sanitizeFilename(name string) string {
	base := filepath.Base(strings.TrimSpace(name))
	if base == "." || base == ".." || base == string(os.PathSeparator) {
		return ""
	}
	var b strings.Builder
	for _, r := range base {
		switch {
		case r >= 'a' && r <= 'z',
			r >= 'A' && r <= 'Z',
			r >= '0' && r <= '9',
			r == '.', r == '-', r == '_':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	return strings.Trim(b.String(), ".")
}

func isSupportedImageMime(m string) bool {
	switch strings.ToLower(m) {
	case "image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif":
		return true
	default:
		return false
	}
}
