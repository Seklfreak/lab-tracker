package llm

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

// ExtractedResult is one parsed measurement from a lab PDF.
type ExtractedResult struct {
	TestName       string   `json:"test_name"`
	Value          string   `json:"value"`
	ValueNumeric   *float64 `json:"value_numeric"`
	Unit           *string  `json:"unit"`
	ReferenceRange *string  `json:"reference_range"`
	ReferenceLow   *float64 `json:"reference_low"`
	ReferenceHigh  *float64 `json:"reference_high"`
	Flag           *string  `json:"flag"`
	Specimen       *string  `json:"specimen"`
}

// ExtractedReport is the full structured extraction of one lab PDF.
type ExtractedReport struct {
	LabName       *string           `json:"lab_name"`
	CollectedDate *string           `json:"collected_date"`
	ReportedDate  *string           `json:"reported_date"`
	Results       []ExtractedResult `json:"results"`
}

// Extractor calls the Anthropic API to turn a lab PDF into structured data.
type Extractor struct {
	client anthropic.Client
}

func NewExtractor(apiKey string) *Extractor {
	return &Extractor{client: anthropic.NewClient(option.WithAPIKey(apiKey))}
}

const instructions = `You are a clinical lab report parser. The attached PDF is a laboratory results report.

Extract every individual test result into JSON. Respond with ONLY a single JSON object (no markdown, no code fences, no commentary) matching exactly this shape:

{
  "lab_name": string | null,            // e.g. "Quest Diagnostics", "LabCorp", hospital name
  "collected_date": "YYYY-MM-DD" | null, // specimen collection date
  "reported_date": "YYYY-MM-DD" | null,  // date the report was issued
  "results": [
    {
      "test_name": string,               // the test name exactly as printed
      "value": string,                   // the result value exactly as printed, e.g. "95", "<5", "Negative"
      "value_numeric": number | null,    // numeric value if the result is a plain number, else null
      "unit": string | null,             // e.g. "mg/dL", "%"
      "reference_range": string | null,  // the reference interval exactly as printed, e.g. "70-99", "<150"
      "reference_low": number | null,    // numeric lower bound if present, else null
      "reference_high": number | null,   // numeric upper bound if present, else null
      "flag": string | null,             // abnormal flag if present, e.g. "H", "L", "HIGH", null otherwise
      "specimen": string | null          // specimen type: "serum", "plasma", "whole blood", "urine", or null if unclear
    }
  ]
}

Rules:
- Include only actual analyte measurements. Skip headers, patient demographics, page footers, and narrative comments.
- Preserve the exact printed test name; do not normalize it.
- reference_range applies to qualitative results too: capture the expected/normal value when printed (e.g. "Negative", "Non-Reactive", "Not Detected", "Yellow", "Clear"). For these, set reference_low and reference_high to null and put the expected value in reference_range. For numeric results, also set reference_low/high from the interval where possible.
- If a date is ambiguous, prefer the collection date for collected_date.
- For "specimen": use the panel/section context. Urinalysis and urine dipstick or microscopic tests are "urine". CBC and hematology/differential tests are "whole blood". Most chemistry, lipid, thyroid, and immunoassay/serology tests are "serum". Use null only if genuinely unclear.
- If no results are found, return an empty "results" array.`

// Extract parses a PDF's bytes into an ExtractedReport.
func (e *Extractor) Extract(ctx context.Context, pdf []byte) (*ExtractedReport, error) {
	b64 := base64.StdEncoding.EncodeToString(pdf)

	msg, err := e.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.ModelClaudeOpus4_8,
		MaxTokens: 16000,
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewDocumentBlock(anthropic.Base64PDFSourceParam{Data: b64}),
				anthropic.NewTextBlock(instructions),
			),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic request: %w", err)
	}

	var sb strings.Builder
	for _, block := range msg.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			sb.WriteString(t.Text)
		}
	}
	raw := sb.String()

	jsonStr, err := extractJSONObject(raw)
	if err != nil {
		return nil, fmt.Errorf("locate JSON in model output: %w", err)
	}

	var report ExtractedReport
	if err := json.Unmarshal([]byte(jsonStr), &report); err != nil {
		return nil, fmt.Errorf("unmarshal extraction: %w", err)
	}
	return &report, nil
}

// extractJSONObject returns the substring from the first '{' to its matching
// closing '}', tolerating any prose or code fences the model might add.
func extractJSONObject(s string) (string, error) {
	start := strings.IndexByte(s, '{')
	if start < 0 {
		return "", fmt.Errorf("no JSON object found")
	}
	depth := 0
	inString := false
	escaped := false
	for i := start; i < len(s); i++ {
		c := s[i]
		switch {
		case escaped:
			escaped = false
		case c == '\\':
			escaped = true
		case c == '"':
			inString = !inString
		case inString:
			// skip
		case c == '{':
			depth++
		case c == '}':
			depth--
			if depth == 0 {
				return s[start : i+1], nil
			}
		}
	}
	return "", fmt.Errorf("unbalanced JSON object")
}
