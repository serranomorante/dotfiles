package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
)

const (
	version          = 1
	sessionReadBytes = 512 * 1024
	titleMaxRunes    = 200
)

var providers = map[string]providerDefaults{
	"codex": {
		root:    "~/.codex/sessions",
		history: "~/.codex/history.jsonl",
		envSessionKeys: []string{
			"CODEX_SESSION_ID",
			"CODEX_CONVERSATION_ID",
			"CODEX_CURRENT_SESSION_ID",
		},
	},
	"claude": {
		root:    "~/.claude/projects",
		history: "~/.claude/history.jsonl",
		envSessionKeys: []string{
			"CLAUDE_SESSION_ID",
			"CLAUDE_CODE_SESSION_ID",
			"CLAUDE_CURRENT_SESSION_ID",
		},
	},
	"gemini": {
		root:    "~/.gemini/tmp",
		history: "~/.gemini/history.jsonl",
		envSessionKeys: []string{
			"GEMINI_SESSION_ID",
			"GEMINI_CURRENT_SESSION_ID",
		},
	},
}

type providerDefaults struct {
	root           string
	history        string
	envSessionKeys []string
}

type session struct {
	Provider   string `json:"provider"`
	Path       string `json:"path"`
	ID         string `json:"id,omitempty"`
	CWD        string `json:"cwd,omitempty"`
	Timestamp  string `json:"timestamp,omitempty"`
	Originator string `json:"originator,omitempty"`
	Title      string `json:"title,omitempty"`
	UpdatedAt  string `json:"updated_at,omitempty"`
}

type refreshPayload struct {
	Version     int       `json:"version"`
	Provider    string    `json:"provider"`
	GeneratedAt int64     `json:"generated_at"`
	Sessions    []session `json:"sessions"`
}

type idsPayload struct {
	Version  int      `json:"version"`
	Provider string   `json:"provider"`
	IDs      []string `json:"ids"`
}

type sessionPayload struct {
	Version  int      `json:"version"`
	Provider string   `json:"provider"`
	Session  *session `json:"session"`
}

type watchPayload struct {
	Version  int      `json:"version"`
	Provider string   `json:"provider"`
	Event    string   `json:"event"`
	Session  *session `json:"session,omitempty"`
}

type exitError struct {
	code int
	msg  string
}

