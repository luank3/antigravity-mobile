package acp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestParseTranscriptHistoryFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "transcript_full.jsonl")
	content := "" +
		`{"type":"USER_INPUT","content":"<USER_REQUEST>\nHello agent\n</USER_REQUEST>"}` + "\n" +
		`{"type":"SYSTEM_MESSAGE","content":"ignore internal system prompt"}` + "\n" +
		`{"type":"PLANNER_RESPONSE","thinking":"Let me check. ","tool_calls":[{"name":"run_command","args":{"CommandLine":"\"ls -la\""}}]}` + "\n" +
		`{"type":"GENERIC","content":"file1\nfile2"}` + "\n" +
		`{"type":"PLANNER_RESPONSE","content":"Done!"}` + "\n"
	if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
		t.Fatalf("write temp transcript: %v", err)
	}

	items, ok := parseTranscriptHistoryFile(p)
	if !ok {
		t.Fatal("expected ok=true")
	}
	if len(items) != 4 {
		t.Fatalf("expected 4 coalesced items (user, thought, tool_call, assistant), got %d", len(items))
	}

	var usr, tc, asst map[string]any
	_ = json.Unmarshal(items[0], &usr)
	_ = json.Unmarshal(items[2], &tc)
	_ = json.Unmarshal(items[3], &asst)

	if usr["sessionUpdate"] != "user_message_chunk" {
		t.Fatalf("unexpected item 0: %v", usr)
	}
	if usr["content"].(map[string]any)["text"] != "Hello agent" {
		t.Fatalf("expected stripped user text, got %v", usr["content"])
	}
	rawOut, ok := tc["rawOutput"].(map[string]any)
	if tc["sessionUpdate"] != "tool_call" || tc["title"] != "run_command" || tc["kind"] != "execute" || !ok || rawOut["output"] != "file1\nfile2" {
		t.Fatalf("unexpected tool_call item: %v", tc)
	}
	rawIn := tc["rawInput"].(map[string]any)
	if rawIn["CommandLine"] != "ls -la" {
		t.Fatalf("expected unwrapped CommandLine, got %v", rawIn["CommandLine"])
	}
	if asst["sessionUpdate"] != "agent_message_chunk" || asst["content"].(map[string]any)["text"] != "Done!" {
		t.Fatalf("unexpected assistant item: %v", asst)
	}
}
