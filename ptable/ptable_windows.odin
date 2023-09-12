/*
	MIT License

	Copyright (c) 2023 xDahl

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
*/

// For the record, I don't understand the windows API.

package ptable

import k32 "core:sys/windows"
import "core:os"

@(private) BLOCK_DEFAULT_SIZE :: 1024*32 // Good enough?

@(private)
map_s :: struct {
	mapped : bool
	size : i64
	file_handle : k32.HANDLE
	map_handle  : k32.HANDLE
	map_view    : k32.LPVOID
}

@(private)
file_map :: proc(m : ^map_s, file : string) -> (ptr : uintptr, len : uint, ok : bool)
{
	m.size = os.file_size_from_path(file)
	if m.size == 0 {
		return 0, 0, false
	}


	m.file_handle = k32.CreateFileW(
		k32.LPCWSTR(k32.utf8_to_wstring(file))
		k32.GENERIC_READ,
		0, // No sharing = 0? Guessing...
		nil,
		k32.OPEN_EXISTING,
		k32.FILE_ATTRIBUTE_NORMAL,
		nil)

	if m.file_handle == k32.INVALID_HANDLE_VALUE {
		return 0, 0, false
	}
	defer if !ok {
		k32.CloseHandle(m.file_handle)
	}


	m.map_handle = k32.CreateFileMappingW(
		m.file_handle,
		nil,
		k32.PAGE_READONLY,
		0, 0, nil)

	if m.map_handle == nil {
		return 0, 0, false
	}
	defer if !ok {
		k32.CloseHandle(m.map_handle)
	}


	m.map_view = k32.MapViewOfFile(
		m.map_handle,
		k32.FILE_MAP_READ,
		0, 0, k32.SIZE_T(m.size))
	if m.map_view == nil {
		k32.UnmapViewOfFile(m.map_view)
		return 0, 0, false
	}


	ok = true
	return uintptr(m.map_view), uint(m.size), ok
}

@(private)
file_unmap :: proc(m : ^map_s)
{
	k32.CloseHandle(m.file_handle)
	k32.CloseHandle(m.map_handle)
	k32.UnmapViewOfFile(m.map_view)
}

@(private)
block_alloc :: proc(size : uint = BLOCK_DEFAULT_SIZE) -> (b : ^block_s)
{
	block_size : uint
	
	if size == 0 {
		block_size = BLOCK_DEFAULT_SIZE
	} else {
		// Block size required + one extra block.
		block_size = (size / BLOCK_DEFAULT_SIZE) * BLOCK_DEFAULT_SIZE + BLOCK_DEFAULT_SIZE
	}

	// MEM_COMMIT ensures data is initialized to 0.
	block := transmute(^block_s)k32.VirtualAlloc(
		nil,
		block_size,
		k32.MEM_COMMIT | k32.MEM_RESERVE,
		k32.PAGE_READWRITE)

	if block == nil {
		return nil
	}

	block.size = block_size - size_of(block_s)
	return block
}

@(private)
block_free :: proc(b : ^block_s)
{
	// I think this is the right way to do it?
	k32.VirtualFree(transmute(k32.LPVOID)b, 0, k32.MEM_RELEASE)
}
