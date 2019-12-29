#--
# the rod scripting language
# copyright (C) iLiquid, 2019
# licensed under the MIT license
#--

import tables

import parser
import value

type
  Opcode* = enum ## An opcode, used for execution.
    # Stack
    opcPushTrue = "pushTrue"
    opcPushFalse = "pushFalse"
    opcPushN = "pushN" ## Push number
    opcPushS = "pushS" ## Push string
    opcPushG = "pushG" ## Push global
    opcPopG = "popG" ## Pop global
    opcPushL = "pushL" ## Push local
    opcPopL = "popL" ## Pop local
    opcConstrObj = "constrObj" ## Construct object
    opcPushF = "pushF" ## Push field
    opcPopF = "popF" ## Pop field
    opcDiscard = "discard" ## Discard values
    # Arithmetic operations
    opcNegN = "negN" ## Negate number
    opcAddN = "addN" ## Add numbers
    opcSubN = "subN" ## Subtract numbers
    opcMultN = "multN" ## Multiply numbers
    opcDivN = "divN" ## Divide numbers
    # Logic operations
    opcInvB = "invB" ## Invert bool
    # Relational operations
    opcEqB = "eqB" ## Equal bools
    opcEqN = "eqN" ## Equal numbers
    opcLessN = "lessN" ## Number less than
    opcLessEqN = "lessEqN" ## Number less than or equal
    opcGreaterN = "greaterN" ## Number greater than
    opcGreaterEqN = "greaterEqN" ## Number greater than or equal
    # Execution
    opcJumpFwd = "jumpFwd" ## Jump forward
    opcJumpFwdT = "jumpFwdT" ## Jump forward if true
    opcJumpFwdF = "jumpFwdF" ## Jump forward if false
    opcJumpBack = "jumpBack" ## Jump backward
    opcCallD = "callD" ## Call direct
    opcCallR = "callR" ## Call indirect
    opcHalt = "halt"

  Script* = ref object ## A complete rod script.
    procs*: seq[Proc] ## The procs declared across all of the script's modules.
    mainChunk*: Chunk ## The main chunk of this script.
  LineInfo* = tuple ## Line information.
    ln, col: int
    runLength: int
  Chunk* = ref object ## A chunk of bytecode.
    file*: string ## The filename of the module this chunk belongs to.
    code*: seq[uint8] ## The raw bytecode.
    ln*, col*: int ## The current line info used when emitting bytecode.
    lineInfo: seq[LineInfo] ## A list of run-length encoded line info.
    strings*: seq[string] ## A table of strings used in this chunk.
  ProcKind* = enum
    pkNative ## A native (bytecode) proc
    pkForeign ## A foreign (Nim) proc
  Proc* = ref object ## A runtime procedure.
    case kind*: ProcKind
    of pkNative:
      chunk*: Chunk ## The chunk of bytecode of this procedure.
      stackSize*: int ## The amount of values this procedure needs on the stack.
    of pkForeign:
      discard # TODO: foreign procedures
    paramCount*: int ## The number of parameters this procedure takes.

proc addLineInfo*(chunk: var Chunk, n: int) =
  ## Add ``n`` line info entries to the chunk.
  if chunk.lineInfo.len > 0:
    if chunk.lineInfo[^1].ln == chunk.ln and
       chunk.lineInfo[^1].col == chunk.col:
      inc(chunk.lineInfo[^1].runLength, n)
      return
  chunk.lineInfo.add((chunk.ln, chunk.col, n))

proc getString*(chunk: var Chunk, str: string): uint16 =
  ## Get a string ID from a chunk, adding it to the chunk's string list if it
  ## isn't already stored.
  ## TODO: This is an `O(n)` operation, depending on the number of strings
  ## already stored in the chunk. Optimize this.
  if str notin chunk.strings:
    result = chunk.strings.len.uint16
    chunk.strings.add(str)
  else:
    result = chunk.strings.find(str).uint16

proc emit*(chunk: var Chunk, opc: Opcode) =
  ## Emit an opcode.
  chunk.addLineInfo(1)
  chunk.code.add(opc.uint8)

proc emit*(chunk: var Chunk, u8: uint8) =
  ## Emit a ``uint8``.
  chunk.addLineInfo(1)
  chunk.code.add(u8)

proc emit*(chunk: var Chunk, u16: uint16) =
  ## Emit a ``uint16``.
  chunk.addLineInfo(2)
  chunk.code.add([uint8 u16 and 0x00ff'u16,
                  uint8 (u16 and 0xff00'u16) shr 8])

proc emit*(chunk: var Chunk, val: Value) =
  ## Emit a Value.
  chunk.addLineInfo(ValueSize)
  chunk.code.add(val.into.bytes)

proc emitHole*(chunk: var Chunk, size: int): int =
  ## Emit a hole, to be filled later by ``fillHole``.
  result = chunk.code.len
  chunk.addLineInfo(size)
  for i in 1..size:
    chunk.code.add(0x00)

proc fillHole*(chunk: var Chunk, hole: int, val: uint8) =
  ## Fill a hole with an 8-bit value.
  chunk.code[hole] = val

proc fillHole*(chunk: var Chunk, hole: int, val: uint16) =
  ## Fill a hole with a 16-bit value.
  chunk.code[hole] = uint8(val and 0x00ff)
  chunk.code[hole + 1] = uint8((val and 0xff00) shr 8)

proc getOpcode*(chunk: Chunk, i: int): Opcode =
  ## Get the opcode at position ``i``.
  result = chunk.code[i].Opcode

proc getU8*(chunk: Chunk, i: int): uint8 =
  ## Gets the ``uint8`` at position ``i``.
  result = chunk.code[i]

proc getU16*(chunk: Chunk, i: int): uint16 =
  ## Get the ``uint16`` at position ``i``.
  result = chunk.code[i].uint16 or chunk.code[i + 1].uint16 shl 8

proc getValue*(chunk: Chunk, i: int): Value =
  ## Get a constant Value at position ``i``.
  var
    bytes: array[ValueSize, uint8]
    raw = cast[ptr UncheckedArray[uint8]](chunk.code[i].unsafeAddr)
  for i in low(bytes)..high(bytes):
    bytes[i] = raw[i]
  result = Value(into: RawValue(bytes: bytes))

proc getLineInfo*(chunk: Chunk, i: int): LineInfo =
  ## Get the line info at position ``i``. **Warning:** This is very slow,
  ## because it has to walk the entire chunk decoding the run length encoded
  ## line info!
  var n = 0
  for li in chunk.lineInfo:
    for r in 1..li.runLength:
      if n == i:
        return li
      inc(n)

proc newChunk*(): Chunk =
  ## Create a new chunk.
  result = Chunk()

proc newScript*(main: Chunk): Script =
  ## Create a new script, with the given main chunk.
  result = Script(mainChunk: main)

