package workspace

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWorkspaceTraversalAndRead(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "hello.txt"), []byte("hello antigravity"), 0o644); err != nil {
		t.Fatal(err)
	}

	mgr, err := NewManager([]string{root}, "")
	if err != nil {
		t.Fatal(err)
	}

	entries, err := mgr.ListTree(root, ".")
	if err != nil {
		t.Fatalf("list tree: %v", err)
	}
	if len(entries) != 1 || entries[0].Name != "hello.txt" {
		t.Fatalf("unexpected entries: %+v", entries)
	}

	txt, truncated, err := mgr.ReadFile(root, "hello.txt", 1024)
	if err != nil || truncated || txt != "hello antigravity" {
		t.Fatalf("read file unexpected: %q trunc=%v err=%v", txt, truncated, err)
	}

	if _, _, err := mgr.ReadFile(root, "../../etc/passwd", 1024); err == nil {
		t.Fatal("expected path traversal to be rejected")
	}
}

func TestUploadManagerStagingAndCleanup(t *testing.T) {
	tmpRoot := filepath.Join(t.TempDir(), "uploads")
	um, err := NewUploadManager(tmpRoot, 1024, 2048)
	if err != nil {
		t.Fatal(err)
	}

	data := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 1, 2, 3, 4}
	sum := sha256.Sum256(data)
	hexSum := hex.EncodeToString(sum[:])

	res, err := um.SaveStream("sess-1", "../../evil name.png", "image/png", bytes.NewReader(data), hexSum)
	if err != nil {
		t.Fatalf("save stream: %v", err)
	}
	if !res.IsImage || res.Filename != "evil_name.png" || !strings.HasPrefix(res.RemotePath, tmpRoot) {
		t.Fatalf("unexpected upload result: %+v", res)
	}
	if _, err := os.Stat(res.RemotePath); err != nil {
		t.Fatalf("expected staged file on disk: %v", err)
	}

	// Bad SHA256 must fail and clean up file.
	if _, err := um.SaveStream("sess-1", "bad.txt", "text/plain", strings.NewReader("abc"), "0000"); err == nil {
		t.Fatal("expected sha256 mismatch error")
	}

	// Oversized file must fail.
	if _, err := um.SaveStream("sess-1", "big.bin", "", bytes.NewReader(make([]byte, 1500)), ""); err == nil {
		t.Fatal("expected maxFileBytes limit error")
	}

	if err := um.Delete("sess-1", res.UploadID); err != nil {
		t.Fatalf("delete upload: %v", err)
	}
	if _, err := os.Stat(res.RemotePath); !os.IsNotExist(err) {
		t.Fatal("expected deleted file removed from /tmp")
	}

	res2, err := um.SaveStream("sess-1", "notes.log", "text/plain", strings.NewReader("log line"), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := um.CleanupSession("sess-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(res2.RemotePath); !os.IsNotExist(err) {
		t.Fatal("expected CleanupSession to wipe session staging dir")
	}
}
