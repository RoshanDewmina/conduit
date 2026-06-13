FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o push-backend .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates && \
    addgroup -S conduit && adduser -S -G conduit conduit
WORKDIR /app
COPY --from=builder /app/push-backend .
RUN chown conduit:conduit /app/push-backend
USER conduit
EXPOSE 8080
ENTRYPOINT ["./push-backend"]
