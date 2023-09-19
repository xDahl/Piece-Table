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

package ptable

import "core:mem"

// This should be a reasonable default.
@(private) UNDO_DEFAULT_MAX :: 100


// @(private)
block_s :: struct {
	next : ^block_s // Linked list to next block.
	size : uint     // Size of block (excluding block struct)
	nidx : uint     // Node index to grow from.
	aidx : uint     // Append index to grow from.
}

table_s :: struct {
	block : ^block_s

	head, tail : piece_s // Dummy pieces for Linked list.
	size : uint // Size of "file" / "table data".

	file : map_s // File mapping.

	// TODO: Last accessed piece cache.
	// cpiece  : ^piece_s
	// coffset : uint // Starting offset of the piece.next.

	// Undo:
	udummy : undo_s // Dummy piece for oldest edit piece.
	undo : ^undo_s  // Ptr to piece to undo, t.undo.prev is redo.
	undo_max : uint // Max undo history, 0 = disabled.
	undo_counter : uint

	// Free-list for allocation.
	free_piece : ^piece_s
	free_undo  : ^undo_s
}

// @(private)
piece_s :: struct {
	next, prev : ^piece_s
	ptr : uintptr
	len : uint
}

// Edit info on where an edit took place, and amount of deletion & insertion.
edit_s :: struct {
	off, del, add : uint
}

// @(private)
undo_s :: struct {
	next, prev : ^undo_s
	head, tail : ^piece_s // Pieces that were replaced / connected pieces.
	piece_offset : uint // Todo: Needed for caching. Offset where the first piece starts.
	edit : edit_s
	reconnect : bool // head and tail point to pieces in active linked list.
}

/* Creates a Piece-Table.
 * 'Data' slice is optional, and is the starting file contents if wanted.
 * This data is copied into the Piece-Table, not referenced;
 * you may free your slice if need be without issues.
 * 'File' is a string to a file to memory map into the Piece-Table.
 * You may use neither, or one of these options, not both. */
create :: proc(t : ^table_s, data : []u8 = nil, file : string = "") -> (ok : bool)
{
	// You can either use a file or have optional starting buffer.
	if len(file) > 0 && data != nil {
		return false
	}

	t^ = table_s{} // Zero initialize if it weren't already.

	t.block = block_alloc(t.size)
	if t.block == nil {
		return false
	}
	defer if ok != true {
		block_free(t.block)
		t.block = nil
	}

	if len(file) > 0 {
		ptr, size, ok := file_map(&t.file, file)
		if !ok {
			return false
		}

		piece := get_struct(piece_s, t, 0)
		piece.ptr, piece.len = ptr, size

		t.head.next = piece
		piece.prev = &t.head
		piece.next = &t.tail
		t.tail.prev = piece

		t.file.mapped = ok
		t.size = size
	} else if len(data) > 0 {
		piece := get_struct(piece_s, t, len(data))
		piece.ptr, piece.len = prepend(t.block, data[:])

		t.head.next = piece
		piece.prev = &t.head
		piece.next = &t.tail
		t.tail.prev = piece

		t.size = len(data)
	} else {
		// No piece needed.
		t.head.next = &t.tail
		t.tail.prev = &t.head
	}

	t.undo = &t.udummy
	t.undo_max = UNDO_DEFAULT_MAX
	ok = true
	return
}

/* Note: Currently does nothing. */
save :: proc(t : ^table_s, file : string)
{
	// TODO.
}

/* Closes the Piece-Table without saving. */
close :: proc(t : ^table_s)
{
	if t.block == nil {
		return
	}

	for {
		n := t.block.next
		block_free(t.block)
		
		if n == nil {
			break
		}
		t.block = n
	}

	if t.file.mapped {
		file_unmap(&t.file)
	}
}

@(private)
table_lookup :: proc(t : ^table_s, offset : uint) -> (begin : uint, p : ^piece_s)
{
	offset := offset

	for p = t.head.next; p != &t.tail; p = p.next {
		if offset >= p.len {
			offset -= p.len
		} else {
			begin = offset
			break;
		}
	}

	return
}

/* Reads data from Piece-Table into slice,
 * returns bytes read. */
read :: proc(t : ^table_s, offset : uint, data : []u8) -> (r : uint)
{
	length : uint = len(data)

	if offset >= t.size {
		return 0
	}

	if offset + length > t.size {
		length = t.size - offset
	}

	// p cannot be tail due to returning early above.
	begin, p := table_lookup(t, offset)

	for ; r < length ; {
		max_len : uint = min(p.len - begin, length - r)

		mem.copy_non_overlapping(
			rawptr(transmute(uintptr)raw_data(data) + uintptr(r)),
			transmute(rawptr)(transmute(uintptr)p.ptr + uintptr(begin)),
			int(max_len))

		r += max_len
		begin = 0
		p = p.next // should never reach tail due to limiting 'length'
	}

	return
}

