package extract

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// createTarball builds an in-memory tar.gz from the given entries.
// Each entry is {name, typeflag, mode, linkname, content}.
func createTarball(t *testing.T, entries []tar.Header, contents []string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gw)
	for i, hdr := range entries {
		hdr.ModTime = time.Now()
		body := ""
		if i < len(contents) {
			body = contents[i]
		}
		hdr.Size = int64(len(body))
		if err := tw.WriteHeader(&hdr); err != nil {
			t.Fatalf("write header %s: %v", hdr.Name, err)
		}
		if body != "" {
			if _, err := tw.Write([]byte(body)); err != nil {
				t.Fatalf("write body %s: %v", hdr.Name, err)
			}
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatalf("close tar: %v", err)
	}
	if err := gw.Close(); err != nil {
		t.Fatalf("close gzip: %v", err)
	}
	return buf.Bytes()
}

func createTestTarball(t *testing.T) []byte {
	t.Helper()
	return createTarball(t, []tar.Header{
		{Name: "bin/hello", Typeflag: tar.TypeReg, Mode: 0755},
		{Name: "lib/clp/libfake.so", Typeflag: tar.TypeReg, Mode: 0644},
	}, []string{
		"#!/bin/sh\necho hi\n",
		"FAKESO\n",
	})
}

func TestPrepare_ExtractsTarball(t *testing.T) {
	data := createTestTarball(t)
	e := New(data)

	if err := e.Prepare(); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	defer e.Cleanup()

	dir := e.Dir()

	binPath := filepath.Join(dir, "bin", "hello")
	fi, err := os.Stat(binPath)
	if err != nil {
		t.Fatalf("stat bin/hello: %v", err)
	}
	if fi.Mode().Perm()&0111 == 0 {
		t.Errorf("bin/hello not executable: %v", fi.Mode())
	}

	libPath := filepath.Join(dir, "lib", "clp", "libfake.so")
	if _, err := os.Stat(libPath); err != nil {
		t.Fatalf("stat lib/clp/libfake.so: %v", err)
	}
}

func TestPrepare_Idempotent(t *testing.T) {
	data := createTestTarball(t)
	e := New(data)

	if err := e.Prepare(); err != nil {
		t.Fatalf("first Prepare: %v", err)
	}
	dir1 := e.Dir()

	if err := e.Prepare(); err != nil {
		t.Fatalf("second Prepare: %v", err)
	}
	dir2 := e.Dir()

	if dir1 != dir2 {
		t.Errorf("expected same dir, got %q then %q", dir1, dir2)
	}
	defer e.Cleanup()
}

func TestCleanup_RemovesDir(t *testing.T) {
	data := createTestTarball(t)
	e := New(data)

	if err := e.Prepare(); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	dir := e.Dir()

	if err := e.Cleanup(); err != nil {
		t.Fatalf("Cleanup: %v", err)
	}

	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Errorf("temp dir still exists after Cleanup: %s", dir)
	}
}

func TestCleanup_NoOpIfNotPrepared(t *testing.T) {
	e := New(nil)
	if err := e.Cleanup(); err != nil {
		t.Fatalf("Cleanup on unprepared: %v", err)
	}
}

func TestPrepare_SkipsPathTraversal(t *testing.T) {
	data := createTarball(t, []tar.Header{
		{Name: "../escape", Typeflag: tar.TypeReg, Mode: 0644},
		{Name: "/absolute", Typeflag: tar.TypeReg, Mode: 0644},
		{Name: "safe", Typeflag: tar.TypeReg, Mode: 0644},
	}, []string{"bad", "bad", "ok"})

	e := New(data)
	if err := e.Prepare(); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	defer e.Cleanup()

	dir := e.Dir()
	if _, err := os.Stat(filepath.Join(filepath.Dir(dir), "escape")); err == nil {
		t.Error("path traversal entry was extracted outside temp dir")
	}
	if _, err := os.Stat("/absolute"); err == nil {
		t.Error("absolute path entry was extracted to /absolute")
	}
	if _, err := os.Stat(filepath.Join(dir, "safe")); err != nil {
		t.Errorf("safe entry was not extracted: %v", err)
	}
}

func TestPrepare_SkipsSymlinksAndHardlinks(t *testing.T) {
	data := createTarball(t, []tar.Header{
		{Name: "real", Typeflag: tar.TypeReg, Mode: 0644},
		{Name: "sym", Typeflag: tar.TypeSymlink, Linkname: "real", Mode: 0644},
		{Name: "hard", Typeflag: tar.TypeLink, Linkname: "real", Mode: 0644},
	}, []string{"content", "", ""})

	e := New(data)
	if err := e.Prepare(); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	defer e.Cleanup()

	dir := e.Dir()
	if fi, err := os.Lstat(filepath.Join(dir, "sym")); err == nil {
		t.Errorf("symlink was extracted: mode=%v", fi.Mode())
	}
	if _, err := os.Lstat(filepath.Join(dir, "hard")); err == nil {
		t.Error("hardlink was extracted")
	}
}

func TestPrepare_CorruptedGzip(t *testing.T) {
	e := New([]byte("this is not gzip data"))
	if err := e.Prepare(); err == nil {
		t.Fatal("expected error for corrupted gzip, got nil")
	}
}

func TestPrepare_ErrorPersists(t *testing.T) {
	e := New([]byte("corrupted"))
	err1 := e.Prepare()
	if err1 == nil {
		t.Fatal("expected error on first call")
	}
	err2 := e.Prepare()
	if err2 == nil {
		t.Fatal("expected error on second call")
	}
	if err1.Error() != err2.Error() {
		t.Errorf("error changed between calls: %q vs %q", err1, err2)
	}
}
