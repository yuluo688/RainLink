package session

import (
	"context"
	"testing"
)

func TestProbeDeadlinePublishesFailure(t *testing.T) {
	core := &runningCore{}
	manager := &Manager{active: core}
	// An immediate child deadline exercises the same exhausted-budget path as
	// four failed requests, without contacting external services from a unit test.
	manager.probeFor(context.Background(), core, 0)
	if core.telemetry.ProbeError == "" || core.telemetry.IP != "" || core.telemetry.Latency != nil {
		t.Fatal("expired probe left a false pending state or fabricated measurements")
	}
}

func TestCancelledOrReplacedProbeCannotOverwriteObservations(t *testing.T) {
	for _, cancelled := range []bool{false, true} {
		core := &runningCore{telemetry: Telemetry{IP: "192.0.2.1", ProbeError: "previous observation"}}
		manager := &Manager{active: core}
		ctx, cancel := context.WithCancel(context.Background())
		if cancelled {
			cancel()
		} else {
			manager.active = &runningCore{}
		}
		manager.probeFor(ctx, core, 0)
		cancel()
		if core.telemetry.IP != "192.0.2.1" || core.telemetry.ProbeError != "previous observation" {
			t.Fatal("cancelled or previous session probe overwrote current measurements")
		}
	}
}
