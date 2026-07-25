package workers

import (
	"context"
	"sync"
	"time"
)

// ReaperErrorFunc 后台安全错误回调（不得传入 token/secret）。
type ReaperErrorFunc func(op string, safeDetail string)

// ReaperOptions 构造失联回收器。
type ReaperOptions struct {
	Registry *Registry
	Interval time.Duration
	OnError  ReaperErrorFunc
}

// Reaper 周期性扫描租约过期 Worker 并失败关联未结束房间。
type Reaper struct {
	reg      *Registry
	interval time.Duration
	onError  ReaperErrorFunc

	startOnce sync.Once
	stopOnce  sync.Once
	stopCh    chan struct{}
	doneCh    chan struct{}
}

// NewReaper 创建回收器。
func NewReaper(opts ReaperOptions) (*Reaper, error) {
	if opts.Registry == nil {
		return nil, errRegistryRequired
	}
	interval := opts.Interval
	if interval <= 0 {
		interval = DefaultReapInterval
	}
	return &Reaper{
		reg:      opts.Registry,
		interval: interval,
		onError:  opts.OnError,
		stopCh:   make(chan struct{}),
		doneCh:   make(chan struct{}),
	}, nil
}

var errRegistryRequired = errString("workers registry required")

type errString string

func (e errString) Error() string { return string(e) }

// Start 启动后台回收；重复调用安全。
func (p *Reaper) Start() {
	p.startOnce.Do(func() {
		go p.loop()
	})
}

// Stop 停止后台回收并等待退出。
func (p *Reaper) Stop(ctx context.Context) error {
	p.startOnce.Do(func() {
		close(p.doneCh)
	})
	p.stopOnce.Do(func() {
		close(p.stopCh)
	})
	select {
	case <-p.doneCh:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (p *Reaper) loop() {
	defer close(p.doneCh)
	ticker := time.NewTicker(p.interval)
	defer ticker.Stop()
	p.tick()
	for {
		select {
		case <-p.stopCh:
			return
		case <-ticker.C:
			p.tick()
		}
	}
}

func (p *Reaper) tick() {
	if _, err := p.reg.ReapExpired(context.Background()); err != nil {
		if p.onError != nil {
			p.onError("worker_reap", "operation failed")
		}
	}
}
