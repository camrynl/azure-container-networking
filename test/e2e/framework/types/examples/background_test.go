package types

import (
	"fmt"
	"log"
	"sync"
	"testing"
	"time"

	"github.com/Azure/azure-container-networking/test/e2e/framework/types"
)

func TestFramework(t *testing.T) {
	job := types.NewJob("Validate that drop metrics are present in the prometheus endpoint")
	runner := types.NewRunner(t, job)
	defer runner.Run()

	job.AddStep(&TestBackground{
		CounterName: "Example Counter",
	}, &types.StepOptions{
		ExpectError:           false,
		RunInBackgroundWithID: "TestStep",
	})

	job.AddStep(&types.Sleep{
		Duration: 1 * time.Second,
	}, nil)

	job.AddStep(&types.Stop{
		BackgroundID: "TestStep",
	}, nil)
}

type TestBackground struct {
	CounterName string
	c           *counter
}

func (t *TestBackground) Run() error {
	t.c = newCounter()
	err := t.c.Start()
	if err != nil {
		return fmt.Errorf("failed to start counter: %w", err)
	}
	log.Println("running counter: " + t.CounterName)
	return nil
}

func (t *TestBackground) Stop() error {
	log.Println("stopping counter: " + t.CounterName)
	err := t.c.Stop()
	if err != nil {
		return fmt.Errorf("failed to stop counter: %w", err)
	}
	log.Println("count:", t.c.count)
	return nil
}

func (t *TestBackground) Prevalidate() error {
	return nil
}

type counter struct {
	ticker *time.Ticker
	count  int
	ch     chan struct{}
	wg     sync.WaitGroup
}

func newCounter() *counter {
	return &counter{
		ch: make(chan struct{}),
	}
}

func (c *counter) Start() error {
	c.ticker = time.NewTicker(1 * time.Millisecond)
	c.wg.Add(1)
	go func() {
		for {
			select {
			case <-c.ticker.C:
				c.count++
			case <-c.ch:
				c.wg.Done()
				return
			}
		}
	}()

	return nil
}

func (c *counter) Stop() error {
	close(c.ch)
	c.wg.Wait()
	return nil
}