func (e exitError) Error() string {
	return e.msg
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		var ee exitError
		if errors.As(err, &ee) {
			if ee.msg != "" {
				fmt.Fprintf(os.Stderr, "agent-session-store: %s\n", ee.msg)
			}
			os.Exit(ee.code)
		}
		fmt.Fprintf(os.Stderr, "agent-session-store: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	opts, commandArgs, err := parseGlobalArgs(args)
	if err != nil {
		return err
	}
	if opts.help {
		printUsage(os.Stdout)
		return nil
	}
	if opts.command == "" {
		printUsage(os.Stderr)
		return exitError{code: 2}
	}

	defaults, ok := providers[opts.provider]
	if !ok {
		return exitError{code: 2, msg: "unsupported provider: " + opts.provider}
	}
	root := opts.root
	if root == "" {
		root = defaults.root
	}
	root = expandUser(root)

	switch opts.command {
	case "refresh":
		if wantsCommandHelp(commandArgs) {
			printRefreshUsage(os.Stdout)
			return nil
		}
		if len(commandArgs) != 0 {
			return usageError("refresh takes no arguments")
		}
		return emitRefresh(opts.provider, root)
	case "ids":
		if wantsCommandHelp(commandArgs) {
			printIDsUsage(os.Stdout)
			return nil
		}
		if len(commandArgs) != 1 {
			return usageError("ids requires cwd")
		}
		return emitIDs(opts.provider, root, commandArgs[0])
	case "wait-new":
		if wantsCommandHelp(commandArgs) {
			printWaitNewUsage(os.Stdout)
			return nil
		}
		if len(commandArgs) != 4 {
			return usageError("wait-new requires cwd known_ids_json timeout_seconds interval_seconds")
		}
		return emitWaitNew(opts.provider, root, commandArgs)
	case "watch-new":
		if wantsCommandHelp(commandArgs) {
			printWatchNewUsage(os.Stdout)
			return nil
		}
		if len(commandArgs) != 5 {
			return usageError("watch-new requires cwd known_ids_json timeout_seconds interval_seconds title_timeout_seconds")
		}
		return emitWatchNew(opts.provider, root, commandArgs)
	case "current-id":
		currentOpts, err := parseCurrentIDArgs(commandArgs, defaults)
		if err != nil {
			return err
		}
		if currentOpts.help {
			printCurrentIDUsage(os.Stdout)
			return nil
		}
		return emitCurrentID(opts.provider, root, currentOpts.cwd, currentOpts.history)
	default:
		return usageError("unsupported command: " + opts.command)
	}
}

type globalOptions struct {
	provider string
	root     string
	command  string
	help     bool
}

func parseGlobalArgs(args []string) (globalOptions, []string, error) {
	opts := globalOptions{provider: "codex"}

	for len(args) > 0 {
		arg := args[0]
		switch {
		case arg == "-h" || arg == "--help":
			opts.help = true
			return opts, nil, nil
		case arg == "--provider":
			value, rest, err := consumeValue(arg, args[1:])
			if err != nil {
				return opts, nil, err
			}
			opts.provider = value
			args = rest
		case strings.HasPrefix(arg, "--provider="):
			opts.provider = strings.TrimPrefix(arg, "--provider=")
			args = args[1:]
		case arg == "--root":
			value, rest, err := consumeValue(arg, args[1:])
			if err != nil {
				return opts, nil, err
			}
			opts.root = value
			args = rest
		case strings.HasPrefix(arg, "--root="):
			opts.root = strings.TrimPrefix(arg, "--root=")
			args = args[1:]
		case strings.HasPrefix(arg, "-"):
			return opts, nil, usageError("unknown option: " + arg)
		default:
			opts.command = arg
			return opts, args[1:], nil
		}
	}

	return opts, nil, nil
}

type currentIDOptions struct {
	cwd     string
	history string
	help    bool
}

func parseCurrentIDArgs(args []string, defaults providerDefaults) (currentIDOptions, error) {
	opts := currentIDOptions{history: expandUser(defaults.history)}

	for len(args) > 0 {
		arg := args[0]
		switch {
		case arg == "-h" || arg == "--help":
			opts.help = true
			return opts, nil
		case arg == "--cwd":
			value, rest, err := consumeValue(arg, args[1:])
			if err != nil {
				return opts, err
			}
			opts.cwd = value
			args = rest
		case strings.HasPrefix(arg, "--cwd="):
			opts.cwd = strings.TrimPrefix(arg, "--cwd=")
			args = args[1:]
		case arg == "--history":
			value, rest, err := consumeValue(arg, args[1:])
			if err != nil {
				return opts, err
			}
			opts.history = expandUser(value)
			args = rest
		case strings.HasPrefix(arg, "--history="):
			opts.history = expandUser(strings.TrimPrefix(arg, "--history="))
			args = args[1:]
		default:
			return opts, usageError("current-id does not accept positional arguments")
		}
	}

	return opts, nil
}

func consumeValue(name string, args []string) (string, []string, error) {
	if len(args) == 0 {
		return "", args, usageError(name + " requires a value")
	}
	return args[0], args[1:], nil
}

func usageError(msg string) error {
	return exitError{code: 2, msg: msg}
}

func wantsCommandHelp(args []string) bool {
	return len(args) == 1 && (args[0] == "-h" || args[0] == "--help")
}

func printUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: agent-session-store [--provider codex|claude|gemini] [--root PATH] refresh")
	fmt.Fprintln(out, "       agent-session-store [--provider codex|claude|gemini] [--root PATH] ids CWD")
	fmt.Fprintln(out, "       agent-session-store [--provider codex|claude|gemini] [--root PATH] wait-new CWD KNOWN_IDS_JSON TIMEOUT_SECONDS INTERVAL_SECONDS")
	fmt.Fprintln(out, "       agent-session-store [--provider codex|claude|gemini] [--root PATH] watch-new CWD KNOWN_IDS_JSON TIMEOUT_SECONDS INTERVAL_SECONDS TITLE_TIMEOUT_SECONDS")
	fmt.Fprintln(out, "       agent-session-store [--provider codex|claude|gemini] [--root PATH] current-id [--cwd CWD] [--history PATH]")
}

func printRefreshUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: agent-session-store [--provider codex|claude|gemini] [--root PATH] refresh")
}

func printIDsUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: agent-session-store [--provider codex|claude|gemini] [--root PATH] ids CWD")
}

func printWaitNewUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: agent-session-store [--provider codex|claude|gemini] [--root PATH] wait-new CWD KNOWN_IDS_JSON TIMEOUT_SECONDS INTERVAL_SECONDS")
}

func printWatchNewUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: agent-session-store [--provider codex|claude|gemini] [--root PATH] watch-new CWD KNOWN_IDS_JSON TIMEOUT_SECONDS INTERVAL_SECONDS TITLE_TIMEOUT_SECONDS")
}

func printCurrentIDUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: agent-session-store [--provider codex|claude|gemini] [--root PATH] current-id [--cwd CWD] [--history PATH]")
}

func compactTitleText(text string) string {
	var builder strings.Builder
	pendingSpace := false
	written := 0

	for _, char := range text {
		if unicode.IsSpace(char) {
			if written > 0 {
				pendingSpace = true
			}
			continue
		}
		if pendingSpace {
			if written >= titleMaxRunes {
				return builder.String() + "..."
			}
			builder.WriteByte(' ')
			written++
		}
		pendingSpace = false
		if written >= titleMaxRunes {
			return builder.String() + "..."
		}
		builder.WriteRune(char)
		written++
	}

	return builder.String()
}

func isGeneratedContextMessage(text string) bool {
	text = compactTitleText(text)
	if text == "" {
		return false
	}
	prefixes := []string{
		"# AGENTS.md instructions for ",
		"<environment_context>",
		"<permissions instructions>",
		"<collaboration_mode>",
		"<skills_instructions>",
		"<command-name>",
		"<local-command-stdout>",
	}
	for _, prefix := range prefixes {
		if strings.HasPrefix(text, prefix) {
			return true
		}
	}
	return false
}

func normalizeTitle(value string) string {
	text := compactTitleText(value)
	if text == "" || isGeneratedContextMessage(text) {
		return ""
	}
	return text
}

func contentText(content any) string {
	switch value := content.(type) {
	case string:
		return value
	case []any:
		var builder strings.Builder
		for _, item := range value {
			if builder.Len() > titleMaxRunes*4 {
				break
			}
			switch typed := item.(type) {
			case string:
				builder.WriteByte(' ')
				builder.WriteString(typed)
			case map[string]any:
				if text, ok := stringValue(typed["text"]); ok {
					builder.WriteByte(' ')
					builder.WriteString(text)
				} else if text, ok := stringValue(typed["content"]); ok {
					builder.WriteByte(' ')
					builder.WriteString(text)
				}
			}
		}
		return builder.String()
	default:
		return ""
	}
}

func codexUserMessageTitle(payload map[string]any) string {
	payloadType, _ := stringValue(payload["type"])
	if payloadType == "user_message" {
		if message, ok := stringValue(payload["message"]); ok {
			return normalizeTitle(message)
		}
		return ""
	}
	if payloadType == "message" {
		role, _ := stringValue(payload["role"])
		if role == "user" {
			return normalizeTitle(contentText(payload["content"]))
		}
	}
	return ""
}

func claudeUserMessageTitle(item map[string]any) string {
	itemType, _ := stringValue(item["type"])
	if itemType != "user" {
		return ""
	}
	if isMeta, ok := item["isMeta"].(bool); ok && isMeta {
		return ""
	}

	message, ok := item["message"].(map[string]any)
	if !ok {
		return ""
	}
	role, _ := stringValue(message["role"])
	if role != "user" {
		return ""
	}
	return normalizeTitle(contentText(message["content"]))
}

