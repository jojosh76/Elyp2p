package main

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://postgres:postgres@localhost:5432/p2p_delivery?sslmode=disable"
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		panic(err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		panic(err)
	}
	_, err = db.Exec(`
		TRUNCATE TABLE
			otp_challenges,
			notifications,
			tracking_events,
			escrows,
			matches,
			package_verifications,
			kyc_verifications,
			delivery_requests,
			traveler_listings,
			payment_events
		RESTART IDENTITY CASCADE
	`)
	if err != nil {
		panic(err)
	}
	fmt.Println("DB wipe complete (users preserved)")
}
