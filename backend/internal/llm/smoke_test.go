package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/anthropics/anthropic-sdk-go/option"
)

// mockExtractor returns an Extractor whose Anthropic client is pointed at a
// local server that always replies with modelText as the assistant message —
// so the real SDK request/response + our parsing run, with no API key/network.
// Extract streams and the other calls don't, so the server answers in whichever
// shape the request asked for.
func mockExtractor(t *testing.T, modelText string) *Extractor {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var req struct {
			Stream bool `json:"stream"`
		}
		_ = json.Unmarshal(raw, &req)
		if req.Stream {
			writeMessageStream(w, modelText)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":          "msg_test",
			"type":        "message",
			"role":        "assistant",
			"model":       "claude-opus-5-5",
			"content":     []map[string]any{{"type": "text", "text": modelText}},
			"stop_reason": "end_turn",
			"usage":       map[string]any{"input_tokens": 1, "output_tokens": 1},
		})
	}))
	t.Cleanup(srv.Close)
	return NewExtractor("test-key", option.WithBaseURL(srv.URL))
}

// writeMessageStream replays text as the server-sent event sequence a streamed
// message arrives in, so the SDK's accumulator runs the way it does in
// production rather than being handed a finished message.
func writeMessageStream(w http.ResponseWriter, text string) {
	w.Header().Set("Content-Type", "text/event-stream")
	events := []struct {
		name string
		data map[string]any
	}{
		{"message_start", map[string]any{"type": "message_start", "message": map[string]any{
			"id": "msg_test", "type": "message", "role": "assistant", "model": "claude-opus-5-5",
			"content": []any{}, "stop_reason": nil, "stop_sequence": nil,
			"usage": map[string]any{"input_tokens": 1, "output_tokens": 1},
		}}},
		{"content_block_start", map[string]any{"type": "content_block_start", "index": 0,
			"content_block": map[string]any{"type": "text", "text": ""}}},
		{"content_block_delta", map[string]any{"type": "content_block_delta", "index": 0,
			"delta": map[string]any{"type": "text_delta", "text": text}}},
		{"content_block_stop", map[string]any{"type": "content_block_stop", "index": 0}},
		{"message_delta", map[string]any{"type": "message_delta",
			"delta": map[string]any{"stop_reason": "end_turn", "stop_sequence": nil},
			"usage": map[string]any{"output_tokens": 1}}},
		{"message_stop", map[string]any{"type": "message_stop"}},
	}
	for _, ev := range events {
		b, err := json.Marshal(ev.data)
		if err != nil {
			panic(err)
		}
		_, _ = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", ev.name, b)
	}
}

func TestCompleteSmoke(t *testing.T) {
	ex := mockExtractor(t, "## What this measures\nGlucose is ...")
	got, err := ex.Complete(context.Background(), "analyze this", 200)
	if err != nil {
		t.Fatal(err)
	}
	if got != "## What this measures\nGlucose is ..." {
		t.Errorf("unexpected completion: %q", got)
	}
}

func TestExtractSmoke(t *testing.T) {
	// Model output wrapped in prose + a code fence to also exercise extractJSONObject.
	model := "Here you go:\n```json\n" + `{
      "lab_name": "Quest Diagnostics",
      "collected_date": "2025-09-26",
      "reported_date": null,
      "results": [
        {"test_name":"Glucose","value":"95","value_numeric":95,"unit":"mg/dL","reference_range":"70-99","reference_low":70,"reference_high":99,"specimen":"serum","note":null},
        {"test_name":"D-Dimer Assay, Plasma","value":"<150","value_numeric":null,"unit":"ng/mL","reference_range":null,"reference_low":null,"reference_high":null,"specimen":"plasma","note":null}
      ]
    }` + "\n```"
	ex := mockExtractor(t, model)

	rep, err := ex.Extract(context.Background(), []byte("%PDF-1.4 fake"))
	if err != nil {
		t.Fatal(err)
	}
	if rep.LabName == nil || *rep.LabName != "Quest Diagnostics" {
		t.Errorf("lab name: %v", rep.LabName)
	}
	if len(rep.Results) != 2 {
		t.Fatalf("want 2 results, got %d", len(rep.Results))
	}
	if r := rep.Results[0]; r.TestName != "Glucose" || r.ValueNumeric == nil || *r.ValueNumeric != 95 {
		t.Errorf("result 0: %+v", r)
	}
	if r := rep.Results[1]; r.Value != "<150" || r.ValueNumeric != nil {
		t.Errorf("result 1 (bounded): %+v", r)
	}
}

func TestMatchAnalytesSmoke(t *testing.T) {
	// GLUC maps to Glucose; the POC variant returns null and must be dropped.
	model := `{"mappings":[{"test_name":"GLUC","analyte":"Glucose"},{"test_name":"POC Chloride","analyte":null}]}`
	ex := mockExtractor(t, model)

	got, err := ex.MatchAnalytes(context.Background(),
		[]MatchInput{{TestName: "GLUC", Specimen: "serum"}, {TestName: "POC Chloride", Specimen: "whole blood"}},
		[]AnalyteOption{
			{Name: "Glucose", Specimens: []string{"serum"}, Category: "Metabolic"},
			{Name: "Chloride", Specimens: []string{"serum"}, Category: "Metabolic"},
		})
	if err != nil {
		t.Fatal(err)
	}
	if got["GLUC"] != "Glucose" {
		t.Errorf(`GLUC -> %q, want "Glucose"`, got["GLUC"])
	}
	if _, ok := got["POC Chloride"]; ok {
		t.Error("null mapping should be dropped")
	}
	if len(got) != 1 {
		t.Errorf("want 1 mapping, got %d", len(got))
	}
}

func TestMatchAnalytesEmpty(t *testing.T) {
	// No inputs/catalog: returns empty without calling the model.
	ex := NewExtractor("unused")
	got, err := ex.MatchAnalytes(context.Background(), nil, nil)
	if err != nil || len(got) != 0 {
		t.Errorf("want empty/no-error, got %v err=%v", got, err)
	}
}