func geminiUserMessageTitle(item map[string]any) string {
	if messages, ok := item["messages"].([]any); ok {
		for _, raw := range messages {
			message, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			if title := geminiUserMessageTitle(message); title != "" {
				return title
			}
		}
	}

	role, _ := stringValue(item["role"])
	itemType, _ := stringValue(item["type"])
	if role != "user" && itemType != "user" {
		return ""
	}
	if title := normalizeTitle(contentText(item["content"])); title != "" {
		return title
	}
	if title := normalizeTitle(contentText(item["parts"])); title != "" {
		return title
	}
	if title := normalizeTitle(contentText(item["text"])); title != "" {
		return title
	}
	return ""
}

func fileMtimeTimestamp(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return ""
	}
	return info.ModTime().UTC().Format("2006-01-02T15:04:05.000Z")
}

func millisTimestamp(value any) string {
	millis, ok := numberFloat(value)
	if !ok {
		return ""
	}
	return time.Unix(0, int64(millis*float64(time.Millisecond))).UTC().Format("2006-01-02T15:04:05.000Z")
}

func parseCodexSession(path string, cwd string) *session {
	result := session{Provider: "codex", Path: path}
	err := readSessionLines(path, func(item map[string]any) bool {
		payload, ok := item["payload"].(map[string]any)
		if !ok {
			return true
		}

		itemType, _ := stringValue(item["type"])
		if itemType == "session_meta" {
			if id, ok := stringValue(payload["id"]); ok {
				result.ID = id
			}
			if itemCWD, ok := stringValue(payload["cwd"]); ok {
				result.CWD = itemCWD
			}
			if timestamp, ok := stringValue(payload["timestamp"]); ok {
				result.Timestamp = timestamp
			}
			if originator, ok := stringValue(payload["originator"]); ok {
				result.Originator = originator
			}
		}

		if result.Title == "" {
			result.Title = codexUserMessageTitle(payload)
		}

		return !(result.ID != "" && result.CWD != "" && result.Timestamp != "" && result.Title != "")
	})
	if err != nil {
		return nil
	}
	if (cwd != "" && result.CWD != cwd) || result.ID == "" || result.Timestamp == "" || result.Originator != "codex-tui" {
		return nil
	}

	result.UpdatedAt = fileMtimeTimestamp(path)
	if result.UpdatedAt == "" {
		result.UpdatedAt = result.Timestamp
	}
	return &result
}

func parseClaudeSession(path string, cwd string) *session {
	result := session{Provider: "claude", Path: path}
	var titleFromPrompt string
	var fallbackTitle string

	err := readSessionLines(path, func(item map[string]any) bool {
		if result.ID == "" {
			if id, ok := stringValue(item["sessionId"]); ok {
				result.ID = id
			}
		}
		if result.CWD == "" {
			if itemCWD, ok := stringValue(item["cwd"]); ok {
				result.CWD = itemCWD
			}
		}
		if result.Timestamp == "" {
			if timestamp, ok := stringValue(item["timestamp"]); ok {
				result.Timestamp = timestamp
			} else if timestamp := millisTimestamp(item["timestamp"]); timestamp != "" {
				result.Timestamp = timestamp
			}
		}

		if aiTitle, ok := stringValue(item["aiTitle"]); ok {
			if title := normalizeTitle(aiTitle); title != "" {
				result.Title = title
			}
		}
		if fallbackTitle == "" {
			if lastPrompt, ok := stringValue(item["lastPrompt"]); ok {
				fallbackTitle = normalizeTitle(lastPrompt)
			}
		}
		if titleFromPrompt == "" {
			titleFromPrompt = claudeUserMessageTitle(item)
		}

		return !(result.ID != "" && result.CWD != "" && result.Timestamp != "" && result.Title != "")
	})
	if err != nil {
		return nil
	}

	if result.ID == "" {
		filename := filepath.Base(path)
		if strings.HasSuffix(filename, ".jsonl") {
			result.ID = strings.TrimSuffix(filename, ".jsonl")
		}
	}
	if result.Title == "" {
		result.Title = titleFromPrompt
	}
	if result.Title == "" {
		result.Title = fallbackTitle
	}
	if (cwd != "" && result.CWD != cwd) || result.ID == "" || result.Timestamp == "" {
		return nil
	}

	result.UpdatedAt = fileMtimeTimestamp(path)
	if result.UpdatedAt == "" {
		result.UpdatedAt = result.Timestamp
	}
	return &result
}

