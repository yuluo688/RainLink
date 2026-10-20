//go:build linux && !android

// Package linuxmanage provides the ordinary user's private service-management
// channel. It accepts fixed actions only, never a path, command or configuration.
package linuxmanage

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"time"

	"rainlink.local/host/internal/linuxinstall"
	"rainlink.local/host/internal/linuxipc"
)

const managementTimeout = 8 * time.Minute

type failure struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (f *failure) Error() string { return f.Message }

type request struct {
	ID     int    `json:"id"`
	Method string `json:"method"`
}

type reply struct {
	ID     int      `json:"id"`
	Result any      `json:"result,omitempty"`
	Error  *failure `json:"error,omitempty"`
}

type backend interface {
	inspect(context.Context) linuxinstall.ServiceStatus
	change(context.Context, string) error
}

type systemBackend struct{}

func (systemBackend) inspect(ctx context.Context) linuxinstall.ServiceStatus {
	return linuxinstall.InspectService(ctx)
}

func parseRequest(raw []byte) (request, error) {
	var value request
	if linuxipc.ValidateJSON(raw) != nil {
		return value, errors.New("invalid service-management request")
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || len(fields) < 2 || len(fields) > 3 {
		return value, errors.New("invalid service-management envelope")
	}
	for name, data := range fields {
		switch name {
		case "id":
			if json.Unmarshal(data, &value.ID) != nil || value.ID < 1 || value.ID > 0x7fffffff {
				return request{}, errors.New("invalid management identifier")
			}
		case "method":
			if json.Unmarshal(data, &value.Method) != nil {
				return request{}, errors.New("invalid management method")
			}
		case "payload":
			var payload map[string]json.RawMessage
			if json.Unmarshal(data, &payload) != nil || payload == nil || len(payload) != 0 {
				return request{}, errors.New("management methods do not accept payloads")
			}
		default:
			return request{}, errors.New("unknown management field")
		}
	}
	if value.ID == 0 {
		return request{}, errors.New("missing management identifier")
	}
	switch value.Method {
	case "status", "install", "uninstall", "recover", "cancel":
		return value, nil
	default:
		return request{}, errors.New("unsupported management method")
	}
}

// Serve runs independently of the network session. EOF cancels authorization or
// installation and waits for the elevated worker's bounded rollback and exit.
func Serve(parent context.Context, input io.Reader, output io.Writer) error {
	if err := dropBrokerCapabilities(); err != nil {
		return err
	}
	return serve(parent, input, output, systemBackend{})
}

func serve(parent context.Context, input io.Reader, output io.Writer, service backend) (result error) {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	commands := make(chan request)
	readErr := make(chan error, 1)
	go func() {
		defer close(commands)
		defer cancel()
		scanner := bufio.NewScanner(input)
		scanner.Buffer(make([]byte, 1024), 4096)
		previous := 0
		for scanner.Scan() {
			command, err := parseRequest(scanner.Bytes())
			if err != nil || command.ID <= previous {
				readErr <- errors.New("invalid service-management sequence")
				return
			}
			previous = command.ID
			select {
			case commands <- command:
			case <-ctx.Done():
				return
			}
		}
		if err := scanner.Err(); err != nil {
			readErr <- err
		}
	}()
	encoder := json.NewEncoder(output)
	var running context.CancelFunc
	var completed <-chan reply
	defer func() {
		if running != nil {
			running()
			response := <-completed
			if response.Error != nil {
				result = errors.Join(result, response.Error)
			}
		}
	}()
	for {
		select {
		case <-ctx.Done():
			select {
			case err := <-readErr:
				return err
			default:
				return nil
			}
		case result := <-completed:
			running()
			running, completed = nil, nil
			if err := encoder.Encode(result); err != nil {
				return err
			}
		case command, ok := <-commands:
			if !ok {
				continue
			}
			result := reply{ID: command.ID}
			switch {
			case command.Method == "cancel":
				if running != nil {
					running()
				}
				// This only acknowledges the request. The original operation still
				// has to return; it cannot be replaced with a synthetic success.
				result.Result = map[string]bool{"requested": true}
			case running != nil:
				result.Error = &failure{"service_busy", "服务管理操作尚未完成"}
			case command.Method == "status":
				inspection, stop := context.WithTimeout(ctx, 15*time.Second)
				result.Result = service.inspect(inspection)
				stop()
			default:
				operation, stop := context.WithTimeout(ctx, managementTimeout)
				running = stop
				done := make(chan reply, 1)
				completed = done
				go func() {
					response := reply{ID: command.ID}
					err := service.change(operation, command.Method)
					if err != nil {
						if !errors.As(err, &response.Error) {
							response.Error = &failure{"service_operation_failed", "服务管理未完成，请重新检查或恢复安装"}
						}
					} else {
						response.Result = map[string]bool{"completed": true}
					}
					done <- response
				}()
				continue
			}
			if err := encoder.Encode(result); err != nil {
				return err
			}
		}
	}
}
