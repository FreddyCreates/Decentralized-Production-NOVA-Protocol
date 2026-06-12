// NOVA Platform Health Check — Go CLI Utility
//
// A lightweight CLI tool for checking organism substrate health.
// Validates canister connectivity, cycle balance, and memory thresholds
// using Fibonacci-based alerting thresholds.
//
// Usage:
//   go run main.go [--endpoint URL] [--threshold LEVEL]
//
// Casa de Medina — Architectos de Architectura Inteligente

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"
)

// PHI is the golden ratio constant
const PHI = 1.6180339887498948482

// Fibonacci returns the n-th Fibonacci number
func Fibonacci(n int) int {
	if n <= 0 {
		return 0
	}
	if n == 1 {
		return 1
	}
	a, b := 0, 1
	for i := 2; i <= n; i++ {
		a, b = b, a+b
	}
	return b
}

// HealthStatus represents the organism health response
type HealthStatus struct {
	Status       string  `json:"status"`
	SystemHealth float64 `json:"systemHealth"`
	Canisters    int     `json:"activeCanisters"`
	Connections  int     `json:"connections"`
	TotalCycles  int64   `json:"totalCycles"`
	TotalMemory  int64   `json:"totalMemory"`
	Timestamp    string  `json:"timestamp"`
}

// HealthLevel categorizes system health using φ-thresholds
type HealthLevel int

const (
	Optimal  HealthLevel = iota // >= 0.9
	Nominal                     // >= φ⁻¹ ≈ 0.618
	Degraded                    // >= φ⁻² ≈ 0.382
	Critical                    // < 0.382
)

func (h HealthLevel) String() string {
	switch h {
	case Optimal:
		return "OPTIMAL"
	case Nominal:
		return "NOMINAL"
	case Degraded:
		return "DEGRADED"
	case Critical:
		return "CRITICAL"
	default:
		return "UNKNOWN"
	}
}

func classifyHealth(health float64) HealthLevel {
	switch {
	case health >= 0.9:
		return Optimal
	case health >= 1.0/PHI: // φ⁻¹ ≈ 0.618
		return Nominal
	case health >= 1.0/(PHI*PHI): // φ⁻² ≈ 0.382
		return Degraded
	default:
		return Critical
	}
}

func main() {
	endpoint := flag.String("endpoint", "http://localhost:3000/api/health", "Health check endpoint URL")
	threshold := flag.String("threshold", "nominal", "Minimum acceptable health level (optimal|nominal|degraded|critical)")
	timeout := flag.Int("timeout", Fibonacci(8), "Request timeout in seconds (default: F(8)=21)")
	verbose := flag.Bool("verbose", false, "Enable verbose output")
	flag.Parse()

	thresholdLevel := Nominal
	switch *threshold {
	case "optimal":
		thresholdLevel = Optimal
	case "nominal":
		thresholdLevel = Nominal
	case "degraded":
		thresholdLevel = Degraded
	case "critical":
		thresholdLevel = Critical
	}

	client := &http.Client{
		Timeout: time.Duration(*timeout) * time.Second,
	}

	if *verbose {
		fmt.Printf("[NOVA] Health check → %s\n", *endpoint)
		fmt.Printf("[NOVA] Timeout: %ds (F(8)=%d)\n", *timeout, Fibonacci(8))
		fmt.Printf("[NOVA] Minimum threshold: %s\n", thresholdLevel)
	}

	resp, err := client.Get(*endpoint)
	if err != nil {
		fmt.Fprintf(os.Stderr, "✗ Connection failed: %v\n", err)
		fmt.Println("STATUS: UNREACHABLE")
		os.Exit(2)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "✗ Unexpected status code: %d\n", resp.StatusCode)
		os.Exit(2)
	}

	var status HealthStatus
	if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
		fmt.Fprintf(os.Stderr, "✗ Failed to parse response: %v\n", err)
		os.Exit(2)
	}

	level := classifyHealth(status.SystemHealth)

	if *verbose {
		fmt.Printf("\n─── Organism Health Report ───\n")
		fmt.Printf("  System Health:    %.1f%%\n", status.SystemHealth*100)
		fmt.Printf("  Health Level:     %s\n", level)
		fmt.Printf("  Active Canisters: %d\n", status.Canisters)
		fmt.Printf("  Connections:      %d\n", status.Connections)
		fmt.Printf("  Total Cycles:     %d\n", status.TotalCycles)
		fmt.Printf("  Total Memory:     %d bytes\n", status.TotalMemory)
		fmt.Printf("  Timestamp:        %s\n", status.Timestamp)
		fmt.Printf("──────────────────────────────\n\n")
	}

	if level <= thresholdLevel {
		fmt.Printf("✓ Health: %s (%.1f%%) — threshold met\n", level, status.SystemHealth*100)
		os.Exit(0)
	} else {
		fmt.Printf("✗ Health: %s (%.1f%%) — below %s threshold\n", level, status.SystemHealth*100, thresholdLevel)
		os.Exit(1)
	}
}
