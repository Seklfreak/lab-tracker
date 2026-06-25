// Package llmtest provides a mock-backed llm.Extractor for tests in other
// packages: it points the Anthropic SDK at a local server returning a canned
// assistant message, so no API key or network is needed.
package llmtest

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/anthropics/anthropic-sdk-go/option"
	"github.com/Seklfreak/lab-tracker/backend/internal/llm"
)

// MockExtractor returns an Extractor whose model always responds with modelText.
func MockExtractor(t *testing.T, modelText string) *llm.Extractor {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":          "msg_test",
			"type":        "message",
			"role":        "assistant",
			"model":       "claude-opus-4-8",
			"content":     []map[string]any{{"type": "text", "text": modelText}},
			"stop_reason": "end_turn",
			"usage":       map[string]any{"input_tokens": 1, "output_tokens": 1},
		})
	}))
	t.Cleanup(srv.Close)
	return llm.NewExtractor("test-key", option.WithBaseURL(srv.URL))
}
