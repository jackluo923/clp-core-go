// Package main is a development smoke test that calls clp.Run("--help") to
// verify that the embedded clp-s binary can be extracted and executed.
// Run with: bazel run //cmd/testrun
package main

import (
	"errors"
	"fmt"
	"log"
	"os/exec"

	clp "github.com/y-scope/clp-core-go"
)

func main() {
	stdout, stderr, err := clp.Run("--help")
	fmt.Println("=== stdout ===")
	fmt.Println(stdout)
	fmt.Println("=== stderr ===")
	fmt.Println(stderr)

	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		// clp-s --help exits non-zero; the binary extracted and ran successfully.
		fmt.Printf("clp-s exited %d (expected for --help)\n", exitErr.ExitCode())
		return
	}
	if err != nil {
		log.Fatalf("error: %v", err)
	}
}
