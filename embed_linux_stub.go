//go:build !(linux && (amd64 || arm64))

package clp

// Data holds the embedded tarball. On release builds this is populated by an
// arch-specific generated file's init(). On dev builds (non-Linux platforms or
// before go generate has run) it remains nil, causing Run to return an error.
// Run sets Data to nil after successful extraction to release the memory.
var Data []byte
