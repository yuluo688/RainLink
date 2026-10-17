//go:build linux && !android

package linuxtun

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"os"
	"sync"
	"time"

	"golang.org/x/sys/unix"
	"rainlink.local/host/internal/linuxnet"
	"rainlink.local/host/internal/linuxprocess"
	"rainlink.local/host/internal/privatefs"
)

const (
	runtimeDirectory  = "/run/rainlink-tun"
	journalName       = "capture-recovery.json"
	journalLimit      = 4096
	journalVersion    = 2
	lockTimeout       = 250 * time.Millisecond
	operationTimeout  = 20 * time.Second
	tablePoolStart    = 0x524c0000 // Dedicated RainLink allocation pool ("RL").
	tablePoolSize     = 65536
	priorityPoolStart = 16000
	priorityPoolSize  = 1000
	priorityStride    = 16 // Keep the locked core's entire 11-priority block free.
)

var (
	// ErrOwned means a live guardian owns the global capture lease.
	ErrOwned = errors.New("another guardian owns the Linux TUN lease")
	// ErrCoreAlive refuses rule cleanup until the bound core has stopped.
	ErrCoreAlive = errors.New("Linux TUN core is still alive")
	// ErrPending retains recovery state after incomplete cleanup.
	ErrPending = errors.New("Linux TUN recovery remains incomplete")
	// ErrNamespace refuses to restore resources in a different namespace.
	ErrNamespace = errors.New("Linux TUN recovery namespace does not match")
)

type network interface {
	read(context.Context) (linuxnet.State, error)
	deleteRule(context.Context, linuxnet.Rule) (bool, error)
}

type kernelNetwork struct{}

func (kernelNetwork) read(ctx context.Context) (linuxnet.State, error) { return linuxnet.Read(ctx) }
func (kernelNetwork) deleteRule(ctx context.Context, rule linuxnet.Rule) (bool, error) {
	return linuxnet.DeleteExactRule(ctx, rule)
}

type journal struct {
	Version   int                    `json:"version"`
	Nonce     string                 `json:"nonce"`
	Namespace string                 `json:"namespace"`
	Owner     linuxprocess.Identity  `json:"owner"`
	Core      *linuxprocess.Identity `json:"core,omitempty"`
	Resources Specification          `json:"resources"`
	Checksum  string                 `json:"checksum"`
}

// Controller owns only the resource journal and recovery. A permission helper
// must separately authenticate the caller, validate configuration and own the
// core. Constructing a Controller does not enable capture or start a process.
type Controller struct {
	directory string
	network   network
}

// New is reserved for a root permission helper, never the ordinary GUI/host.
// The fixed /run parent must be root-controlled before privatefs creates state.
func New() (*Controller, error) {
	if os.Geteuid() != 0 {
		return nil, errors.New("Linux TUN resource controller requires its permission helper")
	}
	var parent unix.Stat_t
	if err := unix.Lstat("/run", &parent); err != nil || parent.Mode&unix.S_IFMT != unix.S_IFDIR || parent.Uid != 0 || parent.Mode&0022 != 0 {
		return nil, errors.New("Linux TUN runtime parent is not root-controlled")
	}
	return &Controller{directory: runtimeDirectory, network: kernelNetwork{}}, nil
}

func checksum(record journal) (string, error) {
	record.Checksum = ""
	data, err := json.Marshal(record)
	if err != nil {
		return "", err
	}
	value := sha256.Sum256(data)
	return hex.EncodeToString(value[:]), nil
}

func writeJournal(directory *privatefs.Directory, record *journal, exclusive bool) error {
	value, err := checksum(*record)
	if err != nil {
		return err
	}
	record.Checksum = value
	data, err := json.Marshal(record)
	if err != nil {
		return err
	}
	return directory.Write(journalName, data, exclusive)
}

