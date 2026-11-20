package workspace

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/antigravity/antigravity-mobile/server/pkg/protocol"
)

// Manager provides path-jailed workspace browsing, git status/diffs, and brain artifacts.
type Manager struct {
	mu       sync.RWMutex
	roots    []string
	brainDir string
}

// NewManager creates a workspace Manager restricted to roots (defaulting to current working dir).
func NewManager(roots []string, brainDir string) (*Manager, error) {
	resolved := make([]string, 0, len(roots))
	for _, r := range roots {
		r = strings.TrimSpace(r)
		if r == "" {
			continue
		}
		abs, err := resolveRealPath(r)
		if err != nil {
			continue
		}
		resolved = append(resolved, abs)
	}
	if len(resolved) == 0 {
		wd, err := os.Getwd()
		if err != nil {
			return nil, err
		}
		if real, err := resolveRealPath(wd); err == nil {
			resolved = append(resolved, real)
		} else {
			resolved = append(resolved, wd)
		}
	}

	if brainDir == "" {
		if home, err := os.UserHomeDir(); err == nil {
			brainDir = filepath.Join(home, ".gemini", "antigravity-cli", "brain")
		}
	}

	return &Manager{
		roots:    resolved,
		brainDir: brainDir,
	}, nil
}

// AddRoot dynamically registers an active session cwd so its files/diffs can be inspected.
func (m *Manager) AddRoot(dir string) {
	real, err := resolveRealPath(dir)
	if err != nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.roots {
		if r == real {
			return
		}
	}
	m.roots = append(m.roots, real)
}

// Roots returns a copy of configured workspace roots.
func (m *Manager) Roots() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]string, len(m.roots))
	copy(out, m.roots)
	return out
}

func resolveRealPath(p string) (string, error) {
	abs, err := filepath.Abs(p)
	if err != nil {
		return "", err
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		return real, nil
	}
	return filepath.Clean(abs), nil
}

func isWithin(base, target string) bool {
	rel, err := filepath.Rel(base, target)
	if err != nil {
		return false
	}
	return rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator)))
}

// ResolvePath verifies target stays strictly inside root (or any configured root when root=="").
func (m *Manager) ResolvePath(root, relPath string) (string, error) {
	m.mu.RLock()
	roots := append([]string(nil), m.roots...)
	m.mu.RUnlock()

	var base string
	if root != "" {
		realRoot, err := resolveRealPath(root)
		if err != nil {
			return "", err
		}
		allowed := false
		for _, r := range roots {
			if isWithin(r, realRoot) {
				allowed = true
				break
			}
		}
		if !allowed {
			return "", errors.New("workspace root is outside allowed roots")
		}
		base = realRoot
	} else {
		base = roots[0]
	}

	if relPath == "" || relPath == "." {
		return base, nil
	}

	var candidate string
	if filepath.IsAbs(relPath) {
		candidate = relPath
	} else {
		candidate = filepath.Join(base, relPath)
	}
	realTarget, err := resolveRealPath(candidate)
	if err != nil {
		return "", err
	}
	if !isWithin(base, realTarget) {
		return "", fmt.Errorf("path %q escapes workspace root", relPath)
	}
	return realTarget, nil
}

