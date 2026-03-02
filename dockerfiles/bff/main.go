package main

import (
	"encoding/json"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
)

func main() {
	port       := getEnv("SERVICE_PORT",    "8080")
	apiUserURL := getEnv("API_USER_URL",    "http://api-user:8080")
	apiOrderURL := getEnv("API_ORDER_URL",  "http://api-order:8080")
	apiProdURL := getEnv("API_PRODUCT_URL", "http://api-product:8080")

	mux := http.NewServeMux()
	mux.HandleFunc("/health",      healthHandler("bff"))
	mux.HandleFunc("/api/health",  healthHandler("bff"))
	mux.Handle("/api/users",       newProxy(apiUserURL))
	mux.Handle("/api/users/",      newProxy(apiUserURL))
	mux.Handle("/api/orders",      newProxy(apiOrderURL))
	mux.Handle("/api/orders/",     newProxy(apiOrderURL))
	mux.Handle("/api/products",    newProxy(apiProdURL))
	mux.Handle("/api/products/",   newProxy(apiProdURL))

	log.Printf("BFF listening :%s  user=%s order=%s product=%s",
		port, apiUserURL, apiOrderURL, apiProdURL)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func healthHandler(service string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy", "service": service})
	}
}

func newProxy(target string) http.Handler {
	u, err := url.Parse(target)
	if err != nil {
		log.Fatalf("invalid upstream URL %s: %v", target, err)
	}
	return httputil.NewSingleHostReverseProxy(u)
}
