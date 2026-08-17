//go:build windows

package securefs

import (
	"fmt"
	"os/user"
	"syscall"
	"unsafe"
)

const (
	sddlRevision1            = 1
	daclSecurityInformation  = 0x00000004
	protectedDACLInformation = 0x80000000
)

var (
	advapi32                        = syscall.NewLazyDLL("advapi32.dll")
	kernel32                        = syscall.NewLazyDLL("kernel32.dll")
	convertStringSecurityDescriptor = advapi32.NewProc("ConvertStringSecurityDescriptorToSecurityDescriptorW")
	setFileSecurity                 = advapi32.NewProc("SetFileSecurityW")
	localFree                       = kernel32.NewProc("LocalFree")
)

// Restrict replaces inherited ACLs with full control for the current Windows
// user and SYSTEM. This is the Windows equivalent of chmod 0600/0700; os.Chmod
// alone only changes the read-only bit on Windows.
func Restrict(path string, directory bool) error {
	current, err := user.Current()
	if err != nil {
		return fmt.Errorf("resolve current Windows user: %w", err)
	}
	if current.Uid == "" {
		return fmt.Errorf("current Windows user has no SID")
	}

	inheritance := ""
	if directory {
		inheritance = "OICI"
	}
	sddl := fmt.Sprintf(
		"D:P(A;%s;FA;;;SY)(A;%s;FA;;;%s)",
		inheritance,
		inheritance,
		current.Uid,
	)
	sddlPointer, err := syscall.UTF16PtrFromString(sddl)
	if err != nil {
		return fmt.Errorf("encode Windows ACL: %w", err)
	}
	var descriptor unsafe.Pointer
	converted, _, conversionErr := convertStringSecurityDescriptor.Call(
		uintptr(unsafe.Pointer(sddlPointer)),
		sddlRevision1,
		uintptr(unsafe.Pointer(&descriptor)),
		0,
	)
	if converted == 0 {
		return fmt.Errorf("create Windows ACL: %w", conversionErr)
	}
	defer localFree.Call(uintptr(descriptor))

	pathPointer, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return fmt.Errorf("encode secure path: %w", err)
	}
	applied, _, applyErr := setFileSecurity.Call(
		uintptr(unsafe.Pointer(pathPointer)),
		daclSecurityInformation|protectedDACLInformation,
		uintptr(descriptor),
	)
	if applied == 0 {
		return fmt.Errorf("apply Windows ACL to %q: %w", path, applyErr)
	}
	return nil
}
