package redisx

import (
	"context"

	"github.com/redis/go-redis/v9"
)

// Options 描述真实 Redis 连接参数。
type Options struct {
	Addr     string
	Password string
	DB       int
}

// Client 封装 go-redis，提供 Ping/Close 与底层访问（队列等真实 Redis 语义）。
type Client struct {
	rdb *redis.Client
}

// New 创建 Redis 客户端（惰性连接；以 Ping 验证可用性）。
func New(opts Options) (*Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     opts.Addr,
		Password: opts.Password,
		DB:       opts.DB,
	})
	return &Client{rdb: rdb}, nil
}

// Redis 返回底层 go-redis 客户端（队列/票据等真实命令）。
func (c *Client) Redis() *redis.Client {
	return c.rdb
}

// Ping 对真实 Redis 执行 PING。
func (c *Client) Ping(ctx context.Context) error {
	return c.rdb.Ping(ctx).Err()
}

// Close 关闭底层连接池。
func (c *Client) Close() error {
	return c.rdb.Close()
}
