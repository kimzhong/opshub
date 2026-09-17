// checkout-api 主入口
// 演示用途：作为 OpsHub 平台的端到端走通用例
// 覆盖：OTel 埋点 + Prometheus metrics + 健康检查 + 业务逻辑
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

	"github.com/gin-gonic/gin"
	"github.com/oklog/run"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/contrib/instrumentation/runtime"

	"github.com/opshub/checkout-api/internal/handlers"
	"github.com/opshub/checkout-api/internal/observability"
)

type config struct {
	// 服务配置
	ServiceName    string `envconfig:"SERVICE_NAME" default:"checkout-api"`
	ServiceVersion string `envconfig:"SERVICE_VERSION" default:"v0.1.0"`
	Environment    string `envconfig:"ENVIRONMENT" default:"dev"`
	Port           int    `envconfig:"PORT" default:"8080"`
	MetricsPort    int    `envconfig:"METRICS_PORT" default:"9090"`

	// 业务配置
	FailureRate   float64 `envconfig:"FAILURE_RATE" default:"0.0"` // 0.0-1.0 模拟错误率
	LatencyMs     int     `envconfig:"LATENCY_MS" default:"0"`     // 模拟延迟（ms）
	DownstreamURL string  `envconfig:"DOWNSTREAM_URL" default:""`  // 模拟调用下游

	// OTel 配置
	OTLPEndpoint string  `envconfig:"OTEL_EXPORTER_OTLP_ENDPOINT" default:"otel-collector.observability:4317"`
	OTELInsecure bool    `envconfig:"OTEL_EXPORTER_OTLP_INSECURE" default:"true"`
	SampleRatio  float64 `envconfig:"OTEL_TRACES_SAMPLER_ARG" default:"1.0"`
}

func main() {
	var cfg config
	if err := envconfig.Process("", &cfg); err != nil {
		log.Fatalf("config error: %v", err)
	}

	log.Printf("starting %s %s (env=%s)", cfg.ServiceName, cfg.ServiceVersion, cfg.Environment)

	// 1. 初始化 OpenTelemetry
	otelShutdown, err := observability.InitOTel(context.Background(), observability.OTelConfig{
		ServiceName:    cfg.ServiceName,
		ServiceVersion: cfg.ServiceVersion,
		Environment:    cfg.Environment,
		OTLPEndpoint:   cfg.OTLPEndpoint,
		Insecure:       cfg.OTELInsecure,
		SampleRatio:    cfg.SampleRatio,
	})
	if err != nil {
		log.Fatalf("init otel: %v", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := otelShutdown(shutdownCtx); err != nil {
			log.Printf("otel shutdown: %v", err)
		}
	}()

	// 2. 运行时指标（Go runtime metrics）
	if err := runtime.Start(runtime.WithMeterProvider(observability.MeterProvider())); err != nil {
		log.Printf("runtime metrics: %v", err)
	}

	// 3. 业务 handler
	h := handlers.New(handlers.Config{
		FailureRate:   cfg.FailureRate,
		LatencyMs:     cfg.LatencyMs,
		DownstreamURL: cfg.DownstreamURL,
	})

	// 4. Gin router
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(otelgin.Middleware(cfg.ServiceName)) // 自动 trace 每个请求

	// 业务路由
	r.GET("/healthz", h.Healthz) // liveness
	r.GET("/readyz", h.Readyz)   // readiness
	r.GET("/checkout/:orderId", h.Checkout)
	r.POST("/checkout", h.CreateCheckout)
	r.GET("/", h.Index)

	// 5. run group 管理多个 goroutine
	var g run.Group
	{
		// HTTP 业务服务
		g.Add(func() error {
			srv := &http.Server{
				Addr:              fmt.Sprintf(":%d", cfg.Port),
				Handler:           r,
				ReadHeaderTimeout: 5 * time.Second,
			}
			log.Printf("HTTP listening on :%d", cfg.Port)
			return srv.ListenAndServe()
		}, func(error) {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = shutdown(ctx, srv)
		})
	}
	{
		// Prometheus metrics 端口
		g.Add(func() error {
			mux := http.NewServeMux()
			mux.Handle("/metrics", promhttp.Handler())
			srv := &http.Server{Addr: fmt.Sprintf(":%d", cfg.MetricsPort), Handler: mux}
			log.Printf("metrics listening on :%d", cfg.MetricsPort)
			return srv.ListenAndServe()
		}, func(error) {})
	}
	{
		// 信号处理
		g.Add(func() error {
			sigCh := make(chan os.Signal, 1)
			signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
			s := <-sigCh
			return fmt.Errorf("received signal %v", s)
		}, func(error) {})
	}

	if err := g.Run(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server: %v", err)
	}
	log.Print("shutdown complete")
}

func shutdown(ctx context.Context, srv *http.Server) error {
	return srv.Shutdown(ctx)
}
