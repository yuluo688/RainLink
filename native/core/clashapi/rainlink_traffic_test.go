package clashapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/sagernet/sing-box/experimental/clashapi/trafficontrol"
)

func TestRainLinkTrafficEndpointRequiresSameAuthentication(t *testing.T) {
	router := chi.NewRouter()
	router.Group(func(route chi.Router) {
		route.Use(authentication("fixture-token"))
		route.Get("/rainlink/traffic", rainlinkTraffic(trafficontrol.NewManager()))
	})
	for _, token := range []string{"", "Bearer wrong", "Bearer fixture-token"} {
		request := httptest.NewRequest(http.MethodGet, "/rainlink/traffic", nil)
		request.Header.Set("Authorization", token)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if token != "Bearer fixture-token" {
			if response.Code != http.StatusUnauthorized {
				t.Fatal("unauthenticated aggregate request was accepted")
			}
			continue
		}
		var snapshot trafficontrol.RainLinkTrafficSnapshot
		if response.Code != http.StatusOK || json.Unmarshal(response.Body.Bytes(), &snapshot) != nil || snapshot.Version != 1 || snapshot.Epoch == "" || snapshot.Rows == nil {
			t.Fatal("aggregate endpoint did not return its versioned empty snapshot")
		}
	}
}
