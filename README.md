# Piece-Table implementation in Odin.
This is my Piece-Table implementation written in Odin,\
and comes with unlimited linear undo & redo capability\*.\
**\*: Redo history is lost upon edits;  and default undo history is 100.**

**This code is not finished, and currently lacks saving capability.\
However, the code does work from my testing.**

I originally wrote this about a year ago, but in C.\
I wasn't happy with my C implementation, and decided to try learning Odin\
and better ways of programming.

There are two versions of my Piece-Table:
1. Standard.
2. Data-Blocks (Data that repeats).

The standard one is what you'd expect, you can insert slices of data.\
The Data-Block versions allows you to insert large amounts of repeating\
data without taking up much memory.  In short, you can insert a slice\
and have it be repeated for X bytes without taking up X bytes of memory.

---

My procedures:
```text
close :: proc(t: ^table_s) {...}
    Closes the Piece-Table without saving.

create :: proc(t: ^table_s, data: []u8 = nil, file: string = "") -> (ok: bool) {...}
    Creates a Piece-Table.
     * 'Data' slice is optional, and is the starting file contents if wanted.
     * This data is copied into the Piece-Table, not referenced;
     * you may free or edit your slice after an edit without issues.
     * 'File' is a string to a file to memory map into the Piece-Table.
     * You may use neither, or one of these options, not both.

edit :: proc(t: ^table_s, off, del: uint, data: []u8, vlen: uint = 0) -> (: edit_s, : bool) {...}
     * 'off' is the offset where an edit will take place (inclusive).
     * 'del' is the amount of bytes to delete (inclusive).
     * 'data' slice is data to insert, this is copied into the Piece-Table,
     * not referenced, you may safely free/modify your slice after an edit.
     *
     * --- Block version only ---
     * 'vlen' is the virtual length, say your slice is 'abc' and 'vlen' is 5,
     * that means 'abcab' is copied into the piece-table;
     * a 'vlen' that's smaller than length of slice means slice is inserted normally.
     *
     * Returns Edit information on success.

read :: proc(t: ^table_s, offset: uint, data: []u8) -> (r: uint) {...}
    Reads data from Piece-Table into slice,
     * returns bytes read.

redo :: proc(t: ^table_s) {...}
    Redos last undo.

undo :: proc(t: ^table_s) {...}
    Undoes last change.
```

---

My reasoning behind these procedure designs:\
For editing, I decided that having delete and insert be their own\
procedures was wasteful, especially since they mostly did the same thing.\
You can use the 'edit' procedure to insert, delete and replace data, all in one.\
Data is also copied into the Piece-Table, rather than referenced,\
as this allows for more flexibility and safety.

For creating/initializing a Piece-Table, I found that it made more sense\
to pass a pointer to a table struct, rather than allocate one.\
This allows for more flexibility.

For more notes about my design decisions, see the 'Documentation.txt' file.
