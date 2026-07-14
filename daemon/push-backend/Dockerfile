FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o push-backend .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates && \
    addgroup -S lancer && adduser -S -G lancer lancer
WORKDIR /app
COPY --from=builder /app/push-backend .
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh && chown lancer:lancer /app/push-backend /app/docker-entrypoint.sh
USER lancer
EXPOSE 8080
ENTRYPOINT ["/app/docker-entrypoint.sh"]
