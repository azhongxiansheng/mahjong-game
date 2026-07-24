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
	"github.com/lov-team/mahjong-game/services/control-plane/internal/queue"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	tokenSvc, err := tokens.NewService(tokens.Options{
		Secret: cfg.TokenSigningSecret,
	})
	if err != nil {
		log.Fatalf("tokens: %v", err)
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

	queueSvc, err := queue.NewService(queue.Options{
		Redis: redisClient.Redis(),
	})
	if err != nil {
		log.Fatalf("queue: %v", err)
	}

	matcher, err := queue.NewMatcher(queue.MatcherOptions{
		Service:        queueSvc,
		TokenIssuer:    tokenSvc,
		WorkerEndpoint: cfg.WorkerEndpoint,
		OnError: func(op string, safeDetail string) {
			// 仅记录稳定操作类别与固定安全文案；不得输出原始 err/密钥/token。
			log.Printf("matcher error op=%s detail=%s", op, safeDetail)
		},
	})
	if err != nil {
		log.Fatalf("matcher: %v", err)
	}
	matcher.Start()
	defer func() {
		stopCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := matcher.Stop(stopCtx); err != nil {
			log.Printf("matcher stop: %v", err)
		}
	}()

	srv := httpserver.New(httpserver.Config{
		Addr:         cfg.HTTPAddr,
		Pinger:       redisClient,
		TokenService: tokenSvc,
		CasualQueue:  queueSvc,
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
