package main

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// The server registers exactly the expected tools (handlers aren't invoked here,
// so nil queries/extractor are fine — this checks the wiring + schemas).
func TestServerListsTools(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := newMCPServer(nil, nil, logger)

	ct, st := mcp.NewInMemoryTransports()
	ctx := context.Background()
	ss, err := srv.Connect(ctx, st, nil)
	if err != nil {
		t.Fatalf("server connect: %v", err)
	}
	defer ss.Close()

	client := mcp.NewClient(&mcp.Implementation{Name: "test", Version: "0"}, nil)
	cs, err := client.Connect(ctx, ct, nil)
	if err != nil {
		t.Fatalf("client connect: %v", err)
	}
	defer cs.Close()

	res, err := cs.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("list tools: %v", err)
	}
	got := map[string]bool{}
	for _, tl := range res.Tools {
		got[tl.Name] = true
	}
	want := []string{
		"list_profiles", "list_latest_results", "get_analyte_trend",
		"search_analytes", "get_analysis", "generate_analysis",
	}
	for _, name := range want {
		if !got[name] {
			t.Errorf("missing tool %q", name)
		}
	}
	if len(res.Tools) != len(want) {
		t.Errorf("want %d tools, got %d", len(want), len(res.Tools))
	}
}

func TestValueStr(t *testing.T) {
	if got := valueStr(pgtype.Text{String: "NEGATIVE", Valid: true}, pgtype.Float8{}); got != "NEGATIVE" {
		t.Errorf("text value: got %q", got)
	}
	if got := valueStr(pgtype.Text{}, pgtype.Float8{Float64: 1.5, Valid: true}); got != "1.5" {
		t.Errorf("numeric value: got %q", got)
	}
	if got := valueStr(pgtype.Text{String: "  ", Valid: true}, pgtype.Float8{Float64: 2, Valid: true}); got != "2" {
		t.Errorf("blank text should fall back to numeric: got %q", got)
	}
	if got := valueStr(pgtype.Text{}, pgtype.Float8{}); got != "" {
		t.Errorf("empty: got %q", got)
	}
}

func TestRefStr(t *testing.T) {
	cases := []struct {
		name      string
		low, high pgtype.Float8
		text      pgtype.Text
		want      string
		wantNil   bool
	}{
		{name: "range", low: f8(70), high: f8(99), want: "70-99"},
		{name: "upper only", high: f8(5), want: "<5"},
		{name: "lower only", low: f8(60), want: ">60"},
		{name: "text wins", low: f8(70), high: f8(99), text: txt("Negative"), want: "Negative"},
		{name: "none", wantNil: true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := refStr(c.low, c.high, c.text)
			if c.wantNil {
				if got != nil {
					t.Errorf("want nil, got %q", *got)
				}
				return
			}
			if got == nil || *got != c.want {
				t.Errorf("want %q, got %v", c.want, got)
			}
		})
	}
}

func TestDateAndTextToPtr(t *testing.T) {
	d := dateToPtr(pgtype.Date{Time: time.Date(2025, 9, 26, 0, 0, 0, 0, time.UTC), Valid: true})
	if d == nil || *d != "2025-09-26" {
		t.Errorf("dateToPtr: got %v", d)
	}
	if dateToPtr(pgtype.Date{}) != nil {
		t.Error("invalid date should be nil")
	}
	if got := textToPtr(txt("Quest")); got == nil || *got != "Quest" {
		t.Errorf("textToPtr: got %v", got)
	}
	if textToPtr(pgtype.Text{String: "  ", Valid: true}) != nil {
		t.Error("blank text should be nil")
	}
}

func f8(v float64) pgtype.Float8 { return pgtype.Float8{Float64: v, Valid: true} }
func txt(s string) pgtype.Text   { return pgtype.Text{String: s, Valid: true} }