// ListTree lists entries under root/relPath.
func (m *Manager) ListTree(root, relPath string) ([]protocol.WorkspaceEntry, error) {
	dir, err := m.ResolvePath(root, relPath)
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	base, err := m.ResolvePath(root, ".")
	if err != nil {
		base = dir
	}

	out := make([]protocol.WorkspaceEntry, 0, len(entries))
	for _, entry := range entries {
		name := entry.Name()
		if name == ".git" || name == "node_modules" {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		full := filepath.Join(dir, name)
		rel, err := filepath.Rel(base, full)
		if err != nil {
			rel = name
		}
		out = append(out, protocol.WorkspaceEntry{
			Name:  name,
			Path:  filepath.ToSlash(rel),
			IsDir: entry.IsDir(),
			Size:  info.Size(),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].IsDir != out[j].IsDir {
			return out[i].IsDir
		}
		return out[i].Name < out[j].Name
	})
	return out, nil
}

// ReadFile reads up to maxBytes from a workspace file.
func (m *Manager) ReadFile(root, relPath string, maxBytes int64) (string, bool, error) {
	if maxBytes <= 0 {
		maxBytes = 256 << 10
	}
	target, err := m.ResolvePath(root, relPath)
	if err != nil {
		return "", false, err
	}
	info, err := os.Stat(target)
	if err != nil {
		return "", false, err
	}
	if info.IsDir() {
		return "", false, errors.New("cannot read directory as file")
	}
	f, err := os.Open(target)
	if err != nil {
		return "", false, err
	}
	defer f.Close()

	buf := make([]byte, maxBytes+1)
	n, err := f.Read(buf)
	if err != nil && n == 0 {
		return "", false, err
	}
	truncated := int64(n) > maxBytes
	if truncated {
		n = int(maxBytes)
	}
	return string(buf[:n]), truncated, nil
}

// GitStatus returns modified/untracked files and line stats in cwd.
func (m *Manager) GitStatus(ctx context.Context, cwd string) ([]protocol.GitChange, error) {
	dir, err := m.ResolvePath(cwd, ".")
	if err != nil {
		return nil, err
	}

	statusOut, err := exec.CommandContext(ctx, "git", "-C", dir, "status", "--porcelain").Output()
	if err != nil {
		return []protocol.GitChange{}, nil
	}

	numstatOut, _ := exec.CommandContext(ctx, "git", "-C", dir, "diff", "--numstat", "HEAD").Output()
	stats := make(map[string][2]int)
	for _, line := range strings.Split(strings.TrimSpace(string(numstatOut)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) < 3 {
			continue
		}
		add, _ := strconv.Atoi(parts[0])
		del, _ := strconv.Atoi(parts[1])
		stats[parts[2]] = [2]int{add, del}
	}

	var changes []protocol.GitChange
	for _, line := range strings.Split(strings.TrimRight(string(statusOut), "\n"), "\n") {
		if len(line) < 4 {
			continue
		}
		code := strings.TrimSpace(line[:2])
		path := strings.TrimSpace(line[3:])
		if idx := strings.LastIndex(path, " -> "); idx != -1 {
			path = path[idx+4:]
		}
		st := stats[path]
		changes = append(changes, protocol.GitChange{
			Path:      path,
			Status:    code,
			Additions: st[0],
			Deletions: st[1],
		})
	}
	return changes, nil
}

// GitDiff returns the unified diff for relPath (or the whole repo when relPath is empty).
func (m *Manager) GitDiff(ctx context.Context, cwd, relPath string) (string, error) {
	dir, err := m.ResolvePath(cwd, ".")
	if err != nil {
		return "", err
	}
	args := []string{"-C", dir, "diff", "HEAD"}
	if relPath != "" {
		if _, err := m.ResolvePath(dir, relPath); err != nil {
			return "", err
		}
		args = append(args, "--", relPath)
	}
	out, err := exec.CommandContext(ctx, "git", args...).CombinedOutput()
	if err != nil && len(out) == 0 {
		// Try diff without HEAD (e.g. unborn initial commit).
		args2 := []string{"-C", dir, "diff"}
		if relPath != "" {
			args2 = append(args2, "--", relPath)
		}
		out2, err2 := exec.CommandContext(ctx, "git", args2...).CombinedOutput()
		if err2 != nil && len(out2) == 0 {
			return "", nil
		}
		return string(out2), nil
	}
	return string(out), nil
}

// ListArtifacts lists brain artifacts for sessionID.
func (m *Manager) ListArtifacts(sessionID string) ([]protocol.ArtifactSummary, error) {
	if m.brainDir == "" || sessionID == "" {
		return []protocol.ArtifactSummary{}, nil
	}
	safeID := filepath.Base(sessionID)
	dir := filepath.Join(m.brainDir, safeID)
	entries, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return []protocol.ArtifactSummary{}, nil
	}
	if err != nil {
		return nil, err
	}
	var out []protocol.ArtifactSummary
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || strings.HasPrefix(name, ".") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		out = append(out, protocol.ArtifactSummary{
			Name:      name,
			SessionID: safeID,
			Size:      info.Size(),
			UpdatedAt: info.ModTime().UTC().Format("2006-01-02T15:04:05Z"),
		})
	}
	return out, nil
}

// ReadArtifact reads a specific brain artifact file safely.
func (m *Manager) ReadArtifact(sessionID, name string) (string, error) {
	if m.brainDir == "" || sessionID == "" || name == "" {
		return "", errors.New("invalid artifact coordinates")
	}
	dir := filepath.Join(m.brainDir, filepath.Base(sessionID))
	target := filepath.Join(dir, filepath.Base(name))
	realDir, err := resolveRealPath(dir)
	if err != nil {
		return "", err
	}
	realTarget, err := resolveRealPath(target)
	if err != nil {
		return "", err
	}
	if !isWithin(realDir, realTarget) {
		return "", errors.New("artifact path escape blocked")
	}
	data, err := os.ReadFile(realTarget)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
