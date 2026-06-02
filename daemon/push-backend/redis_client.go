package main

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"net/url"
	"strings"
	"time"
)

type redisConn struct {
	conn net.Conn
	r    *bufio.Reader
}

func dialRedis(ctx context.Context, redisURL string) (*redisConn, error) {
	u, err := url.Parse(redisURL)
	if err != nil {
		return nil, fmt.Errorf("parse redis url: %w", err)
	}
	addr := u.Host
	if !strings.Contains(addr, ":") {
		addr += ":6379"
	}
	dialer := net.Dialer{Timeout: 3 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}
	rc := &redisConn{conn: conn, r: bufio.NewReader(conn)}
	if u.User != nil {
		password, _ := u.User.Password()
		if password != "" {
			if err := rc.auth(password); err != nil {
				conn.Close()
				return nil, err
			}
		}
	}
	return rc, nil
}

func (c *redisConn) Close() error {
	return c.conn.Close()
}

func (c *redisConn) Ping(ctx context.Context) error {
	_, err := c.do(ctx, "PING")
	return err
}

func (c *redisConn) Get(ctx context.Context, key string) (string, error) {
	reply, err := c.do(ctx, "GET", key)
	if err != nil {
		return "", err
	}
	if reply == nil {
		return "", nil
	}
	s, ok := reply.(string)
	if !ok {
		return "", fmt.Errorf("unexpected GET reply type")
	}
	return s, nil
}

func (c *redisConn) Set(ctx context.Context, key, value string) error {
	_, err := c.do(ctx, "SET", key, value)
	return err
}

func (c *redisConn) auth(password string) error {
	_, err := c.do(context.Background(), "AUTH", password)
	return err
}

func (c *redisConn) do(ctx context.Context, args ...string) (any, error) {
	if err := c.writeCommand(args...); err != nil {
		return nil, err
	}
	return c.readReply()
}

func (c *redisConn) writeCommand(args ...string) error {
	var b strings.Builder
	b.WriteString("*")
	b.WriteString(fmt.Sprintf("%d\r\n", len(args)))
	for _, arg := range args {
		b.WriteString("$")
		b.WriteString(fmt.Sprintf("%d\r\n", len(arg)))
		b.WriteString(arg)
		b.WriteString("\r\n")
	}
	_, err := c.conn.Write([]byte(b.String()))
	return err
}

func (c *redisConn) readReply() (any, error) {
	line, err := c.r.ReadString('\n')
	if err != nil {
		return nil, err
	}
	line = strings.TrimSpace(line)
	if len(line) == 0 {
		return nil, fmt.Errorf("empty redis reply")
	}
	switch line[0] {
	case '+':
		if line == "+OK" || strings.HasPrefix(line, "+PONG") {
			return "OK", nil
		}
		return line[1:], nil
	case '-':
		return nil, fmt.Errorf("redis error: %s", line[1:])
	case ':':
		return line[1:], nil
	case '$':
		if line == "$-1" {
			return nil, nil
		}
		var n int
		if _, err := fmt.Sscanf(line, "$%d", &n); err != nil {
			return nil, err
		}
		buf := make([]byte, n+2)
		if _, err := c.r.Read(buf); err != nil {
			return nil, err
		}
		return string(buf[:n]), nil
	default:
		return nil, fmt.Errorf("unsupported redis reply: %q", line)
	}
}
