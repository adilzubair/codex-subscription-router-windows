//go:build !windows

package securefs

import "os"

// Restrict limits a path to its owner. Directories remain traversable by the
// owner while files are readable and writable only by the owner.
func Restrict(path string, directory bool) error {
	mode := os.FileMode(0o600)
	if directory {
		mode = 0o700
	}
	return os.Chmod(path, mode)
}
