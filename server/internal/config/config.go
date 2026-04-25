package config

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	HTTPAddr    string
	DatabaseURL string
	JWTSecret   []byte
	JWTTTL      time.Duration

	OpenRouterAPIKey string
	GroqAPIKey       string
}

func Load() (*Config, error) {
	_ = godotenv.Load()

	addr := getenv("DIARY_HTTP_ADDR", ":8080")
	dbURL := os.Getenv("DIARY_DATABASE_URL")
	if dbURL == "" {
		return nil, fmt.Errorf("DIARY_DATABASE_URL is required")
	}

	secret := os.Getenv("DIARY_JWT_SECRET")
	if len(secret) < 16 {
		return nil, fmt.Errorf("DIARY_JWT_SECRET must be at least 16 characters")
	}

	ttlHours, err := strconv.Atoi(getenv("DIARY_JWT_TTL_HOURS", "720"))
	if err != nil {
		return nil, fmt.Errorf("invalid DIARY_JWT_TTL_HOURS: %w", err)
	}

	return &Config{
		HTTPAddr:         addr,
		DatabaseURL:      dbURL,
		JWTSecret:        []byte(secret),
		JWTTTL:           time.Duration(ttlHours) * time.Hour,
		OpenRouterAPIKey: os.Getenv("OPENROUTER_API_KEY"),
		GroqAPIKey:       os.Getenv("GROQ_API_KEY"),
	}, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