func readJournal(directory *privatefs.Directory) (*journal, error) {
	data, err := directory.Read(journalName, journalLimit)
	if err != nil {
		return nil, err
	}
	var record journal
	if err = json.Unmarshal(data, &record); err != nil {
		return nil, errors.New("invalid TUN recovery journal")
	}
	canonical, err := json.Marshal(record)
	if err != nil || !bytes.Equal(bytes.TrimSpace(data), canonical) {
		return nil, errors.New("TUN recovery journal is not canonical")
	}
	computed, err := checksum(record)
	if err != nil || len(record.Checksum) != 64 || computed != record.Checksum || (record.Version != 1 && record.Version != journalVersion) ||
		len(record.Nonce) != 32 || !record.Owner.Valid() || !linuxprocess.ValidNamespace(record.Namespace) || record.Resources.validate() != nil {
		return nil, errors.New("invalid TUN recovery ownership or integrity")
	}
	if _, err = hex.DecodeString(record.Nonce); err != nil {
		return nil, errors.New("invalid TUN recovery nonce")
	}
	if record.Core != nil && (!record.Core.Valid() || record.Core.Boot != record.Owner.Boot || record.Core.PID == record.Owner.PID) {
		return nil, errors.New("invalid bound TUN core identity")
	}
	return &record, nil
}

func (c *Controller) lock(ctx context.Context) (*privatefs.Directory, func() error, error) {
	return c.lockState(ctx, false)
}

func (c *Controller) lockState(ctx context.Context, skipBusy bool) (*privatefs.Directory, func() error, error) {
	directory, err := privatefs.Open(c.directory)
	if err != nil {
		return nil, nil, err
	}
	lockCtx, cancel := context.WithTimeout(ctx, lockTimeout)
	defer cancel()
	unlock, err := directory.Lock(lockCtx, "capture.lock")
	if err != nil {
		closeErr := directory.Close()
		if errors.Is(err, context.DeadlineExceeded) && ctx.Err() == nil {
			if skipBusy {
				return nil, nil, closeErr
			}
			err = ErrOwned
		}
		return nil, nil, errors.Join(err, closeErr)
	}
	return directory, unlock, nil
}

func release(directory *privatefs.Directory, unlock func() error) error {
	return errors.Join(unlock(), directory.Close())
}

func chooseResources(state linuxnet.State, name string) (Specification, error) {
	for _, link := range state.Links {
		if link.Name == name {
			return Specification{}, errors.New("TUN interface name is already in use")
		}
	}
	usedTables := make(map[uint32]bool)
	usedPriorities := make(map[uint32]bool)
	for _, route := range state.Routes {
		usedTables[route.Table] = true
	}
	for _, rule := range state.Rules {
		usedTables[rule.Table] = true
		usedPriorities[rule.Priority] = true
		for _, attribute := range rule.Attributes {
			if attribute.Type&0x3fff == unix.FRA_GOTO {
				if attribute.Type != unix.FRA_GOTO || len(attribute.Value) != 4 {
					return Specification{}, errors.New("invalid policy goto reference")
				}
				// A new rule must not become another owner's unresolved target.
				usedPriorities[binary.NativeEndian.Uint32(attribute.Value)] = true
			}
		}
	}
	tableOffset, err := rand.Int(rand.Reader, big.NewInt(tablePoolSize))
	if err != nil {
		return Specification{}, err
	}
	priorityOffset, err := rand.Int(rand.Reader, big.NewInt(priorityPoolSize))
	if err != nil {
		return Specification{}, err
	}
	var specification Specification
	specification.Name = name
	for step := uint32(0); step < tablePoolSize; step++ {
		candidate := uint32(tablePoolStart) + (uint32(tableOffset.Uint64())+step)%tablePoolSize
		if !usedTables[candidate] {
			specification.Table = candidate
			break
		}
	}
	for step := uint32(0); step < priorityPoolSize; step++ {
		candidate := uint32(priorityPoolStart) + ((uint32(priorityOffset.Uint64())+step)%priorityPoolSize)*priorityStride
		free := true
		for offset := uint32(0); offset < RuleSpan; offset++ {
			free = free && !usedPriorities[candidate+offset]
		}
		if free {
			specification.Priority = candidate
			break
		}
	}
	if err = specification.validate(); err != nil {
		return Specification{}, errors.New("no free dedicated Linux TUN resources")
	}
	return specification, nil
}

// Lease holds the kernel-wide RainLink lock until Close. Close never discards a
// pending journal; callers must stop the core and Restore before normal close.
type Lease struct {
	mu         sync.Mutex
	controller *Controller
	directory  *privatefs.Directory
	unlock     func() error
	record     *journal
	closed     bool
	restored   bool
}

