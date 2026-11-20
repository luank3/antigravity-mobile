package main

import (
	"strings"
	"testing"
)

func TestRenderSystemdUnit(t *testing.T) {
	unit := RenderSystemdUnit(ServiceConfig{
		BinaryPath:   "/usr/local/bin/agyd",
		ConfigDir:    "/home/dat/.config/agyd",
		AgyBinary:    "/home/dat/.local/bin/agy",
		Workspaces:   []string{"/home/dat/dev/my project", "/srv/app"},
		Relays:       []string{"/dns4/relay.example.com/udp/4001/quic-v1/p2p/12D3KooWTest"},
		EnableMDNS:   true,
		ForcePrivate: true,
	})

	checks := []string{
		"[Unit]",
		"After=network-online.target",
		"[Service]",
		"Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin",
		`ExecStart=/usr/local/bin/agyd run --config-dir /home/dat/.config/agyd --agy /home/dat/.local/bin/agy --mdns=true --force-private --relay /dns4/relay.example.com/udp/4001/quic-v1/p2p/12D3KooWTest --workspace "/home/dat/dev/my project" --workspace /srv/app`,
		"Restart=always",
		"WantedBy=default.target",
	}
	for _, want := range checks {
		if !strings.Contains(unit, want) {
			t.Fatalf("rendered unit missing %q:\n%s", want, unit)
		}
	}
}
