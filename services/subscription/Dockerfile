FROM golang:1.27.0-alpine3.23@sha256:3747dcba41c8b0db3211fda4db61638b980e17ac5bb3c94460a975a9cfe19395 AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/subscription/ ./cmd/subscription/
COPY internal/contracts/ ./internal/contracts/
COPY internal/subscription/ ./internal/subscription/
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/subscription ./cmd/subscription

FROM scratch
COPY --from=builder /out/subscription /subscription
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/subscription"]