func projectRootForGeminiSession(path string) string {
	projectDir := filepath.Dir(filepath.Dir(path))
	projectRootPath := filepath.Join(projectDir, ".project_root")
	data, err := os.ReadFile(projectRootPath)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func applyGeminiSessionItem(result *session, item map[string]any) {
	if result.ID == "" {
		if id, ok := stringValue(item["sessionId"]); ok {
			result.ID = id
		}
	}
	if result.Timestamp == "" {
		if timestamp, ok := stringValue(item["startTime"]); ok {
			result.Timestamp = timestamp
		} else if timestamp, ok := stringValue(item["timestamp"]); ok {
			result.Timestamp = timestamp
		}
	}
	if result.UpdatedAt == "" {
		if updatedAt, ok := stringValue(item["lastUpdated"]); ok {
			result.UpdatedAt = updatedAt
		} else if updatedAt, ok := stringValue(item["updatedAt"]); ok {
			result.UpdatedAt = updatedAt
		}
	}
	if result.Title == "" {
		result.Title = geminiUserMessageTitle(item)
	}
}

func parseGeminiJSONObject(path string, cwd string) *session {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var item map[string]any
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(&item); err != nil {
		return nil
	}

	result := session{Provider: "gemini", Path: path, CWD: projectRootForGeminiSession(path)}
	applyGeminiSessionItem(&result, item)
	return finishGeminiSession(result, cwd)
}

func parseGeminiSession(path string, cwd string) *session {
	if strings.HasSuffix(path, ".json") {
		return parseGeminiJSONObject(path, cwd)
	}

	result := session{Provider: "gemini", Path: path, CWD: projectRootForGeminiSession(path)}
	err := readSessionLines(path, func(item map[string]any) bool {
		applyGeminiSessionItem(&result, item)
		return !(result.ID != "" && result.CWD != "" && result.Timestamp != "" && result.Title != "" && result.UpdatedAt != "")
	})
	if err != nil {
		return nil
	}
	return finishGeminiSession(result, cwd)
}

func finishGeminiSession(result session, cwd string) *session {
	if result.ID == "" {
		filename := filepath.Base(result.Path)
		if strings.HasPrefix(filename, "session-") {
			parts := strings.Split(strings.TrimSuffix(strings.TrimSuffix(filename, ".jsonl"), ".json"), "-")
			if len(parts) > 0 {
				result.ID = parts[len(parts)-1]
			}
		}
	}
	if (cwd != "" && result.CWD != cwd) || result.ID == "" || result.CWD == "" || result.Timestamp == "" {
		return nil
	}

	if result.UpdatedAt == "" {
		result.UpdatedAt = fileMtimeTimestamp(result.Path)
	}
	if result.UpdatedAt == "" {
		result.UpdatedAt = result.Timestamp
	}
	return &result
}

func readSessionLines(path string, handle func(map[string]any) bool) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()

	reader := bufio.NewReader(io.LimitReader(file, sessionReadBytes))
	for {
		line, err := reader.ReadBytes('\n')
		if len(line) > 0 {
			line = bytes.TrimSpace(line)
			if len(line) > 0 {
				if item, ok := decodeJSONObject(line); ok {
					if !handle(item) {
						return nil
					}
				}
			}
		}
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}

func decodeJSONObject(line []byte) (map[string]any, bool) {
	decoder := json.NewDecoder(bytes.NewReader(line))
	decoder.UseNumber()
	var item map[string]any
	if err := decoder.Decode(&item); err != nil {
		return nil, false
	}
	return item, true
}

func sessionFiles(provider string, root string) []string {
	files := []string{}
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		if provider == "gemini" {
			parent := filepath.Base(filepath.Dir(path))
			if parent == "chats" && strings.HasPrefix(entry.Name(), "session-") &&
				(strings.HasSuffix(entry.Name(), ".jsonl") || strings.HasSuffix(entry.Name(), ".json")) {
				files = append(files, path)
			}
			return nil
		}
		if strings.HasSuffix(entry.Name(), ".jsonl") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return files
	}
	return files
}

