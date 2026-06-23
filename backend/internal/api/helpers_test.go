package api

import "testing"

func TestTextRoundTrip(t *testing.T) {
	if got := textToPtr(ptrToText(nil)); got != nil {
		t.Errorf("nil -> text -> ptr: got %v, want nil", *got)
	}
	s := "hello"
	got := textToPtr(ptrToText(&s))
	if got == nil || *got != "hello" {
		t.Errorf("round trip: got %v, want hello", got)
	}
	// empty string is a present value, not null
	empty := ""
	if got := textToPtr(ptrToText(&empty)); got == nil || *got != "" {
		t.Errorf("empty string should round-trip as present: got %v", got)
	}
}

func TestFloat8RoundTrip(t *testing.T) {
	if got := float8ToPtr(ptrToFloat8(nil)); got != nil {
		t.Errorf("nil -> float8 -> ptr: got %v, want nil", *got)
	}
	v := 12.5
	got := float8ToPtr(ptrToFloat8(&v))
	if got == nil || *got != 12.5 {
		t.Errorf("round trip: got %v, want 12.5", got)
	}
	zero := 0.0
	if got := float8ToPtr(ptrToFloat8(&zero)); got == nil || *got != 0 {
		t.Errorf("zero should round-trip as present: got %v", got)
	}
}

func TestPtrToDate(t *testing.T) {
	d := ptrToDate(strptr("2026-01-15"))
	if !d.Valid {
		t.Fatal("expected valid date")
	}
	if got := dateToPtr(d); got == nil || *got != "2026-01-15" {
		t.Errorf("date round trip: got %v, want 2026-01-15", got)
	}

	for _, bad := range []*string{nil, strptr(""), strptr("not-a-date"), strptr("01/15/2026")} {
		if d := ptrToDate(bad); d.Valid {
			t.Errorf("ptrToDate(%v) should be invalid", bad)
		}
	}
}

func TestDateToPtrInvalid(t *testing.T) {
	// an invalid pgtype.Date maps back to nil
	if got := dateToPtr(ptrToDate(nil)); got != nil {
		t.Errorf("invalid date -> ptr: got %v, want nil", *got)
	}
}

func strptr(s string) *string { return &s }
