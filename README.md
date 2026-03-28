# gothstrap

> A scaffolding CLI for the **GOTH** stack: **G**o · **t**empl · **H**TMX · **T**ailwind

## Install

```bash
go install github.com/medevdk/gothstrap@latest
```

Or build from source:

```bash
git clone https://github.com/medevdk/gothstrap
cd gothstrap
go build -o gothstrap .
```

## Usage

```bash
gothstrap
```

You'll be prompted for:

| Prompt           | Example                 |
| ---------------- | ----------------------- |
| Project name     | `my-app`                |
| Go module path   | `github.com/you/my-app` |
| Output directory | `./my-app`              |

## What gets generated

```
my-app/
├── cmd/server/main.go              # HTTP server entry point
├── internal/
│   ├── handlers/handlers.go        # Route handlers
│   └── views/
│       ├── layouts/base.templ      # Base HTML layout
│       └── pages/index.templ       # Index page + HTMX fragment
├── static/
│   ├── css/input.css               # Tailwind source
│   └── js/                         # HTMX downloaded here by make setup
├── go.mod
├── Makefile
├── .gitignore
├── .env.example
└── README.md
```

## Adding your own templates

Drop any file under `internal/scaffold/templates/`. Files ending in `.tmpl`
are processed as Go `text/template` with the following variables available:

| Variable           | Example                 |
| ------------------ | ----------------------- |
| `{{.ProjectName}}` | `my-app`                |
| `{{.ModulePath}}`  | `github.com/you/my-app` |
| `{{.OutputDir}}`   | `./my-app`              |

All other files are copied verbatim — including `.templ` files, which use
their own `{ }` syntax that would clash with Go's template engine.
