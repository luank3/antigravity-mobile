package acp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type transcriptToolCall struct {
	Name string         `json:"name"`
	Args map[string]any `json:"args"`
}

type transcriptEntry struct {
	Type      string               `json:"type"`
	Content   string               `json:"content"`
	Thinking  string               `json:"thinking"`
	ToolCalls []transcriptToolCall `json:"tool_calls"`
}

func findTranscriptPath(sessionID string) string {
	if sessionID == "" || strings.ContainsAny(sessionID, "/\\") || sessionID == "." || sessionID == ".." {
		return ""
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	logsDir := filepath.Join(home, ".gemini", "antigravity-cli", "brain", sessionID, ".system_generated", "logs")
	for _, name := range []string{"transcript_full.jsonl", "transcript.jsonl"} {
		p := filepath.Join(logsDir, name)
		if info, err := os.Stat(p); err == nil && !info.IsDir() && info.Size() > 0 {
			return p
		}
	}
	return ""
}

func loadTranscriptHistory(sessionID string) ([]json.RawMessage, bool) {
	path := findTranscriptPath(sessionID)
	if path == "" {
		return nil, false
	}
	return parseTranscriptHistoryFile(path)
}

func parseTranscriptHistoryFile(path string) ([]json.RawMessage, bool) {
	f, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 64*1024), maxScannerTokenSize)

	raw := make([]json.RawMessage, 0, 128)
	tcMaps := make(map[int]map[string]any)
	lastToolIdx := -1
	tcSeq := 0

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var entry transcriptEntry
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue
		}

		switch entry.Type {
		case "USER_INPUT":
			lastToolIdx = -1
			txt := stripUserRequestTags(entry.Content)
			if txt != "" {
				raw = append(raw, marshalTextUpdate("user_message_chunk", txt))
			}

		case "PLANNER_RESPONSE":
			lastToolIdx = -1
			if entry.Thinking != "" {
				raw = append(raw, marshalTextUpdate("agent_thought_chunk", entry.Thinking))
			}
			for _, tc := range entry.ToolCalls {
				if tc.Name == "" {
					continue
				}
				tcSeq++
				m := map[string]any{
					"sessionUpdate": "tool_call",
					"toolCallId":    fmt.Sprintf("hist-tc-%d", tcSeq),
					"name":          tc.Name,
					"title":         tc.Name,
					"kind":          mapToolKind(tc.Name),
					"status":        "completed",
					"rawInput":      unwrapToolArgs(tc.Args),
				}
				b, err := json.Marshal(m)
				if err == nil {
					idx := len(raw)
					raw = append(raw, json.RawMessage(b))
					tcMaps[idx] = m
					lastToolIdx = idx
				}
			}
			if entry.Content != "" {
				lastToolIdx = -1
				raw = append(raw, marshalTextUpdate("agent_message_chunk", entry.Content))
			}

		case "GENERIC":
			if lastToolIdx >= 0 && entry.Content != "" {
				if m, ok := tcMaps[lastToolIdx]; ok {
					m["rawOutput"] = map[string]any{"output": entry.Content}
					if b, err := json.Marshal(m); err == nil {
						raw[lastToolIdx] = json.RawMessage(b)
					}
				}
				lastToolIdx = -1
			}

		case "ERROR_MESSAGE":
			lastToolIdx = -1
			if entry.Content != "" {
				raw = append(raw, marshalTextUpdate("agent_message_chunk", entry.Content))
			}

		default:
			lastToolIdx = -1
		}
	}
	if err := scanner.Err(); err != nil && len(raw) == 0 {
		return nil, false
	}
	if len(raw) == 0 {
		return nil, false
	}
	return coalesceHistoryUpdates(raw), true
}

func marshalTextUpdate(kind, text string) json.RawMessage {
	b, _ := json.Marshal(map[string]any{
		"sessionUpdate": kind,
		"content": map[string]any{
			"type": "text",
			"text": text,
		},
	})
	return json.RawMessage(b)
}

func stripUserRequestTags(s string) string {
	trimmed := strings.TrimSpace(s)
	if strings.HasPrefix(trimmed, "<USER_REQUEST>") && strings.HasSuffix(trimmed, "</USER_REQUEST>") {
		inner := strings.TrimPrefix(trimmed, "<USER_REQUEST>")
		inner = strings.TrimSuffix(inner, "</USER_REQUEST>")
		return strings.TrimSpace(inner)
	}
	return s
}

func mapToolKind(name string) string {
	switch name {
	case "run_command":
		return "execute"
	case "edit_file", "write_file":
		return "edit"
	case "read_file":
		return "read"
	default:
		return name
	}
}

func unwrapToolArgs(args map[string]any) map[string]any {
	if len(args) == 0 {
		return map[string]any{}
	}
	out := make(map[string]any, len(args))
	for k, v := range args {
		if s, ok := v.(string); ok {
			var decoded any
			if err := json.Unmarshal([]byte(s), &decoded); err == nil {
				out[k] = decoded
				continue
			}
		}
		out[k] = v
	}
	return out
}