func parseSession(provider string, path string, cwd string) *session {
	switch provider {
	case "codex":
		return parseCodexSession(path, cwd)
	case "claude":
		return parseClaudeSession(path, cwd)
	case "gemini":
		return parseGeminiSession(path, cwd)
	default:
		return nil
	}
}

func sessions(provider string, root string, cwd string) []session {
	items := []session{}
	for _, path := range sessionFiles(provider, root) {
		if item := parseSession(provider, path, cwd); item != nil {
			items = append(items, *item)
		}
	}
	sort.Slice(items, func(i, j int) bool {
		left := items[i].UpdatedAt
		if left == "" {
			left = items[i].Timestamp
		}
		right := items[j].UpdatedAt
		if right == "" {
			right = items[j].Timestamp
		}
		if left == right {
			return items[i].Timestamp > items[j].Timestamp
		}
		return left > right
	})
	return items
}

func emitRefresh(provider string, root string) error {
	return emitJSON(refreshPayload{
		Version:     version,
		Provider:    provider,
		GeneratedAt: time.Now().Unix(),
		Sessions:    sessions(provider, root, ""),
	})
}

func emitIDs(provider string, root string, cwd string) error {
	items := sessions(provider, root, cwd)
	ids := make([]string, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.ID)
	}
	return emitJSON(idsPayload{Version: version, Provider: provider, IDs: ids})
}

func findNewSession(provider string, root string, cwd string, knownIDs map[string]bool) *session {
	for _, item := range sessions(provider, root, cwd) {
		if !knownIDs[item.ID] {
			return &item
		}
	}
	return nil
}

func emitWaitNew(provider string, root string, args []string) error {
	cwd := args[0]
	knownIDs, err := parseKnownIDs(args[1])
	if err != nil {
		return err
	}
	timeout, err := parseSeconds(args[2], "timeout_seconds")
	if err != nil {
		return err
	}
	interval, err := parseSeconds(args[3], "interval_seconds")
	if err != nil {
		return err
	}
	deadline := time.Now().Add(timeout)

	for {
		if item := findNewSession(provider, root, cwd, knownIDs); item != nil {
			return emitJSON(sessionPayload{Version: version, Provider: provider, Session: item})
		}
		if !time.Now().Before(deadline) {
			return emitJSON(sessionPayload{Version: version, Provider: provider, Session: nil})
		}
		sleepPollingInterval(interval)
	}
}

func emitWatchNew(provider string, root string, args []string) error {
	cwd := args[0]
	knownIDs, err := parseKnownIDs(args[1])
	if err != nil {
		return err
	}
	timeout, err := parseSeconds(args[2], "timeout_seconds")
	if err != nil {
		return err
	}
	interval, err := parseSeconds(args[3], "interval_seconds")
	if err != nil {
		return err
	}
	titleTimeout, err := parseSeconds(args[4], "title_timeout_seconds")
	if err != nil {
		return err
	}

	deadline := time.Now().Add(timeout)
	var newSession *session
	for {
		newSession = findNewSession(provider, root, cwd, knownIDs)
		if newSession != nil {
			if err := emitJSON(watchPayload{Version: version, Provider: provider, Event: "session", Session: newSession}); err != nil {
				return err
			}
			break
		}
		if !time.Now().Before(deadline) {
			return emitJSON(watchPayload{Version: version, Provider: provider, Event: "timeout"})
		}
		sleepPollingInterval(interval)
	}

	if newSession.Title != "" {
		return emitJSON(watchPayload{Version: version, Provider: provider, Event: "title", Session: newSession})
	}

	titleDeadline := time.Now().Add(titleTimeout)
	for {
		for _, item := range sessions(provider, root, cwd) {
			if item.ID == newSession.ID && item.Title != "" {
				return emitJSON(watchPayload{Version: version, Provider: provider, Event: "title", Session: &item})
			}
		}
		if !time.Now().Before(titleDeadline) {
			return nil
		}
		sleepPollingInterval(interval)
	}
}

