package llm

import "testing"

func TestExtractJSONObject(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		want    string
		wantErr bool
	}{
		{name: "plain object", in: `{"a":1}`, want: `{"a":1}`},
		{
			name: "with prose around it",
			in:   "Here is the JSON:\n{\"a\":1}\nThanks!",
			want: `{"a":1}`,
		},
		{
			name: "fenced code block",
			in:   "```json\n{\"a\":1,\"b\":2}\n```",
			want: `{"a":1,"b":2}`,
		},
		{
			name: "nested objects",
			in:   `prefix {"a":{"b":{"c":1}}} suffix`,
			want: `{"a":{"b":{"c":1}}}`,
		},
		{
			name: "braces inside strings are ignored",
			in:   `{"note":"value with } brace and { brace"}`,
			want: `{"note":"value with } brace and { brace"}`,
		},
		{
			name: "escaped quote inside string",
			in:   `{"note":"he said \"hi}\" today"}`,
			want: `{"note":"he said \"hi}\" today"}`,
		},
		{name: "no object", in: "no json here", wantErr: true},
		{name: "unbalanced", in: `{"a":1`, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := extractJSONObject(tt.in)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("expected error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
		})
	}
}
