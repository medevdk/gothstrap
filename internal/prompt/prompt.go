package prompt

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/devdk/gothstrap/internal/config"
)

// ── Styles ────────────────────────────────────────────────────────────────────

var (
	titleStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("47")).Bold(true).MarginLeft(2)
	labelStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("47")).Bold(true)
	activeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("46"))
	dimStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	arrowStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("47"))
	errorStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("203")).Bold(true).MarginLeft(2)
	summaryBox  = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(1, 2).BorderForeground(lipgloss.Color("63"))
	doneStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("47")).Bold(true)
	cancelStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("203")).Bold(true)
)

// ── Field index ───────────────────────────────────────────────────────────────

const (
	fieldProject = iota
	fieldModule
	fieldOutput
	fieldCount
)

// ── Model ─────────────────────────────────────────────────────────────────────

type status int

const (
	statusRunning status = iota
	statusDone
	statusCancelled
)

type model struct {
	inputs   [fieldCount]textinput.Model
	focus    int
	status   status
	validErr string // inline validation message
}

func newModel() model {
	m := model{}

	placeholders := [fieldCount]string{
		"my-app",
		"github.com/you/my-app",
		"./my-app",
	}

	for i := range m.inputs {
		t := textinput.New()
		t.Cursor.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("63"))
		t.Placeholder = placeholders[i]
		t.CharLimit = 120
		m.inputs[i] = t
	}

	m.inputs[fieldProject].Focus()
	return m
}

func (m model) Init() tea.Cmd {
	return textinput.Blink
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			m.status = statusCancelled
			return m, tea.Quit

		case "enter":
			// Validate current field before advancing.
			if err := m.validateCurrent(); err != "" {
				m.validErr = err
				return m, nil
			}
			m.validErr = ""

			// Auto-fill dependent defaults when advancing from project name.
			if m.focus == fieldProject {
				name := sanitize(m.currentValue())
				m.inputs[fieldProject].SetValue(name)
				if m.inputs[fieldModule].Value() == "" {
					m.inputs[fieldModule].SetValue("github.com/you/" + name)
				}
				if m.inputs[fieldOutput].Value() == "" {
					m.inputs[fieldOutput].SetValue(filepath.Join(".", name))
				}
			}

			if m.focus == fieldCount-1 {
				m.status = statusDone
				return m, tea.Quit
			}

			m.inputs[m.focus].Blur()
			m.focus++
			m.inputs[m.focus].Focus()
			return m, textinput.Blink
		}
	}

	var cmd tea.Cmd
	m.inputs[m.focus], cmd = m.inputs[m.focus].Update(msg)
	return m, cmd
}

func (m model) View() string {
	if m.status == statusCancelled {
		return cancelStyle.Render("\n  Cancelled.\n")
	}
	if m.status == statusDone {
		return m.doneView()
	}

	labels := [fieldCount]string{"Project name", "Go module path", "Output directory"}
	hints := [fieldCount]string{"lowercase, hyphens OK", "used in go.mod", "created if absent"}

	var b strings.Builder
	b.WriteString("\n")
	b.WriteString(titleStyle.Render("GoTH Stack Scaffolder") + "\n\n")

	for i, inp := range m.inputs {
		label := dimStyle.Render(labels[i])
		hint := dimStyle.Render("(" + hints[i] + ")")

		if i == m.focus {
			label = labelStyle.Render(labels[i])
			hint = activeStyle.Render("(" + hints[i] + ")")
		}

		b.WriteString(fmt.Sprintf(" %s %s\n", label, hint))

		arrow := dimStyle.Render("  ➤ ")
		if i == m.focus {
			arrow = arrowStyle.Render(" ➤ ")
		}
		b.WriteString(arrow + inp.View() + "\n\n")
	}

	if m.validErr != "" {
		b.WriteString(errorStyle.Render("✖  "+m.validErr) + "\n\n")
	}

	b.WriteString(dimStyle.Render("  enter → next   esc → quit") + "\n")
	return b.String()
}

func (m model) doneView() string {
	name := m.inputs[fieldProject].Value()
	module := m.inputs[fieldModule].Value()
	output := m.inputs[fieldOutput].Value()

	content := lipgloss.JoinVertical(lipgloss.Left,
		doneStyle.Render("✔  Ready to scaffold"),
		"",
		fmt.Sprintf("%s  %s", labelStyle.Render("project"), name),
		fmt.Sprintf("%s   %s", labelStyle.Render("module"), module),
		fmt.Sprintf("%s   %s", labelStyle.Render("output"), output),
	)
	return "\n" + summaryBox.Render(content) + "\n\n"
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func (m model) currentValue() string {
	return strings.TrimSpace(m.inputs[m.focus].Value())
}

func (m model) validateCurrent() string {
	v := m.currentValue()
	if v == "" {
		return "field cannot be empty"
	}
	if m.focus == fieldProject && strings.ContainsAny(v, " /\\") {
		return "project name must not contain spaces or slashes"
	}
	return ""
}

func sanitize(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	return strings.ReplaceAll(s, " ", "-")
}

// ── Public API ────────────────────────────────────────────────────────────────

// Gather runs the interactive TUI and returns a filled Config.
func Gather() (*config.Config, error) {
	m := newModel()
	final, err := tea.NewProgram(m).Run()
	if err != nil {
		return nil, fmt.Errorf("TUI error: %w", err)
	}

	result := final.(model)
	if result.status == statusCancelled {
		return nil, fmt.Errorf("cancelled")
	}

	return &config.Config{
		ProjectName: result.inputs[fieldProject].Value(),
		ModulePath:  result.inputs[fieldModule].Value(),
		OutputDir:   result.inputs[fieldOutput].Value(),
	}, nil
}
