module github.com/opshub/checkout-api

go 1.22

require (
	github.com/gin-gonic/gin v1.10.0
	github.com/prometheus/client_golang v1.20.5
	go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.55.0
	go.opentelemetry.io/otel v1.31.0
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc v1.31.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.31.0
	go.opentelemetry.io/otel/exporters/prometheus v0.55.0
	go.opentelemetry.io/otel/sdk v1.31.0
	go.opentelemetry.io/otel/sdk/metric v1.31.0
	go.opentelemetry.io/otel/sdk/trace v1.31.0
	go.opentelemetry.io/otel/log v0.10.0
	go.opentelemetry.io/contrib/instrumentation/runtime v0.55.0
	github.com/oklog/run v1.1.0
	github.com/kelseyhightower/envconfig v1.4.0
	github.com/google/uuid v1.6.0
)
