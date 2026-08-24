package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/subscription"
)

func main() {
	logger := log.New(os.Stdout, "", 0)
	config, err := subscription.LoadConfig(os.Getenv)
	if err != nil {
		logger.Fatalf("configuration rejected: %v", err)
	}

	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", config.Port),
		Handler:           subscription.NewServer(config, logger),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	stopped := make(chan os.Signal, 1)
	signal.Notify(stopped, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stopped
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()

	logger.Printf("subscription listening on port %d", config.Port)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Fatalf("server stopped unexpectedly")
	}
}
