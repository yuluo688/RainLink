// Package update validates RainLink bundles and replaces an installation with a
// rollback boundary. It never downloads code or changes network settings.
package update

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const (
	// ManifestName is included in every installable Windows bundle.
	ManifestName = "rainlink-bundle.json"
	maxArchive   = 300 << 20
	maxExpanded  = 1 << 30
	maxFiles     = 4096
	maxManifest  = 2 << 20
)

var versionPattern = regexp.MustCompile(`^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+(0|[1-9][0-9]*))?$`)
var hashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

// BundleFile binds a relative file name to the release's exact bytes.
type BundleFile struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

// Manifest describes the complete managed installation, excluding user data.
type Manifest struct {
	Schema   int          `json:"schema"`
	Product  string       `json:"product"`
	Platform string       `json:"platform"`
	Version  string       `json:"version"`
	Files    []BundleFile `json:"files"`
}

func validPath(name string) bool {
	if name == "" || len(name) > 240 || strings.ContainsAny(name, "\\:\x00") ||
		strings.HasPrefix(name, "/") || path.Clean(name) != name {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if part == "." || part == ".." || strings.HasSuffix(part, ".") || strings.HasSuffix(part, " ") {
			return false
		}
		for _, char := range part {
			if char < 32 || strings.ContainsRune(`<>:"|?*`, char) {
				return false
			}
		}
		base := strings.ToUpper(strings.SplitN(part, ".", 2)[0])
		if base == "CON" || base == "PRN" || base == "AUX" || base == "NUL" ||
			(strings.HasPrefix(base, "COM") || strings.HasPrefix(base, "LPT")) &&
				strings.Contains("|0|1|2|3|4|5|6|7|8|9|¹|²|³|", "|"+base[3:]+"|") {
			return false
		}
	}
	switch strings.ToLower(path.Ext(name)) {
	case ".sqlite", ".db", ".key", ".pem", ".jks", ".p12":
		return false
	}
	// Release packages own Flutter's data directory and specific runtime files.
	// No local database, credential file, or transaction marker can be shipped.
	if strings.Contains(name, "/") {
		return strings.HasPrefix(name, "data/")
	}
	lower := strings.ToLower(name)
	return lower == "rainlink.exe" || lower == "rainlink-ui.exe" || lower == "rainlink-host.exe" ||
		lower == "rainlink-updater.exe" || lower == "sing-box.exe" ||
		lower == "native_assets.yaml" ||
		lower == "sing-box-source.zip" || strings.HasSuffix(lower, ".dll") ||
		strings.HasSuffix(lower, "-license.txt") || lower == ManifestName
}

func parseManifest(data []byte) (Manifest, error) {
	var manifest Manifest
	if len(data) > maxManifest {
		return manifest, errors.New("manifest exceeds limit")
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return manifest, fmt.Errorf("decode manifest: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return manifest, errors.New("trailing manifest data")
	}
	if (manifest.Schema != 1 && manifest.Schema != 2) || manifest.Product != "RainLink" ||
		manifest.Platform != "windows-x64" || len(manifest.Version) > 128 ||
		!versionPattern.MatchString(manifest.Version) || len(manifest.Files) == 0 || len(manifest.Files) > maxFiles {
		return manifest, errors.New("unsupported bundle manifest")
	}
	seen := map[string]bool{}
	var total int64
	for _, file := range manifest.Files {
		key := strings.ToLower(file.Path)
		if !validPath(file.Path) || key == ManifestName || seen[key] ||
			file.Bytes < 0 || file.Bytes > maxExpanded || !hashPattern.MatchString(file.SHA256) {
			return manifest, errors.New("invalid manifest file")
		}
		seen[key] = true
		total += file.Bytes
		if total > maxExpanded {
			return manifest, errors.New("expanded bundle exceeds limit")
		}
	}
	for key := range seen {
		for parent := path.Dir(key); parent != "."; parent = path.Dir(parent) {
			if seen[parent] {
				return manifest, errors.New("file directory conflict")
			}
		}
	}
	for _, required := range []string{"rainlink.exe", "rainlink-host.exe", "rainlink-updater.exe", "sing-box.exe", "flutter_windows.dll", "data/app.so"} {
		if !seen[required] {
			return manifest, errors.New("incomplete runtime bundle")
		}
	}
	if manifest.Schema == 2 && !seen["rainlink-ui.exe"] {
		return manifest, errors.New("bootstrap bundle is missing its UI")
	}
	return manifest, nil
}

func runtimeExecutable(manifest Manifest) string {
	if manifest.Schema == 2 {
		return "rainlink-ui.exe"
	}
	return "rainlink.exe"
}

func bootstrapFile(manifest Manifest) BundleFile {
	for _, file := range manifest.Files {
		if strings.EqualFold(file.Path, "rainlink.exe") {
			return file
		}
	}
	return BundleFile{}
}

func replacementRoots(manifest Manifest) []string {
	result := roots(manifest)
	if manifest.Schema != 2 {
		return result
	}
	filtered := result[:0]
	for _, name := range result {
		if !strings.EqualFold(name, "rainlink.exe") {
			filtered = append(filtered, name)
		}
	}
	return filtered
}

func loadManifest(directory string) (Manifest, error) {
	file, err := os.Open(filepath.Join(directory, ManifestName))
	if err != nil {
		return Manifest{}, fmt.Errorf("open installed manifest: %w", err)
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxManifest+1))
	if err != nil {
		return Manifest{}, fmt.Errorf("read installed manifest: %w", err)
	}
	return parseManifest(data)
}

