package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/diaryai/server/internal/ai"
	"github.com/diaryai/server/internal/auth"
	"github.com/diaryai/server/internal/config"
	"github.com/diaryai/server/internal/db"
	"github.com/diaryai/server/internal/httpx"
	syncsvc "github.com/diaryai/server/internal/sync"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		slog.Error("load config", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := db.New(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("connect db", "err", err)
		os.Exit(1)
	}
	defer pool.Close()
	slog.Info("connected to database")

	authSvc := auth.New(pool, cfg.JWTSecret, cfg.JWTTTL)
	syncSvc := syncsvc.New(pool)
	syncCatSvc := syncsvc.NewFor(pool, "categories", "categories")
	aiSvc := ai.New(pool, cfg.OpenRouterAPIKey)

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger) // лог входящих запросов
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(60 * time.Second))

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	r.Route("/auth", func(r chi.Router) {
		authSvc.Routes(r)
	})

	r.Group(func(r chi.Router) {
		r.Use(auth.Middleware(cfg.JWTSecret))
		r.Route("/sync", func(r chi.Router) {
			// /sync/push, /sync/pull — записи (старый API, v1.0 совместимость)
			syncSvc.Routes(r)
			// /sync/categories/push, /sync/categories/pull — категории (новый)
			r.Route("/categories", func(r chi.Router) {
				syncCatSvc.Routes(r)
			})
		})
		r.Route("/ai", func(r chi.Router) {
			aiSvc.Routes(r)
		})
	})

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		slog.Info("http server starting", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("http server", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}
