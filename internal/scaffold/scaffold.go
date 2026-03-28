package scaffold

import (
	"bytes"
	"embed"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/devdk/gothstrap/internal/config"
)

//go:embed templates
var templateFS embed.FS

// Generate writes all embedded template files into cfg.OutputDir,
// executing each file as a Go text/template with cfg as data,
// then runs git init with an initial commit.
func Generate(cfg *config.Config) error {
	fmt.Printf("\n🔨  Scaffolding '%s' into %s …\n\n", cfg.ProjectName, cfg.OutputDir)

	if err := fs.WalkDir(templateFS, "templates", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		// Compute destination path by stripping the leading "templates/" prefix.
		rel, err := filepath.Rel("templates", path)
		if err != nil {
			return err
		}

		// Strip .tmpl extension so go.mod.tmpl → go.mod, etc.
		destRel := strings.TrimSuffix(rel, ".tmpl")
		dest := filepath.Join(cfg.OutputDir, destRel)

		if d.IsDir() {
			if mkErr := os.MkdirAll(dest, 0755); mkErr != nil {
				return fmt.Errorf("mkdir %s: %w", dest, mkErr)
			}
			return nil
		}

		return writeFile(path, dest, cfg)
	}); err != nil {
		return err
	}

	if err := gitInit(cfg.OutputDir); err != nil {
		// Non-fatal — git may not be installed in all environments.
		fmt.Printf("  ⚠  git init skipped: %v\n", err)
	}

	return nil
}

// gitInit creates a git repo with a single initial commit.
func gitInit(dir string) error {
	run := func(args ...string) error {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		out, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("git %s: %w\n%s", strings.Join(args, " "), err, out)
		}
		return nil
	}

	if err := run("init", "-b", "main"); err != nil {
		return err
	}
	if err := run("add", "."); err != nil {
		return err
	}
	if err := run("commit", "-m", "Initial commit: GoTH skeleton"); err != nil {
		return err
	}

	fmt.Println("  ✓  git init (branch: main, initial commit)")
	return nil
}

func writeFile(srcPath, destPath string, cfg *config.Config) error {
	raw, err := templateFS.ReadFile(srcPath)
	if err != nil {
		return fmt.Errorf("read template %s: %w", srcPath, err)
	}

	// Only files with the .tmpl extension are processed as Go templates.
	// This avoids clashing with templ's own { } syntax in .templ files.
	if strings.HasSuffix(srcPath, ".tmpl") {
		tmpl, parseErr := template.New(filepath.Base(srcPath)).Parse(string(raw))
		if parseErr != nil {
			return fmt.Errorf("parse template %s: %w", srcPath, parseErr)
		}
		var buf bytes.Buffer
		if execErr := tmpl.Execute(&buf, cfg); execErr != nil {
			return fmt.Errorf("execute template %s: %w", srcPath, execErr)
		}
		return writeBytesToDisk(destPath, buf.Bytes())
	}

	// All other files (Makefile, README, .templ, .go, …) are written verbatim.
	return writeBytesToDisk(destPath, raw)
}

func writeBytesToDisk(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	fmt.Printf("  ✓  %s\n", path)
	return nil
}
