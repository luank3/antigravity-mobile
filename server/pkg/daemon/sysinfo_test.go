package daemon

import "testing"

func TestReadSystemUsageBounds(t *testing.T) {
	cpu, ram := ReadSystemUsage()
	if cpu < 0 || cpu > 100 {
		t.Fatalf("cpu percent out of bounds: %d", cpu)
	}
	if ram <= 0 || ram > 100 {
		t.Fatalf("expected non-zero Linux RAM percent on host, got: %d", ram)
	}
}