// Extract verifies the trusted outer digest, each ZIP entry and each file hash.
// destination must be a newly created directory owned by this transaction.
func Extract(ctx context.Context, archive, expectedHash, expectedVersion, destination string) (Manifest, error) {
	if !hashPattern.MatchString(expectedHash) {
		return Manifest{}, errors.New("missing archive digest")
	}
	input, err := os.Open(archive)
	if err != nil {
		return Manifest{}, fmt.Errorf("open bundle: %w", err)
	}
	defer input.Close()
	stat, err := input.Stat()
	if err != nil || !stat.Mode().IsRegular() || stat.Size() <= 0 || stat.Size() > maxArchive {
		return Manifest{}, errors.New("invalid archive size or type")
	}
	hash := sha256.New()
	if _, err = io.Copy(hash, &contextReader{ctx: ctx, reader: input}); err != nil {
		return Manifest{}, fmt.Errorf("hash bundle: %w", err)
	}
	if hex.EncodeToString(hash.Sum(nil)) != expectedHash {
		return Manifest{}, errors.New("archive digest mismatch")
	}
	reader, err := zip.NewReader(input, stat.Size())
	if err != nil || len(reader.File) > maxFiles+1 {
		return Manifest{}, errors.New("invalid zip bundle")
	}
	entries := map[string]*zip.File{}
	for _, file := range reader.File {
		key := strings.ToLower(file.Name)
		if !validPath(file.Name) || !file.Mode().IsRegular() || entries[key] != nil || file.UncompressedSize64 > maxExpanded {
			return Manifest{}, errors.New("unsafe zip entry")
		}
		entries[key] = file
	}
	manifestEntry := entries[ManifestName]
	if manifestEntry == nil || manifestEntry.Name != ManifestName || manifestEntry.UncompressedSize64 > maxManifest {
		return Manifest{}, errors.New("missing bundle manifest")
	}
	stream, err := manifestEntry.Open()
	if err != nil {
		return Manifest{}, fmt.Errorf("open manifest: %w", err)
	}
	data, readErr := io.ReadAll(io.LimitReader(stream, maxManifest+1))
	closeErr := stream.Close()
	if readErr != nil || closeErr != nil {
		return Manifest{}, errors.New("read bundle manifest")
	}
	manifest, err := parseManifest(data)
	if err != nil || strings.TrimPrefix(manifest.Version, "v") != strings.TrimPrefix(expectedVersion, "v") || len(entries) != len(manifest.Files)+1 {
		return Manifest{}, errors.New("bundle manifest does not match release")
	}
	for _, file := range manifest.Files {
		entry := entries[strings.ToLower(file.Path)]
		if entry == nil || entry.Name != file.Path || entry.UncompressedSize64 != uint64(file.Bytes) {
			return Manifest{}, errors.New("manifest and zip entries differ")
		}
		if err := extractFile(ctx, entry, file, destination); err != nil {
			return Manifest{}, err
		}
	}
	if err := writeJSON(filepath.Join(destination, ManifestName), manifest, true); err != nil {
		return Manifest{}, fmt.Errorf("save manifest: %w", err)
	}
	return manifest, nil
}

func extractFile(ctx context.Context, entry *zip.File, file BundleFile, destination string) error {
	stream, err := entry.Open()
	if err != nil {
		return fmt.Errorf("open bundle entry: %w", err)
	}
	defer stream.Close()
	name := filepath.Join(destination, filepath.FromSlash(file.Path))
	if err := os.MkdirAll(filepath.Dir(name), 0700); err != nil {
		return fmt.Errorf("create staging directory: %w", err)
	}
	output, err := os.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("create staged file: %w", err)
	}
	hash := sha256.New()
	size, copyErr := io.Copy(io.MultiWriter(output, hash), io.LimitReader(&contextReader{ctx: ctx, reader: stream}, file.Bytes+1))
	syncErr := output.Sync()
	closeErr := output.Close()
	if copyErr != nil || syncErr != nil || closeErr != nil || size != file.Bytes || hex.EncodeToString(hash.Sum(nil)) != file.SHA256 {
		return errors.New("staged file verification failed")
	}
	return nil
}

type contextReader struct {
	ctx    context.Context
	reader io.Reader
}

func (reader *contextReader) Read(buffer []byte) (int, error) {
	if err := reader.ctx.Err(); err != nil {
		return 0, err
	}
	return reader.reader.Read(buffer)
}

func roots(manifest Manifest) []string {
	seen := map[string]bool{ManifestName: true}
	for _, file := range manifest.Files {
		seen[strings.SplitN(file.Path, "/", 2)[0]] = true
	}
	result := make([]string, 0, len(seen))
	for name := range seen {
		result = append(result, name)
	}
	sort.Strings(result)
	return result
}
