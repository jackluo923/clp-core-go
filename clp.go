// Package clp provides access to the clp-s structured log compression and
// search engine. It embeds a pre-built clp-s binary so callers require no
// external installation. Use Run to compress, decompress, or search archives.
package clp

//go:generate ./scripts/go-generate.sh

import (
	"bytes"
	"fmt"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"

	"github.com/y-scope/clp-core-go/internal/extract"
)

var (
	extractor   atomic.Pointer[extract.Extractor]
	extractOnce sync.Once
	extractErr  error
)

// Run executes clp-s with the given arguments. The first call extracts the
// embedded binary to a per-process temp directory; subsequent calls reuse the
// same extraction. If extraction fails, all future calls return the same error
// — retrying Run will not help.
//
// The temp directory is removed automatically on SIGINT, SIGTERM, or SIGQUIT.
// Directories left by crashes or SIGKILL are not cleaned up automatically.
func Run(args ...string) (stdout, stderr string, err error) {
	extractOnce.Do(func() {
		// Data is populated by the generated file's init(). Checking here
		// (inside Do) guarantees we see the post-init value, unlike a
		// package-level var initializer which runs before init().
		if len(Data) == 0 {
			extractErr = fmt.Errorf("clp: no embedded binary data")
			return
		}
		ext := extract.New(Data)
		if err := ext.Prepare(); err != nil {
			extractErr = fmt.Errorf("clp: prepare: %w", err)
			return
		}
		extractor.Store(ext)
		Data = nil
	})
	if extractErr != nil {
		return "", "", extractErr
	}

	// The binary name is fixed to clp-s — it matches the path produced by
	// the CLP build system and hard-coded in the Docker build scripts.
	binPath := filepath.Join(extractor.Load().Dir(), "bin", "clp-s")
	cmd := exec.Command(binPath, args...)

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	if err := cmd.Run(); err != nil {
		return outBuf.String(), errBuf.String(), fmt.Errorf("clp-s: %w", err)
	}
	return outBuf.String(), errBuf.String(), nil
}

// Cleanup removes the temp directory created by the first Run call. Safe to
// call if Run has never been called or if the directory has already been
// removed. Intended for programs that exit normally (without SIGINT/SIGTERM/
// SIGQUIT) and want to clean up eagerly rather than relying on the OS.
func Cleanup() error {
	ext := extractor.Load()
	if ext == nil {
		return nil
	}
	return ext.Cleanup()
}