// Specification returns immutable resource identities for the core compiler.
func (lease *Lease) Specification() Specification { return lease.record.Resources }

// Acquire recovers an exited predecessor, reserves an unused table and complete
// priority block, and durably records intent before any core receives config.
func (c *Controller) Acquire(ctx context.Context, name string) (_ *Lease, result error) {
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	if err := (Specification{Name: name, Table: minimumTable, Priority: minimumPriority}).validate(); err != nil {
		return nil, err
	}
	directory, unlock, err := c.lock(ctx)
	if err != nil {
		return nil, err
	}
	keep := false
	defer func() {
		if !keep {
			result = errors.Join(result, release(directory, unlock))
		}
	}()
	if err = c.recoverLocked(ctx, directory); err != nil {
		return nil, err
	}
	state, err := c.network.read(ctx)
	if err != nil {
		return nil, err
	}
	specification, err := chooseResources(state, name)
	if err != nil {
		return nil, err
	}
	owner, alive, err := linuxprocess.ReadIdentity(os.Getpid())
	if err != nil || !alive {
		return nil, errors.Join(errors.New("TUN guardian identity unavailable"), err)
	}
	namespace, err := linuxprocess.NetworkNamespace(os.Getpid())
	if err != nil {
		return nil, err
	}
	var nonce [16]byte
	if _, err = rand.Read(nonce[:]); err != nil {
		return nil, err
	}
	record := &journal{Version: journalVersion, Nonce: hex.EncodeToString(nonce[:]), Namespace: namespace, Owner: owner, Resources: specification}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	if err = writeJournal(directory, record, true); err != nil {
		return nil, err
	}
	if err = ctx.Err(); err != nil {
		return nil, errors.Join(err, directory.Remove(journalName))
	}
	keep = true
	return &Lease{controller: c, directory: directory, unlock: unlock, record: record}, nil
}

// BindCore records a live child identity before its stdin is released. It does
// not authorize arbitrary PIDs or kill processes during recovery.
func (lease *Lease) BindCore(ctx context.Context, pid int) error {
	lease.mu.Lock()
	defer lease.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	if lease.closed || lease.restored || lease.record.Core != nil || pid == lease.record.Owner.PID {
		return errors.New("TUN lease cannot bind this core")
	}
	identity, alive, err := linuxprocess.ReadIdentity(pid)
	if err != nil || !alive || identity.Boot != lease.record.Owner.Boot {
		return errors.Join(errors.New("TUN core identity unavailable"), err)
	}
	namespace, err := linuxprocess.NetworkNamespace(pid)
	if err != nil || namespace != lease.record.Namespace {
		return errors.Join(ErrNamespace, err)
	}
	lease.record.Core = &identity
	return writeJournal(lease.directory, lease.record, false)
}

func (c *Controller) restoreRecord(ctx context.Context, directory *privatefs.Directory, record *journal) error {
	namespace, err := linuxprocess.NetworkNamespace(os.Getpid())
	if err != nil || namespace != record.Namespace {
		return errors.Join(ErrNamespace, err)
	}
	if record.Core != nil {
		alive, err := linuxprocess.Alive(*record.Core)
		if err != nil {
			return err
		}
		if alive {
			return ErrCoreAlive
		}
		state, err := c.network.read(ctx)
		if err != nil {
			return err
		}
		for _, link := range state.Links {
			if link.Name == record.Resources.Name {
				// Never delete a device merely because another owner reused its name.
				return errors.Join(ErrPending, errors.New("TUN interface name is still present"))
			}
		}
		expected, err := record.Resources.ExpectedRules()
		if record.Version == 1 {
			// Preserve recovery for pre-managed cores which created protocol-zero
			// rules. Never apply the new tag retroactively to an old journal.
			expected, err = record.Resources.expectedRules(0)
		}
		if err != nil {
			return err
		}
		for _, rule := range expected {
			if _, err = c.network.deleteRule(ctx, rule); err != nil {
				return fmt.Errorf("restore TUN policy: %w", err)
			}
		}
		state, err = c.network.read(ctx)
		if err != nil {
			return err
		}
		for _, current := range state.Rules {
			for _, rule := range expected {
				matches, err := linuxnet.SameRule(rule, current)
				if err != nil {
					return err
				}
				if matches {
					return ErrPending
				}
			}
		}
	}
	// A prepared record without a bound core never released a configuration.
	// Preserve all current network objects in that case, including new owners.
	if err := ctx.Err(); err != nil {
		return err
	}
	return directory.Remove(journalName)
}