func sleepPollingInterval(interval time.Duration) {
	if interval <= 0 {
		time.Sleep(time.Millisecond)
		return
	}
	time.Sleep(interval)
}

func latestHistorySessionID(provider string, historyPath string, cwd string) string {
	data, err := os.ReadFile(historyPath)
	if err != nil {
		return ""
	}
	lines := bytes.Split(data, []byte{'\n'})
	for index := len(lines) - 1; index >= 0; index-- {
		line := bytes.TrimSpace(lines[index])
		if len(line) == 0 {
			continue
		}
		item, ok := decodeJSONObject(line)
		if !ok {
			continue
		}
		switch provider {
		case "codex":
			if sessionID, ok := stringValue(item["session_id"]); ok && sessionID != "" {
				return sessionID
			}
		case "claude":
			if cwd != "" {
				project, _ := stringValue(item["project"])
				if project != cwd {
					continue
				}
			}
			if sessionID, ok := stringValue(item["sessionId"]); ok && sessionID != "" {
				return sessionID
			}
		case "gemini":
			if sessionID, ok := stringValue(item["sessionId"]); ok && sessionID != "" {
				return sessionID
			}
		}
	}
	return ""
}

func resolveCurrentID(provider string, root string, cwd string, historyPath string) string {
	defaults := providers[provider]
	for _, key := range defaults.envSessionKeys {
		if sessionID := os.Getenv(key); sessionID != "" {
			return sessionID
		}
	}

	if cwd != "" {
		scoped := sessions(provider, root, cwd)
		if len(scoped) > 0 {
			return scoped[0].ID
		}
	}

	if sessionID := latestHistorySessionID(provider, historyPath, cwd); sessionID != "" {
		return sessionID
	}

	allSessions := sessions(provider, root, "")
	if len(allSessions) > 0 {
		return allSessions[0].ID
	}

	return ""
}

func emitCurrentID(provider string, root string, cwd string, historyPath string) error {
	sessionID := resolveCurrentID(provider, root, cwd, historyPath)
	if sessionID == "" {
		return exitError{code: 1, msg: fmt.Sprintf("could not resolve current %s session id", provider)}
	}
	fmt.Println(sessionID)
	return nil
}

func emitJSON(payload any) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(os.Stdout, string(encoded))
	return err
}

func parseKnownIDs(value string) (map[string]bool, error) {
	var raw []any
	if err := json.Unmarshal([]byte(value), &raw); err != nil {
		return nil, usageError("known_ids_json must be a JSON array")
	}
	known := make(map[string]bool, len(raw))
	for _, item := range raw {
		if id, ok := item.(string); ok {
			known[id] = true
		}
	}
	return known, nil
}

func parseSeconds(value string, name string) (time.Duration, error) {
	seconds, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0, usageError(name + " must be a number")
	}
	return time.Duration(seconds * float64(time.Second)), nil
}

func stringValue(value any) (string, bool) {
	text, ok := value.(string)
	return text, ok
}

func numberFloat(value any) (float64, bool) {
	switch typed := value.(type) {
	case json.Number:
		value, err := typed.Float64()
		return value, err == nil
	case float64:
		return typed, true
	case int64:
		return float64(typed), true
	default:
		return 0, false
	}
}

func expandUser(path string) string {
	if path == "" || path[0] != '~' {
		return path
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return path
	}
	if path == "~" {
		return home
	}
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(home, path[2:])
	}
	return path
}
