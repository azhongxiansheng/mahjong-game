package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	fmt.Println("✅ Server starting on :8080")

	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, `{"status":"ok"}`)
	})

	fmt.Println("✅ Listening...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}
