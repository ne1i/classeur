#+build !windows
#+build !linux
package fs

// Another system (macOS first): multicast DNS finds the devices by itself; the system adds none.
system_devices_add :: proc(list: ^[dynamic]Network_Device, allocator := context.allocator) {}
