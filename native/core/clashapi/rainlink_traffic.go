package clashapi

import (
	"net/http"

	"github.com/go-chi/render"
	"github.com/sagernet/sing-box/experimental/clashapi/trafficontrol"
)

// The route is installed inside the existing authenticated Clash API group.
// Only aggregates are returned; no destination or full process path is exposed.
func rainlinkTraffic(manager *trafficontrol.Manager) http.HandlerFunc {
	return func(writer http.ResponseWriter, request *http.Request) {
		snapshot, err := manager.RainLinkTrafficSnapshot()
		if err != nil {
			render.Status(request, http.StatusServiceUnavailable)
			render.JSON(writer, request, map[string]string{"error": "traffic_unavailable"})
			return
		}
		render.JSON(writer, request, snapshot)
	}
}
