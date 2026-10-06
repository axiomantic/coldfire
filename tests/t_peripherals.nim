## `t_peripherals` - unit test suite for MCF5407 on-chip peripherals.
##
## Covers:
##   - SIM registers (RSR, SYPCR, SWIVR, SWSR, PAR, IRQPAR, PLLCR, MPARK)
##   - Chip selects (CS0..CS7: CSARn, CSMRn, CSCRn)
##   - DRAM controller (DCR, DACR0/1, DMR0/1)
##   - Parallel port (PADDR, PADAT with bit 9 strap)
##   - ColdFire model strap (UIPCR at 0x1D0)
##   - 2-Tier Interrupt Controller (arbitration, autovectoring, internal/external)
##   - Timers 0 & 1 (counting, prescaler, reference match, TER, ICR integration)
##   - DUART Channel A (UMR1/2 toggling, USR, 4-byte Rx FIFO, Tx, UIVR, ICR integration)
##   - I2C / M-Bus controller (START/STOP, master transmit/receive, mock slave, MIF)
##   - MBAR memory-mapped access routing and byte-size enforcement

import std/strutils

import coldfire/cpu
import coldfire/decode_types
import coldfire/machine
import coldfire/sim
import coldfire/intc
import coldfire/timer
import coldfire/uart
import coldfire/mbus

var failures: seq[string]
var passCount = 0

proc checkImpl(ok: bool; label: string; got: string; want: string) =
  if ok:
    echo "PASSED  ", label
    inc passCount
  else:
    echo "FAILED  ", label
    echo "          got  ", got
    echo "          want ", want
    failures.add(label)

template check(ok: bool; label: string; got: string; want: string) =
  checkImpl(ok, label, got, want)

template check(ok: bool; label: string) =
  checkImpl(ok, label, (if ok: "true" else: "false"), "true")

# ---------------------------------------------------------------------------
# Test Board for CPU execution
# ---------------------------------------------------------------------------

const memSize = 0x2000

type Board = object
  bytes: array[memSize, uint8]

var board: Board

