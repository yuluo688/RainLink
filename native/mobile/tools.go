//go:build tools

package mobile

// Keep the binding generator's runtime in the module graph for gomobile bind.
import _ "github.com/sagernet/gomobile/bind"
