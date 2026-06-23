package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/anthropics/anthropic-sdk-go"
)

// AnalyteOption is a catalog entry the matcher can map a raw test name to.
type AnalyteOption struct {
	Name      string
	Specimens []string
	Category  string
}

// MatchInput is one unmatched parsed row to resolve.
type MatchInput struct {
	TestName string
	Specimen string // "" if unknown
}

const matchInstructions = `You map raw laboratory test names to a canonical analyte from a catalog.

Catalog (one per line — NAME | specimens | category):
%s
Input test names (one per line — NAME | specimen):
%s
For each input, choose the catalog NAME only when it is the SAME test under a
different name, abbreviation, or formatting AND would share the same reference
range. Rules:
- Map only same-measurement, same-specimen synonyms (e.g. "GLUC, SERUM" -> "Glucose").
- Do NOT map method or specimen variants whose reference ranges differ — e.g.
  point-of-care (POC), blood-gas, or whole-blood versions of a serum analyte.
  These are distinct analytes; return null so they stay separate.
- If the input's specimen is not compatible with the candidate's specimens,
  return null.
- When unsure, return null. Never force a match.

Respond with ONLY a JSON object (no prose, no code fences):
{"mappings":[{"test_name":"<verbatim input>","analyte":"<exact catalog NAME or null>"}]}`

type matchMapping struct {
	TestName string  `json:"test_name"`
	Analyte  *string `json:"analyte"`
}

type matchResponse struct {
	Mappings []matchMapping `json:"mappings"`
}

// MatchAnalytes asks the model to map each raw test name to an existing catalog
// analyte (by name) or to nothing. It is deliberately conservative: only true
// same-specimen synonyms map; method/specimen variants stay separate so
// reference ranges remain meaningful. Returns testName -> catalog analyte name.
func (e *Extractor) MatchAnalytes(ctx context.Context, inputs []MatchInput, catalog []AnalyteOption) (map[string]string, error) {
	out := map[string]string{}
	if len(inputs) == 0 || len(catalog) == 0 {
		return out, nil
	}

	var cb strings.Builder
	for _, a := range catalog {
		fmt.Fprintf(&cb, "- %s | %s | %s\n", a.Name, strings.Join(a.Specimens, "/"), a.Category)
	}
	var nb strings.Builder
	for _, in := range inputs {
		spec := in.Specimen
		if spec == "" {
			spec = "unknown"
		}
		fmt.Fprintf(&nb, "- %s | %s\n", in.TestName, spec)
	}

	msg, err := e.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.ModelClaudeOpus4_8,
		MaxTokens: 4000,
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock(
				fmt.Sprintf(matchInstructions, cb.String(), nb.String()))),
		},
	})
	if err != nil {
		return out, fmt.Errorf("anthropic match request: %w", err)
	}

	var sb strings.Builder
	for _, block := range msg.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			sb.WriteString(t.Text)
		}
	}
	jsonStr, err := extractJSONObject(sb.String())
	if err != nil {
		return out, fmt.Errorf("locate JSON in match output: %w", err)
	}
	var resp matchResponse
	if err := json.Unmarshal([]byte(jsonStr), &resp); err != nil {
		return out, fmt.Errorf("unmarshal match output: %w", err)
	}
	for _, m := range resp.Mappings {
		if m.Analyte != nil && strings.TrimSpace(*m.Analyte) != "" {
			out[m.TestName] = *m.Analyte
		}
	}
	return out, nil
}
