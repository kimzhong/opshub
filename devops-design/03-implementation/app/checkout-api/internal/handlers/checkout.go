// checkout-api 业务 handler
// 演示核心 SRE 关注点：metrics、tracing、错误处理
package handlers

import (
	"context"
	"fmt"
	"math/rand"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
)

type Config struct {
	FailureRate   float64
	LatencyMs     int
	DownstreamURL string
}

type Handler struct {
	cfg            Config
	requestCounter metric.Int64Counter
	latencyHist    metric.Float64Histogram
	errorCounter   metric.Int64Counter
	inFlightGauge  metric.Int64UpDownCounter
}

func New(cfg Config) *Handler {
	meter := otel.Meter("checkout-api")

	requestCounter, _ := meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("Total HTTP requests"),
	)
	latencyHist, _ := meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("HTTP request latency"),
		metric.WithUnit("s"),
		metric.WithExplicitBucketBoundaries(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
	)
	errorCounter, _ := meter.Int64Counter(
		"http_errors_total",
		metric.WithDescription("Total HTTP errors (5xx)"),
	)
	inFlightGauge, _ := meter.Int64UpDownCounter(
		"http_requests_in_flight",
		metric.WithDescription("In-flight HTTP requests"),
	)

	return &Handler{
		cfg:            cfg,
		requestCounter: requestCounter,
		latencyHist:    latencyHist,
		errorCounter:   errorCounter,
		inFlightGauge:  inFlightGauge,
	}
}

// Index 根路径
func (h *Handler) Index(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"service": "checkout-api",
		"status":  "ok",
		"endpoints": []string{
			"GET /healthz",
			"GET /readyz",
			"GET /checkout/:orderId",
			"POST /checkout",
		},
	})
}

// Healthz liveness probe
// 失败时 K8s 会重启 pod
func (h *Handler) Healthz(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "alive"})
}

// Readyz readiness probe
// 失败时 K8s 会从 service endpoints 移除
func (h *Handler) Readyz(c *gin.Context) {
	// 实际场景可以检查下游依赖
	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}

// Checkout 查询订单
// 业务接口：模拟 80% 是 P99 < 800ms 的核心路径
func (h *Handler) Checkout(c *gin.Context) {
	start := time.Now()
	h.inFlightGauge.Add(c.Request.Context(), 1)
	defer h.inFlightGauge.Add(c.Request.Context(), -1)

	orderID := c.Param("orderId")
	ctx, span := otel.Tracer("checkout-api").Start(c.Request.Context(), "Checkout")
	defer span.End()

	span.SetAttributes(
		attribute.String("order.id", orderID),
		attribute.String("http.method", c.Request.Method),
	)

	// 模拟业务处理延迟
	if h.cfg.LatencyMs > 0 {
		time.Sleep(time.Duration(h.cfg.LatencyMs) * time.Millisecond)
	}

	// 模拟错误率（用于演示 SLO burn rate 告警）
	if h.cfg.FailureRate > 0 && rand.Float64() < h.cfg.FailureRate {
		span.RecordError(fmt.Errorf("simulated error for order %s", orderID))
		span.SetStatus(codes.Error, "simulated error")
		h.errorCounter.Add(ctx, 1, metric.WithAttributes(
			attribute.String("endpoint", "/checkout"),
			attribute.String("error.type", "simulated"),
		))
		h.recordMetrics(c, start, "500")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}

	// 模拟下游调用
	if h.cfg.DownstreamURL != "" {
		h.callDownstream(ctx)
	}

	result := gin.H{
		"orderId":  orderID,
		"status":   "confirmed",
		"trace_id": span.SpanContext().TraceID().String(),
		"amount":   99.99,
	}

	h.recordMetrics(c, start, "200")
	c.JSON(http.StatusOK, result)
}

// CreateCheckout 创建订单
func (h *Handler) CreateCheckout(c *gin.Context) {
	start := time.Now()
	h.inFlightGauge.Add(c.Request.Context(), 1)
	defer h.inFlightGauge.Add(c.Request.Context(), -1)

	var req struct {
		UserID string   `json:"user_id"`
		Items  []string `json:"items"`
		Amount float64  `json:"amount"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		h.errorCounter.Add(c.Request.Context(), 1, metric.WithAttributes(
			attribute.String("error.type", "bad_request"),
		))
		h.recordMetrics(c, start, "400")
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.UserID == "" {
		req.UserID = uuid.NewString()
	}

	orderID := uuid.NewString()
	c.JSON(http.StatusCreated, gin.H{
		"orderId": orderID,
		"user_id": req.UserID,
		"status":  "pending",
		"amount":  req.Amount,
	})
	h.recordMetrics(c, start, "201")
}

func (h *Handler) callDownstream(ctx context.Context) {
	_, span := otel.Tracer("checkout-api").Start(ctx, "call-downstream")
	defer span.End()
	// 模拟下游调用
	time.Sleep(20 * time.Millisecond)
	span.SetAttributes(attribute.String("downstream", h.cfg.DownstreamURL))
}

func (h *Handler) recordMetrics(c *gin.Context, start time.Time, status string) {
	duration := time.Since(start).Seconds()
	code, _ := strconv.Atoi(status)
	ctx := c.Request.Context()

	attrs := metric.WithAttributes(
		attribute.String("method", c.Request.Method),
		attribute.String("endpoint", c.FullPath()),
		attribute.String("status", status),
		attribute.Int("http.status_code", code),
	)

	h.requestCounter.Add(ctx, 1, attrs)
	h.latencyHist.Record(ctx, duration, metric.WithAttributes(
		attribute.String("endpoint", c.FullPath()),
	))
}
