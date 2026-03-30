# gothstrap

> A scaffolding CLI for the **GOTH** stack: **G**o · **t**empl · **H**TMX · **T**ailwind

## Install

```bash
go install github.com/devdk/gothstrap@latest
```

Or build from source:

```bash
git clone https://github.com/devdk/gothstrap
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
├── .air.toml                       # Air live-reload config
├── .env.example                    # Environment variable template
├── .gitignore
├── .nvim/                          # Neovim project config
│   ├── database.lua
│   └── goth.lua
├── .nvim.lua                       # Neovim local config entry point
├── cmd/
│   └── server/
│       ├── main.go                 # HTTP server entry point & graceful shutdown
│       ├── routes.go               # Route definitions
│       ├── static_dev.go           # Static file serving (development)
│       └── static_prod.go          # Static file serving (production)
├── internal/
│   ├── data/
│   │   └── db.go                   # SQLite connection & helpers
│   ├── handlers/
│   │   └── handlers.go             # Route handlers & error helpers
│   ├── middleware/
│   │   └── middleware.go           # Logging, recovery, common headers
│   └── ui/
│       └── templates/
│           ├── base.templ          # Base HTML layout
│           ├── components/
│           │   ├── error.templ     # Error alert & full-page error
│           │   └── navbar.templ    # Navigation bar
│           └── pages/
│               └── index.templ    # Index page + HTMX ping fragment
├── static/
│   ├── css/
│   │   ├── input.css               # Tailwind source
│   │   └── output.css              # Generated — do not edit
│   └── js/
│       ├── alpine.min.js           # Alpine.js
│       └── htmx.min.js             # HTMX
├── go.mod
├── go.sum
├── Makefile
├── package.json                    # Tailwind CSS tooling
└── README.md
```

## Environment variables

Copy `.env.example` to `.env` and adjust for your environment:

| Variable  | Default (dev)                 | Description                                |
| --------- | ----------------------------- | ------------------------------------------ |
| `DB_PATH` | `./internal/data/database.db` | SQLite database path                       |
| `PORT`    | `3090`                        | HTTP listen port                           |
| `ENV`     | _(unset)_                     | Set to `production` to enable JSON logging |

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
