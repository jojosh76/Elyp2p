FROM golang:1.24-alpine AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/api ./cmd/api

FROM alpine:3.20
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
USER app

COPY --from=builder /out/api /app/api
COPY migrations /app/migrations

EXPOSE 8080
ENTRYPOINT ["/app/api"]
