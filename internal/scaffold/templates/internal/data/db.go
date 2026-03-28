package data

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/glebarez/go-sqlite"
)

var DB *sql.DB

// Open initialises the SQLite database pointed to by the DB_PATH env var.
// Call this once from main after loading your .env.
func Open() error {
	path := os.Getenv("DB_PATH")
	if path == "" {
		path = "./internal/data/database.db"
	}

	db, err := sql.Open("sqlite", path)
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}
	if err := db.Ping(); err != nil {
		return fmt.Errorf("ping db: %w", err)
	}

	DB = db
	log.Printf("database: connected (%s)", path)
	return migrate(db)
}

// migrate runs any one-time setup DDL.
func migrate(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS example (
			id    INTEGER PRIMARY KEY AUTOINCREMENT,
			name  TEXT    NOT NULL,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP
		);
	`)
	return err
}
