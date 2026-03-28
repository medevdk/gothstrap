package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/devdk/gothstrap/internal/prompt"
	"github.com/devdk/gothstrap/internal/scaffold"
)

const version = "0.1.0"

func main() {
	vLong  := flag.Bool("version", false, "Print version and exit")
	vShort := flag.Bool("v", false, "Print version and exit")
	flag.Parse()

	if *vLong || *vShort {
		fmt.Printf("gothstrap v%s\n", version)
		os.Exit(0)
	}

	cfg, err := prompt.Gather()
	if err != nil {
		// "cancelled" is a clean exit, anything else is a real error.
		if err.Error() != "cancelled" {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		os.Exit(0)
	}

	if err := scaffold.Generate(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "scaffold error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\n✅  Project '%s' ready!\n\n", cfg.ProjectName)
	fmt.Printf("  cd %s\n", cfg.OutputDir)
	fmt.Println("  make setup   # download HTMX, install templ & tailwind")
	fmt.Println("  make dev     # start the server")
	fmt.Println()
}
