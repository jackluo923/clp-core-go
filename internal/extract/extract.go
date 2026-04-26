package extract

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

const dirPrefix = "clp-core-go-"

// Extractor extracts an embedded tar.gz to a unique per-process temp directory.
//
// # Automatic cleanup strategy
//
// Go provides no atexit() equivalent: os.Exit() issues a raw exit_group
// syscall that bypasses the C runtime on Linux, so CGO atexit() hooks do not
// fire. A signal handler covers SIGINT, SIGTERM, and SIGQUIT (immediate
// removal). Dirs left by crashes or SIGKILL are not cleaned up automatically.
type Extractor struct {
	data        []byte
	prepareOnce sync.Once
	prepareErr  error
	mu          sync.RWMutex
	extractDir  string
}

// New creates an Extractor for the given tar.gz data.
func New(data []byte) *Extractor {
	return &Extractor{data: data}
}

// Prepare extracts the tar.gz to a uniquely named temp directory.
func (e *Extractor) Prepare() error {
	e.prepareOnce.Do(func() {
		timestamp := time.Now().UTC().Format("20060102-150405")
		dir, err := os.MkdirTemp("", dirPrefix+timestamp+"-")
		if err != nil {
			e.prepareErr = fmt.Errorf("create temp dir: %w", err)
			return
		}
		if err := extractTarGz(dir, e.data); err != nil {
			os.RemoveAll(dir)
			e.prepareErr = fmt.Errorf("extract tarball: %w", err)
			return
		}
		e.mu.Lock()
		e.extractDir = dir
		e.mu.Unlock()
		e.data = nil
		registerSignalCleanup(dir)
	})
	return e.prepareErr
}

// Dir returns the path to the extraction directory. Only valid after Prepare
// succeeds.
func (e *Extractor) Dir() string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.extractDir
}

// Cleanup removes the extraction temp directory. Safe to call if Prepare was
// never called or if the directory has already been removed.
func (e *Extractor) Cleanup() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.extractDir == "" {
		return nil
	}
	err := os.RemoveAll(e.extractDir)
	if err == nil {
		e.extractDir = ""
	}
	return err
}

// extractTarGz decompresses and extracts a tar.gz archive into dir.
func extractTarGz(dir string, data []byte) error {
	gr, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("gzip open: %w", err)
	}
	defer gr.Close()

	tr := tar.NewReader(gr)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("tar read: %w", err)
		}

		if !filepath.IsLocal(hdr.Name) {
			continue
		}

		target := filepath.Join(dir, hdr.Name)
		if !strings.HasPrefix(target, dir+string(os.PathSeparator)) && target != dir {
			continue
		}

		switch hdr.Typeflag {
		case tar.TypeSymlink, tar.TypeLink:
			continue
		case tar.TypeDir:
			if err := os.MkdirAll(target, os.FileMode(hdr.Mode)); err != nil {
				return fmt.Errorf("mkdir %s: %w", hdr.Name, err)
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return fmt.Errorf("mkdir parent %s: %w", hdr.Name, err)
			}
			f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(hdr.Mode))
			if err != nil {
				return fmt.Errorf("create %s: %w", hdr.Name, err)
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return fmt.Errorf("write %s: %w", hdr.Name, err)
			}
			f.Close()
		}
	}
	return nil
}

// registerSignalCleanup starts a goroutine that removes dir and exits when
// SIGINT, SIGTERM, or SIGQUIT is received. The exit code follows the
// conventional shell formula (128 + signal number): SIGINT→130, SIGQUIT→131,
// SIGTERM→143. Only one signal is acted upon; subsequent signals are not
// re-raised because the process is already exiting.
func registerSignalCleanup(dir string) {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM, syscall.SIGQUIT)
	go func() {
		sig := <-ch
		os.RemoveAll(dir)
		os.Exit(128 + int(sig.(syscall.Signal)))
	}()
}
