package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/config"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/httpserver"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	redisClient, err := redisx.New(redisx.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
		DB:       cfg.RedisDB,
	})
	if err != nil {
		log.Fatalf("redis: %v", err)
	}
	defer func() {
		if err := redisClient.Close(); err != nil {
			log.Printf("redis close: %v", err)
		}
	}()

	srv := httpserver.New(httpserver.Config{
		Addr:   cfg.HTTPAddr,
		Pinger: redisClient,
	})

	errCh := make(chan error, 1)
	go func() {
		log.Printf("control-plane listening on %s (redis=%s)", cfg.HTTPAddr, cfg.RedisAddr)
		errCh <- srv.ListenAndServe()
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("signal %v, shutting down", sig)
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("shutdown: %v", err)
	}
	if err := <-errCh; err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve exit: %v", err)
	}
	log.Printf("control-plane stopped")
}
