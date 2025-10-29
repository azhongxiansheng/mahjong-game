package main

import (
	"os"
	"os/exec"
)

func main() {
	// Execute the backend server
	cmd := exec.Command("go", "run", "./backend/main.go")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	cmd.Run()
}
