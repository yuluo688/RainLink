package securestore

import (
	"bytes"
	"errors"
)

type boundedOutput struct {
	buffer   bytes.Buffer
	limit    int
	overflow bool
}

func (b *boundedOutput) Write(data []byte) (int, error) {
	if len(data) > b.limit-b.buffer.Len() {
		b.overflow = true
		return 0, errors.New("key service output exceeds limit")
	}
	return b.buffer.Write(data)
}