/* Undoes last change. */
undo :: proc(t : ^table_s) -> edit_s
{
	if t.undo == &t.udummy {
		return edit_s{0, 0, 0}
	}

	t.undo = t.undo.next
	e := table_swap(t, t.undo.prev)
	t.size -= e.add
	t.size += e.del
	return e
}

/* Redos last undo. */
redo :: proc(t : ^table_s) -> edit_s
{
	if t.undo.prev == nil {
		return edit_s{0, 0, 0}
	}

	t.undo = t.undo.prev
	e := table_swap(t, t.undo)
	t.size += e.add
	t.size -= e.del
	return e
}

// My pointer swap code here can be a little terse.
@(private)
table_swap :: proc(t : ^table_s, u : ^undo_s) -> edit_s
{
	// reconnect head and tail
	if u.reconnect {
		u.head = u.head.next
		u.tail = u.tail.prev

		u.head.prev.next = u.tail.next
		u.tail.next.prev = u.head.prev

		u.reconnect = false
	} else if u.head.prev.next == u.tail.next {
		// The 'if' above means we deleted X whole pieces.
		// So we need to re-add them :)

		u.head.prev.next = u.head;
		u.head.prev = u.head.prev;

		u.tail.next = u.tail.next;
		u.tail.next.prev = u.tail;

		u.head = u.head.prev
		u.tail = u.tail.next

		// Set redo.reconnect to 1 after this,
		// as we basically inserted X pieces between two pieces.
		u.reconnect = true
	} else {
		p0 := u.head.prev.next
		p1 := u.tail.next.prev

		u.head.prev.next = u.head
		u.head.prev = u.head.prev

		u.tail.next = u.tail.next
		u.tail.next.prev = u.tail

		u.head = p0
		u.tail = p1
	}

	return u.edit
}

/* Makes an edit to the Piece-Table contents.
 * 'off' is the offset where an edit will take place (inclusive).
 * 'del' is the amount of bytes to delete (inclusive).
 * 'data' slice is data to insert, this is copied into the Piece-Table,
 * not referenced, you may safely free your slice.
 * Returns Edit information on success. */
edit :: proc(t : ^table_s, off, del : uint, data : []u8) -> (edit_s, bool)
{
	commit_undo :: proc(t : ^table_s, head,
		tail : ^piece_s,
		u : ^undo_s,
		e : edit_s,
		poff : uint,
		reconnect : bool)
	{
		if t.undo_max == 0 {
			return
		}

		u.head = head
		u.tail = tail

		u.edit = e
		u.piece_offset = poff
		u.reconnect = reconnect

		// redo history gets deleted,
		// so our latest redo ptr points to nothing.
		u.prev = nil

		u.next = t.undo
		t.undo.prev = u
		t.undo = u
	}

	// Validate arguments.
	off := off
	del := del

	if off > t.size {
		off = t.size
		del = 0
	} else if del > t.size - off {
		del = t.size - off
	}

	if len(data) == 0 && del == 0 {
		return {0, 0, 0}, false
	}



	// Fetch pieces to replace.
	begin : [2]uint     // Where data in pieces begin.
	piece : [2]^piece_s // Pieces to put in undo history.
	new   : [3]^piece_s // New pieces to insert.
	amt   : uint        // Amount of pieces needed to insert.

	// Starting from end piece due to future caching reasons.
	begin[1], piece[1] = table_lookup(t, off + del)
	if begin[1] == 0 {
		// Beginning at 0 for deletion means it excludes.
		piece[1] = piece[1].prev
	} else {
		amt += 1
	}

	begin[0], piece[0] = table_lookup(t, off)
	if begin[0]  > 0 { amt += 1 }
	if len(data) > 0 { amt += 1 }


	free_undo :: proc(t : ^table_s, u : ^undo_s)
	{
		if !u.reconnect {
			p : ^piece_s = u.head

			for {
				n := p.next
				p.next = t.free_piece
				t.free_piece = p
				if p == u.tail { break }
				p = n
			}
		}
	}


	// Free redo history.
	u : ^undo_s
	for {
		u = t.undo.prev
		if u == nil { break }

		free_undo(t, u)

		t.undo.prev = u.prev

		u.next = t.free_undo
		t.free_undo = u
		t.undo_counter -= 1
	}

	// Handle max undos, free oldest undo node.
	if t.undo_counter == t.undo_max && t.undo_max > 0 {
		u = t.udummy.prev
		if u != nil {
			t.udummy.prev = u.prev
			u.prev.next = &t.udummy
			free_undo(t, u)
			t.undo_counter -= 1
		}
	}


	// Reserve pieces & append memory.
	// 	if no memory, quit.
	// Note: 'new' pieces point/link to each other,
	// 	this procedure takes care of that.
	if !table_reserve(t, &new, amt, len(data), &u) {
		return {0, 0, 0}, false
	}



	/* There are two special cases for editing pieces...
	 * Deleting a multiple of full pieces.
	 * Inserting a piece between two others.
	 * Besides that, it's a matter of replacing 1-n pieces with 1-3 new ones. */



	// Inserting a piece between two others.
	if amt == 1 && begin[0] == 0 && del == 0 {
		commit_undo(t, piece[0].prev, piece[0], u,
			{off, del, len(data)},
			off, true)

		new[0].ptr, new[0].len = prepend(t.block, data)
		new[0].prev = piece[0].prev
		new[0].prev.next = new[0]

		new[0].next = piece[0]
		piece[0].prev = new[0]
	} else if amt > 0 {
		commit_undo(t, piece[0], piece[1], u,
			{off, del, len(data)},
			off - begin[0],
			false)

		idx : uint
		if begin[0] > 0 {
			new[idx].ptr = piece[0].ptr
			new[idx].len = begin[0]
			idx += 1
		}

		if len(data) > 0 {
			new[idx].ptr, new[idx].len = prepend(t.block, data)
			idx += 1
		}

		if begin[1] > 0 {
			new[idx].ptr = piece[1].ptr + uintptr(begin[1])
			new[idx].len = piece[1].len - begin[1]
		}

		new[0].prev = piece[0].prev
		new[0].prev.next = new[0]

		new[amt-1].next = piece[1].next
		new[amt-1].next.prev = new[amt-1]
	} else {
		// Delete X whole pieces.
		commit_undo(t, piece[0], piece[1], u,
			{off, del, len(data)},
			off - begin[0], // TODO: We might not need subtraction here...
			false)

		// Link neighbors.
		piece[0].prev.next = piece[1].next
		piece[1].next.prev = piece[0].prev
	}


	t.size += len(data)
	t.size -= del

	if t.undo_max > 0 {
		t.undo_counter += 1
	}

	return {off, del, len(data)}, true
}

