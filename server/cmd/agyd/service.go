package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// ServiceConfig describes the arguments baked into the agyd systemd --user unit.
type ServiceConfig struct {
	BinaryPath   string
	ConfigDir    string
	AgyBinary    string
	Workspaces   []string
	Relays       []string
	ListenAddrs  []string
	EnableMDNS   bool
	ForcePrivate bool
}

func systemdQuote(arg string) string {
	escaped := strings.ReplaceAll(arg, "%", "%%")
	if strings.ContainsAny(escaped, " \t\n\"'\\") {
		escaped = strings.ReplaceAll(escaped, `\`, `\\`)
		escaped = strings.ReplaceAll(escaped, `"`, `\"`)
		return `"` + escaped + `"`
	}
	return escaped
}

// RenderSystemdUnit renders a systemd --user unit file for running agyd continuously.
func RenderSystemdUnit(cfg ServiceConfig) string {
	bin := cfg.BinaryPath
	if bin == "" {
		bin = "agyd"
	}
	parts := []string{systemdQuote(bin), "run"}
	if cfg.ConfigDir != "" {
		parts = append(parts, "--config-dir", systemdQuote(cfg.ConfigDir))
	}
	if cfg.AgyBinary != "" {
		parts = append(parts, "--agy", systemdQuote(cfg.AgyBinary))
	}
	parts = append(parts, fmt.Sprintf("--mdns=%t", cfg.EnableMDNS))
	if cfg.ForcePrivate {
		parts = append(parts, "--force-private")
	}
	for _, r := range cfg.Relays {
		parts = append(parts, "--relay", systemdQuote(r))
	}
	for _, w := range cfg.Workspaces {
		parts = append(parts, "--workspace", systemdQuote(w))
	}
	for _, l := range cfg.ListenAddrs {
		parts = append(parts, "--listen", systemdQuote(l))
	}

	var b strings.Builder
	b.WriteString("[Unit]\n")
	b.WriteString("Description=Antigravity Mobile Host Daemon (agyd)\n")
	b.WriteString("After=network-online.target\n")
	b.WriteString("Wants=network-online.target\n\n")
	b.WriteString("[Service]\n")
	b.WriteString("Type=simple\n")
	b.WriteString("Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin\n")
	b.WriteString("ExecStart=" + strings.Join(parts, " ") + "\n")
	b.WriteString("Restart=always\n")
	b.WriteString("RestartSec=3\n")
	b.WriteString("LimitNOFILE=65536\n\n")
	b.WriteString("[Install]\n")
	b.WriteString("WantedBy=default.target\n")
	return b.String()
}

func defaultUnitPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "systemd", "user", "agyd.service")
}

func installServiceCmd(args []string) {
	fs := flag.NewFlagSet("install-service", flag.ExitOnError)
	var (
		unitPath     string
		configDir    string
		agyBin       string
		enableMDNS   bool
		forcePrivate bool
		dryRun       bool
		enableUnit   bool
		relays       stringList
		workspaces   stringList
		listenAddrs  stringList
	)
	fs.StringVar(&unitPath, "unit-path", defaultUnitPath(), "Destination systemd user unit file path")
	fs.StringVar(&configDir, "config-dir", defaultConfigDir(), "Daemon state directory")
	fs.StringVar(&agyBin, "agy", "agy", "Path to Antigravity CLI binary")
	fs.BoolVar(&enableMDNS, "mdns", true, "Enable local LAN mDNS discovery")
	fs.BoolVar(&forcePrivate, "force-private", false, "Force private reachability (immediately reserve relays)")
	fs.Var(&relays, "relay", "Circuit Relay v2 multiaddr (repeatable)")
	fs.Var(&workspaces, "workspace", "Allowed workspace root directory (repeatable)")
	fs.Var(&listenAddrs, "listen", "Listen multiaddr (repeatable)")
	fs.BoolVar(&dryRun, "dry-run", false, "Print generated unit file without writing or enabling it")
	fs.BoolVar(&enableUnit, "enable", true, "Run systemctl --user daemon-reload && enable --now")
	_ = fs.Parse(args)

	binPath, err := os.Executable()
	if err != nil {
		log.Fatalf("resolve executable: %v", err)
	}
	if resolved, err := filepath.EvalSymlinks(binPath); err == nil {
		binPath = resolved
	}

	if agyBin != "" && !filepath.IsAbs(agyBin) {
		if found, err := exec.LookPath(agyBin); err == nil {
			agyBin = found
		}
	}
	if absCfg, err := filepath.Abs(configDir); err == nil {
		configDir = absCfg
	}
	absWorkspaces := make([]string, 0, len(workspaces))
	for _, w := range workspaces {
		if absW, err := filepath.Abs(w); err == nil {
			absWorkspaces = append(absWorkspaces, absW)
		} else {
			absWorkspaces = append(absWorkspaces, w)
		}
	}

	unit := RenderSystemdUnit(ServiceConfig{
		BinaryPath:   binPath,
		ConfigDir:    configDir,
		AgyBinary:    agyBin,
		Workspaces:   absWorkspaces,
		Relays:       relays,
		ListenAddrs:  listenAddrs,
		EnableMDNS:   enableMDNS,
		ForcePrivate: forcePrivate,
	})

	if dryRun {
		fmt.Printf("# Target unit path: %s\n\n%s", unitPath, unit)
		return
	}

	if err := os.MkdirAll(filepath.Dir(unitPath), 0o755); err != nil {
		log.Fatalf("create systemd user dir: %v", err)
	}
	if err := os.WriteFile(unitPath, []byte(unit), 0o644); err != nil {
		log.Fatalf("write unit file: %v", err)
	}
	fmt.Printf("Wrote systemd user unit: %s\n", unitPath)

	if !enableUnit {
		return
	}

	unitName := filepath.Base(unitPath)
	if out, err := exec.Command("systemctl", "--user", "daemon-reload").CombinedOutput(); err != nil {
		fmt.Printf("Warning: systemctl --user daemon-reload failed (%v): %s\n", err, strings.TrimSpace(string(out)))
		fmt.Printf("Run manually on a systemd user session:\n  systemctl --user daemon-reload\n  systemctl --user enable --now %s\n", unitName)
		return
	}
	if out, err := exec.Command("systemctl", "--user", "enable", "--now", unitName).CombinedOutput(); err != nil {
		fmt.Printf("Warning: systemctl --user enable --now %s failed (%v): %s\n", unitName, err, strings.TrimSpace(string(out)))
		return
	}

	fmt.Printf("Service enabled and started (%s).\n", unitName)
	fmt.Println("Tip for headless VPS/remote machines so the daemon keeps running when logged out:")
	fmt.Println("  sudo loginctl enable-linger $USER")
}

func uninstallServiceCmd(args []string) {
	fs := flag.NewFlagSet("uninstall-service", flag.ExitOnError)
	unitPath := fs.String("unit-path", defaultUnitPath(), "Path to installed systemd user unit file")
	_ = fs.Parse(args)

	unitName := filepath.Base(*unitPath)
	_ = exec.Command("systemctl", "--user", "disable", "--now", unitName).Run()
	if err := os.Remove(*unitPath); err != nil && !os.IsNotExist(err) {
		log.Fatalf("remove unit file %s: %v", *unitPath, err)
	}
	_ = exec.Command("systemctl", "--user", "daemon-reload").Run()
	fmt.Printf("Removed systemd user unit: %s\n", *unitPath)
}
