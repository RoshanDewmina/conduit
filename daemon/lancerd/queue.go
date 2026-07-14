package main

import (
	"encoding/json"
	"os"
	"sync"
)

// queueFile is persisted at ~/.lancer/queue.json (mode 0600).
type queueFile struct {
	Pending []ApprovalEvent `json:"pending"`
}

// diskQueue is the durable mirror of unresolved approvals. Delivery does not
// remove an event; only successful resolution or no-client retirement does.
type diskQueue struct {
	mu   sync.Mutex
	path string
}

func newDiskQueue(path string) *diskQueue {
	return &diskQueue{path: path}
}

func (q *diskQueue) readAll() ([]ApprovalEvent, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.readAllLocked()
}

func (q *diskQueue) readAllLocked() ([]ApprovalEvent, error) {
	data, err := os.ReadFile(q.path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var file queueFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, err
	}
	return file.Pending, nil
}

func (q *diskQueue) replace(events []ApprovalEvent) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	file := queueFile{Pending: events}
	data, err := json.Marshal(file)
	if err != nil {
		return err
	}
	return os.WriteFile(q.path, data, 0600)
}

func (q *diskQueue) add(event ApprovalEvent) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	events, err := q.readAllLocked()
	if err != nil {
		return err
	}
	for _, e := range events {
		if e.ApprovalID == event.ApprovalID {
			return nil
		}
	}
	events = append(events, event)
	file := queueFile{Pending: events}
	data, err := json.Marshal(file)
	if err != nil {
		return err
	}
	return os.WriteFile(q.path, data, 0600)
}

func (q *diskQueue) remove(id string) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	events, err := q.readAllLocked()
	if err != nil {
		return err
	}
	out := events[:0]
	for _, e := range events {
		if e.ApprovalID != id {
			out = append(out, e)
		}
	}
	file := queueFile{Pending: out}
	data, err := json.Marshal(file)
	if err != nil {
		return err
	}
	return os.WriteFile(q.path, data, 0600)
}