@(private)
get_struct :: proc($T : typeid, t : ^table_s, size : uint) -> ^T
{
	switch typeid_of(T) {
	case piece_s:
		if t.free_piece != nil {
			ptr := rawptr(t.free_piece)
			t.free_piece = t.free_piece.next
			return (^T)(ptr)
		}
	case undo_s:
		if t.free_undo != nil {
			ptr := rawptr(t.free_undo)
			t.free_undo = t.free_undo.next
			return (^T)(ptr)
		}
	}

	if t.block.size - t.block.nidx - t.block.aidx < size_of(T) {
		b := block_alloc(size)
		if b == nil {
			return nil
		}
		b.next = t.block
		t.block = b
	}

	ptr := rawptr(transmute(uintptr)t.block + size_of(block_s) + uintptr(t.block.nidx))
	t.block.nidx += size_of(T)
	return (^T)(ptr)
}

// TODO: Maybe make this procedure return a pointer/slice where we can append to?
@(private)
table_reserve :: proc(t : ^table_s, ptr : ^[3]^piece_s, amt, size : uint, u : ^^undo_s) -> bool
{
	u := u

	// Undo enabled check.
	if t.undo_max > 0 {
		u^ = get_struct(undo_s, t, size)
		if u^ == nil {
			return false
		}
	}

	for i in 0..<amt {
		ptr[i] = get_struct(piece_s, t, size)
		if ptr[i] == nil {
			if u^ != nil {
				u^.next = t.free_undo
				t.free_undo = u^
			}

			for k in 0..<i {
				ptr[i].next = t.free_piece
				t.free_piece = ptr[i]
			}

			return false
		}
		if i > 0 {
			// Link new pieces together.
			ptr[i-1].next = ptr[i]
			ptr[i].prev = ptr[i-1]
		}
	}

	return true
}

@(private)
prepend :: proc(block : ^block_s, data : []u8) -> (uintptr, uint)
{
	if block.size - block.aidx - block.nidx < len(data) {
		return 0, 0
	}

	dest : uintptr = transmute(uintptr)block
	dest += size_of(block_s)
	dest += uintptr(block.size)
	dest -= uintptr(block.aidx)
	dest -= uintptr(len(data))

	mem.copy_non_overlapping(rawptr(dest),
		transmute(rawptr)&data[0],
		len(data))
	block.aidx += len(data)

	return dest, len(data)
}