proc bRead(user: pointer; address: uint32; size: cint;
           status: ptr Mcf5407BusStatus): uint32 {.cdecl.} =
  let b = cast[ptr Board](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5407BusStatus.busUnmapped
    return 0'u32
  status[] = Mcf5407BusStatus.busOk
  var res = 0'u32
  for i in 0 ..< int(size):
    res = (res shl 8) or uint32(b.bytes[int(address) + i])
  res

proc bWrite(user: pointer; address: uint32; size: cint; value: uint32;
            status: ptr Mcf5407BusStatus) {.cdecl.} =
  let b = cast[ptr Board](user)
  if int(address) + int(size) > memSize:
    status[] = Mcf5407BusStatus.busUnmapped
    return
  status[] = Mcf5407BusStatus.busOk
  for i in 0 ..< int(size):
    b.bytes[int(address) + i] =
      uint8((value shr ((int(size) - 1 - i) * 8)) and 0xFF'u32)

proc bIack(user: pointer; level: cint; vector: uint8) {.cdecl.} =
  discard

proc freshContext(): MCF5407Ctx =
  for i in 0 ..< memSize:
    board.bytes[i] = 0'u8
  result = cf_create(addr board, bRead, bWrite, bIack)
  cf_reset(result, 0x1000'u32, 0x400'u32)

# ===========================================================================
# Block 1: SIM registers, Chip Selects, DRAM, GPIO
# ===========================================================================

block:
  let ctx = freshContext()
  ctx.mbar = 0x1000_0001'u32 # MBAR at 0x1000_0000, valid = 1

  # RSR reset default: bit 7 (HRST) = 1
  let rsr = readMem(ctx, 0x1000_0000'u32, 1)
  check((rsr and 0x80'u32) != 0'u32, "SIM: RSR has HRST bit 7 set at reset")

  # SWIVR reset default: 0x0F
  let swivr = readMem(ctx, 0x1000_0002'u32, 1)
  check(swivr == 0x0F'u32, "SIM: SWIVR reset default is 0x0F")

  # PAR (16-bit) read/write
  writeMem(ctx, 0x1000_0004'u32, 2, 0x1234'u32)
  let par = readMem(ctx, 0x1000_0004'u32, 2)
  check(par == 0x1234'u32, "SIM: PAR 16-bit write and read-back", $par, "0x1234")

  # PLLCR (8-bit) read/write
  writeMem(ctx, 0x1000_0008'u32, 1, 0x55'u32)
  let pllcr = readMem(ctx, 0x1000_0008'u32, 1)
  check(pllcr == 0x55'u32, "SIM: PLLCR 8-bit write and read-back", $pllcr, "0x55")

  # MPARK (8-bit) read/write
  writeMem(ctx, 0x1000_000C'u32, 1, 0xAA'u32)
  let mpark = readMem(ctx, 0x1000_000C'u32, 1)
  check(mpark == 0xAA'u32, "SIM: MPARK 8-bit write and read-back", $mpark, "0xAA")

  # Chip selects CS0: CSAR0 (16-bit), CSMR0 (32-bit), CSCR0 (16-bit)
  writeMem(ctx, 0x1000_0080'u32, 2, 0xFF80'u32) # CSAR0
  writeMem(ctx, 0x1000_0084'u32, 4, 0x000F0001'u32) # CSMR0
  writeMem(ctx, 0x1000_008A'u32, 2, 0x3D80'u32) # CSCR0
  let csar0 = readMem(ctx, 0x1000_0080'u32, 2)
  let csmr0 = readMem(ctx, 0x1000_0084'u32, 4)
  let cscr0 = readMem(ctx, 0x1000_008A'u32, 2)
  check(csar0 == 0xFF80'u32 and csmr0 == 0x000F0001'u32 and cscr0 == 0x3D80'u32,
        "SIM: CSAR0, CSMR0, CSCR0 write and read-back")

  # DRAM controller: DCR (16-bit), DACR0 (32-bit), DMR0 (32-bit)
  writeMem(ctx, 0x1000_0100'u32, 2, 0x8246'u32)
  writeMem(ctx, 0x1000_0108'u32, 4, 0x00001324'u32)
  writeMem(ctx, 0x1000_010C'u32, 4, 0x01FC0001'u32)
  let dcr = readMem(ctx, 0x1000_0100'u32, 2)
  let dacr0 = readMem(ctx, 0x1000_0108'u32, 4)
  let dmr0 = readMem(ctx, 0x1000_010C'u32, 4)
  check(dcr == 0x8246'u32 and dacr0 == 0x00001324'u32 and dmr0 == 0x01FC0001'u32,
        "SIM: DRAM controller DCR, DACR0, DMR0 write and read-back")

  # Parallel port A: PADDR (16-bit), PADAT (16-bit)
  writeMem(ctx, 0x1000_0244'u32, 2, 0xFFFF'u32)
  let paddr = readMem(ctx, 0x1000_0244'u32, 2)
  check(paddr == 0xFFFF'u32, "SIM: PADDR write and read-back")

  # PADAT bit 9 strap: bit 9 (0x0200) is protected
  writeMem(ctx, 0x1000_0248'u32, 2, 0xFDFF'u32) # try writing with bit 9 clear
  let padat1 = readMem(ctx, 0x1000_0248'u32, 2)
  check((padat1 and 0x0200'u32) == 0'u32, "SIM: PADAT write normal bits")

  writeMem(ctx, 0x1000_0248'u32, 2, 0xFFFF'u32) # try writing 1 to bit 9 (protected)
  let padat2 = readMem(ctx, 0x1000_0248'u32, 2)
  check((padat2 and 0x0200'u32) == 0'u32, "SIM: PADAT bit 9 strap is read-only")

  # ColdFire model strap: UIPCR at MBAR+0x1D0 returns 0x0E and is read-only
  let uipcr = readMem(ctx, 0x1000_01D0'u32, 1)
  check(uipcr == 0x0E'u32, "SIM: UIPCR returns 0x0E model strap", $uipcr, "0x0E")

  writeMem(ctx, 0x1000_01D0'u32, 1, 0xFF'u32)
  let uipcrAfter = readMem(ctx, 0x1000_01D0'u32, 1)
  check(uipcrAfter == 0x0E'u32, "SIM: UIPCR strap is read-only")

  cf_destroy(ctx)

# ===========================================================================
# Block 2: 2-Tier Interrupt Controller (INTC)
# ===========================================================================

block:
  let ctx = freshContext()
  ctx.mbar = 0x1000_0001'u32
  let sim = ensureSim(ctx)
  let intc = addr sim.intc

  # Write ICR0 (internal source 0): Level 4, IP = 2 (0x12)
  writeMem(ctx, 0x1000_004C'u32, 1, 0x12'u32)
  let icr0 = readMem(ctx, 0x1000_004C'u32, 1)
  check(icr0 == 0x12'u32, "INTC: ICR0 write and read-back", $icr0, "0x12")

  # Write ICR1 (Timer 0): Level 6, IP = 1 (0x19)
  writeMem(ctx, 0x1000_004D'u32, 1, 0x19'u32)
  let icr1 = readMem(ctx, 0x1000_004D'u32, 1)
  check(icr1 == 0x19'u32, "INTC: ICR1 write and read-back", $icr1, "0x19")

  # Assert internal source 0
  setInternalVector(intc, 0, 0x50'u8)
  setInternalPending(intc, 0, true)

  check(ctx.irqLevel == 4 and ctx.irqVector == 0x50'u8,
        "INTC: Source 0 asserts IRQ level 4 with vector 0x50")

  # Assert internal source 1 (Timer 0 at Level 6): higher level wins
  setInternalVector(intc, 1, 0x60'u8)
  setInternalPending(intc, 1, true)

  check(ctx.irqLevel == 6 and ctx.irqVector == 0x60'u8,
        "INTC: Higher level (6) preempts lower level (4)")

  # Deassert source 1: level falls back to level 4
  setInternalPending(intc, 1, false)
  check(ctx.irqLevel == 4 and ctx.irqVector == 0x50'u8,
        "INTC: Deasserting higher source falls back to level 4")

  # Deassert source 0: IRQ drops to 0
  setInternalPending(intc, 0, false)
  check(ctx.irqLevel == 0, "INTC: Deasserting all sources drops IRQ to 0")

  # Test within-level arbitration:
  # Source 2: Level 5, IP = 1 (rank 3)
  writeMem(ctx, 0x1000_004E'u32, 1, 0x15'u32) # Level 5, IP = 1
  setInternalVector(intc, 2, 0x51'u8)
  setInternalPending(intc, 2, true)

  # Source 3: Level 5, IP = 2 (rank 1, higher priority than IP=1)
  writeMem(ctx, 0x1000_004F'u32, 1, 0x16'u32) # Level 5, IP = 2
  setInternalVector(intc, 3, 0x52'u8)
  setInternalPending(intc, 3, true)

  check(ctx.irqLevel == 5 and ctx.irqVector == 0x52'u8,
        "INTC: Within same level, IP=2 (rank 1) wins over IP=1 (rank 3)")

  # Autovectoring via AVR: set AVR bit for Level 5 (bit 5 = 0x20)
  writeMem(ctx, 0x1000_004B'u32, 1, 0x20'u32) # AVR
  check(ctx.irqAutovector == true, "INTC: AVR enables autovectoring for Level 5")

  setInternalPending(intc, 2, false)
  setInternalPending(intc, 3, false)
  cf_destroy(ctx)

# ===========================================================================
# Block 3: Timers 0 & 1
# ===========================================================================

block:
  let ctx = freshContext()
  ctx.mbar = 0x1000_0001'u32
  let sim = ensureSim(ctx)

  # Configure Timer 0 ICR1: Level 6, autovector
  writeMem(ctx, 0x1000_004D'u32, 1, 0x98'u32) # ICR1: AVN=1, Level=6

  # Timer 0 registers:
  # TRR0 = 10 (reference)
  writeMem(ctx, 0x1000_0144'u32, 2, 10'u32) # TRR0

  # TMR0: RST=1 (enable), ORI=1 (interrupt enable), FRR=1 (restart), prescaler=0
  writeMem(ctx, 0x1000_0140'u32, 2, 0x0019'u32) # TMR0

  # Advance clock by 5 cycles: TCN should be 5
  advanceTimers(sim, 5)
  let tcn5 = readMem(ctx, 0x1000_014C'u32, 2)
  check(tcn5 == 5'u32, "Timer0: TCN counts up to 5", $tcn5, "5")
  check(ctx.irqLevel == 0, "Timer0: No interrupt before reference match")

  # Advance clock by 6 more cycles (total 11): reaches TRR (10), sets TER bit 1, resets TCN
  advanceTimers(sim, 6)
  let ter = readMem(ctx, 0x1000_0151'u32, 1)
  check((ter and 0x02'u32) != 0'u32, "Timer0: TER bit 1 (REF) is set on match")
  check(ctx.irqLevel == 6, "Timer0: Interrupt asserted to CPU core at level 6")

  # Write-1-to-clear TER bit 1
  writeMem(ctx, 0x1000_0151'u32, 1, 0x02'u32)
  let terCleared = readMem(ctx, 0x1000_0151'u32, 1)
  check((terCleared and 0x02'u32) == 0'u32, "Timer0: TER bit 1 cleared by writing 1")
  check(ctx.irqLevel == 0, "Timer0: Interrupt deasserts after clearing TER")

  cf_destroy(ctx)

# ===========================================================================
# Block 4: DUART Channel A (UART0)
# ===========================================================================

block:
  let ctx = freshContext()
  ctx.mbar = 0x1000_0001'u32
  let sim = ensureSim(ctx)

  # Configure UART0 ICR4: Level 5
  writeMem(ctx, 0x1000_0050'u32, 1, 0x14'u32) # ICR4: Level 5

  # Initial USR status
  let usr0 = readMem(ctx, 0x1000_01C4'u32, 1)
  check((usr0 and 0x08'u32) != 0'u32, "UART0: USR TxEmp set initially")

  # UMR pointer toggling: write UMR1, then write UMR2
  writeMem(ctx, 0x1000_01C0'u32, 1, 0x13'u32) # UMR1
  writeMem(ctx, 0x1000_01C0'u32, 1, 0x07'u32) # UMR2

  # Reset UMR pointer with command 0x10
  writeMem(ctx, 0x1000_01C8'u32, 1, 0x10'u32) # UCR: reset MR pointer
  let umr1Read = readMem(ctx, 0x1000_01C0'u32, 1)
  let umr2Read = readMem(ctx, 0x1000_01C0'u32, 1)
  check(umr1Read == 0x13'u32 and umr2Read == 0x07'u32,
        "UART0: UMR1 and UMR2 written and read back sequentially")

  # Enable receiver and transmitter (UCR = 0x05)
  writeMem(ctx, 0x1000_01C8'u32, 1, 0x05'u32) # Tx enable, Rx enable

  # Enable Rx interrupt in UIMR (bit 1 = 0x02)
  writeMem(ctx, 0x1000_01D4'u32, 1, 0x02'u32)

  # Set UIVR vector to 0x42
  writeMem(ctx, 0x1000_01F0'u32, 1, 0x42'u32)

  # Receive byte 0xAA into UART0
  let rxRes = uartReceive(sim, 0, 0xAA'u8)
  check(rxRes == 0, "UART0: receive byte succeeds")
  let usr1 = readMem(ctx, 0x1000_01C4'u32, 1)
  check((usr1 and 0x01'u32) != 0'u32, "UART0: USR RxRdy set after byte received")
  check(ctx.irqLevel == 5 and ctx.irqVector == 0x42'u8,
        "UART0: Rx interrupt asserted with vector 0x42")

  # Read byte from URB (MBAR+0x1CC)
  let rxByte = readMem(ctx, 0x1000_01CC'u32, 1)
  check(rxByte == 0xAA'u32, "UART0: Read byte from URB matches 0xAA", $rxByte, "0xAA")
  check(ctx.irqLevel == 0, "UART0: IRQ deasserted after FIFO emptied")

  # Test Tx callback
  var transmittedByte: uint8 = 0
  var transmittedChannel: cint = -1
  proc testMidiOut(user: pointer; channel: cint; byte: uint8) {.cdecl.} =
    transmittedChannel = channel
    transmittedByte = byte

  setMidiOut(sim, testMidiOut, nil)
  writeMem(ctx, 0x1000_01CC'u32, 1, 0x90'u32) # Write UTB
  check(transmittedChannel == 0, "UART0: Transmitted channel is 0")
  check(transmittedByte == 0x90'u8, "UART0: Transmitted byte reached callback",
        $transmittedByte, "0x90")

  cf_destroy(ctx)

# ===========================================================================
# Block 5: I2C / M-Bus Controller
# ===========================================================================

type MockI2c = ref object of I2cSlave
  startedAddr: uint8
  startedRead: bool
  writtenBytes: seq[uint8]
  readBytes: seq[uint8]
  stopped: bool

method start(s: MockI2c; addr7: uint8; read: bool): bool =
  s.startedAddr = addr7
  s.startedRead = read
  true

method write(s: MockI2c; byte: uint8): bool =
  s.writtenBytes.add(byte)
  true

method read(s: MockI2c): uint8 =
  if s.readBytes.len > 0:
    result = s.readBytes[0]
    s.readBytes.delete(0)
  else:
    return 0xFF'u8

method stop(s: MockI2c) =
  s.stopped = true

block:
  let ctx = freshContext()
  ctx.mbar = 0x1000_0001'u32
  let sim = ensureSim(ctx)

  let mock = MockI2c(writtenBytes: @[], readBytes: @[0x42'u8])
  setI2cSlave(sim, mock)

  # Configure ICR3 (M-Bus): Level 3
  writeMem(ctx, 0x1000_004F'u32, 1, 0x0C'u32) # ICR3: Level 3

  # Enable M-Bus and interrupt (MBCR = MEN | MIEN = 0xC0)
  writeMem(ctx, 0x1000_0288'u32, 1, 0xC0'u32)

  # Master START (set MSTA = 0x20 in MBCR -> 0xE0)
  writeMem(ctx, 0x1000_0288'u32, 1, 0xE0'u32)
  let mbsr1 = readMem(ctx, 0x1000_028C'u32, 1)
  check((mbsr1 and 0x20'u32) != 0'u32, "M-Bus: MBSR MBB (bus busy) set after START")

  # Transmit address 0x38 (0x70 write) via MBDR (0x290)
  writeMem(ctx, 0x1000_0290'u32, 1, 0x70'u32)
  check(mock.startedAddr == 0x38'u8 and mock.startedRead == false,
        "M-Bus: START condition reached slave with 7-bit addr 0x38")
  check(ctx.irqLevel == 3, "M-Bus: Interrupt asserted after transfer")

  # Clear interrupt in MBSR (write 0 to MIF bit 1)
  writeMem(ctx, 0x1000_028C'u32, 1, 0x00'u32)
  check(ctx.irqLevel == 0, "M-Bus: Interrupt cleared via MBSR write")

  # Transmit data byte 0x55
  writeMem(ctx, 0x1000_0290'u32, 1, 0x55'u32)
  check(mock.writtenBytes == @[0x55'u8], "M-Bus: Data byte 0x55 reached slave")

  # Master STOP (clear MSTA bit in MBCR)
  writeMem(ctx, 0x1000_0288'u32, 1, 0xC0'u32)
  check(mock.stopped == true, "M-Bus: STOP condition reached slave")

  cf_destroy(ctx)

# ===========================================================================
# Block 6: Access Size Enforcement & Unmapped Space
# ===========================================================================

block:
  let ctx = freshContext()
  ctx.mbar = 0x1000_0001'u32
  let sim = ensureSim(ctx)

  var st: Mcf5407BusStatus

  # SIM registers allow byte, word, and longword accesses
  discard simRead(sim, 0x000'u32, 1, st)
  check(st == Mcf5407BusStatus.busOk, "MBAR: 1-byte read on SIM register accepted")

  discard simRead(sim, 0x080'u32, 2, st)
  check(st == Mcf5407BusStatus.busOk, "MBAR: 2-byte read on CSAR0 accepted")

  discard simRead(sim, 0x084'u32, 4, st)
  check(st == Mcf5407BusStatus.busOk, "MBAR: 4-byte read on CSMR0 accepted")

  # UART registers require BYTE accesses only
  discard simRead(sim, 0x1C0'u32, 2, st)
  check(st == Mcf5407BusStatus.busSizeIllegal,
        "MBAR: 2-byte read on UART register rejected with busSizeIllegal")

  discard simRead(sim, 0x1C0'u32, 4, st)
  check(st == Mcf5407BusStatus.busSizeIllegal,
        "MBAR: 4-byte read on UART register rejected with busSizeIllegal")

  simWrite(sim, 0x1C0'u32, 2, 0x1234'u32, st)
  check(st == Mcf5407BusStatus.busSizeIllegal,
        "MBAR: 2-byte write on UART register rejected with busSizeIllegal")

  # M-Bus registers require BYTE accesses only
  discard simRead(sim, 0x280'u32, 2, st)
  check(st == Mcf5407BusStatus.busSizeIllegal,
        "MBAR: 2-byte read on M-Bus register rejected with busSizeIllegal")

  # Accesses beyond 0x3FF are unmapped
  discard simRead(sim, 0x400'u32, 1, st)
  check(st == Mcf5407BusStatus.busUnmapped,
        "MBAR: Read at offset 0x400 rejected with busUnmapped")

  simWrite(sim, 0x400'u32, 1, 0xFF'u32, st)
  check(st == Mcf5407BusStatus.busUnmapped,
        "MBAR: Write at offset 0x400 rejected with busUnmapped")

  cf_destroy(ctx)

# ---------------------------------------------------------------------------
# Results summary
# ---------------------------------------------------------------------------

if failures.len > 0:
  echo ""
  echo "t_peripherals: ", failures.len, " of ", failures.len + passCount,
      " cases failed"
  quit(1)
else:
  echo ""
  echo "t_peripherals: ", passCount, " cases passed"