func (c *Controller) recoverLocked(ctx context.Context, directory *privatefs.Directory) error {
	record, err := readJournal(directory)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	current, alive, err := linuxprocess.ReadIdentity(os.Getpid())
	if err != nil || !alive {
		return errors.Join(errors.New("recovery process identity unavailable"), err)
	}
	if current.Boot != record.Owner.Boot {
		// Reboot destroyed all old network objects. Never apply old identities
		// to unrelated resources that happen to use the same numbers now.
		return directory.Remove(journalName)
	}
	namespace, err := linuxprocess.NetworkNamespace(os.Getpid())
	if err != nil || namespace != record.Namespace {
		return errors.Join(ErrNamespace, err)
	}
	ownerAlive, err := linuxprocess.Alive(record.Owner)
	if err != nil {
		return err
	}
	if ownerAlive {
		return ErrOwned
	}
	return c.restoreRecord(ctx, directory, record)
}

// Recover handles an exited guardian only. A live owner, live core, incomplete
// kernel observation or uncertain deletion preserves the recovery journal.
func (c *Controller) Recover(ctx context.Context) (result error) {
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	directory, unlock, err := c.lock(ctx)
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, release(directory, unlock)) }()
	return c.recoverLocked(ctx, directory)
}

// RecoverAfterServiceExit is exclusively for systemd's per-connection exit
// hook. A different live session must retain its lease when an idle probe exits.
// skipped means another owner remains active, NOT that capture has stopped.
// Installation and user disconnect must continue using strict Recover/ConfirmIdle.
func (c *Controller) RecoverAfterServiceExit(ctx context.Context) (skipped bool, result error) {
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	directory, unlock, err := c.lockState(ctx, true)
	if err != nil {
		return false, err
	}
	if directory == nil {
		return true, nil
	}
	defer func() { result = errors.Join(result, release(directory, unlock)) }()
	err = c.recoverLocked(ctx, directory)
	if errors.Is(err, ErrOwned) {
		return true, nil
	}
	return false, err
}

// ConfirmIdle observes the same exclusive lock and durable recovery journal as
// capture. It never recovers a lease, stops a process or modifies network state.
// An absent device alone is insufficient: only completed recovery retires the
// journal. A live owner or a retained journal must not yield a successful stop.
func (c *Controller) ConfirmIdle(ctx context.Context) (result error) {
	directory, unlock, err := c.lock(ctx)
	if err != nil {
		return err
	}
	defer func() { result = errors.Join(result, release(directory, unlock)) }()
	_, err = readJournal(directory)
	if errors.Is(err, os.ErrNotExist) {
		return ctx.Err()
	}
	if err != nil {
		return err
	}
	return ErrPending
}

// Restore verifies the stopped core, removes only exact owned rules and reads
// the final state before retiring the journal. Repeated calls are safe.
func (lease *Lease) Restore(ctx context.Context) error {
	lease.mu.Lock()
	defer lease.mu.Unlock()
	if lease.closed {
		return errors.New("TUN lease is closed")
	}
	if lease.restored {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()
	record, err := readJournal(lease.directory)
	if err != nil {
		return err
	}
	if record.Nonce != lease.record.Nonce || record.Owner != lease.record.Owner || record.Resources != lease.record.Resources {
		return errors.New("TUN recovery ownership changed")
	}
	if err = lease.controller.restoreRecord(ctx, lease.directory, record); err != nil {
		return err
	}
	lease.restored = true
	return nil
}

// Close releases descriptors. It reports pending recovery and retains its
// journal if Restore has not succeeded; it never reports a successful cleanup.
func (lease *Lease) Close() error {
	lease.mu.Lock()
	defer lease.mu.Unlock()
	if lease.closed {
		return nil
	}
	lease.closed = true
	err := release(lease.directory, lease.unlock)
	if !lease.restored {
		return errors.Join(ErrPending, err)
	}
	return err
}
