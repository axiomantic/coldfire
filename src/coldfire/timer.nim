## `timer` - MCF5407 general-purpose timer module.
##
## Motorola MCF5407 User's Manual Chapter 13.
## Each timer module has:
##   +0x00 TMR: Mode register (16-bit)
##   +0x04 TRR: Reference register (16-bit)
##   +0x08 TCR: Capture register (16-bit, read-only)
##   +0x0C TCN: Counter register (16-bit)
##   +0x11 TER: Event register (8-bit, write-1-to-clear)

import coldfire/intc

const
  tmrRst* = 0x0001'u16
  tmrFrr* = 0x0008'u16
  tmrOri* = 0x0010'u16
  tmrPrescalerShift* = 8

  terCap* = 0x01'u8
  terRef* = 0x02'u8

  tmrOffset* = 0x00'u32
  trrOffset* = 0x04'u32
  tcrOffset* = 0x08'u32
  tcnOffset* = 0x0C'u32
  terOffset* = 0x11'u32
  timerBlockSize* = 0x12'u32

type
  TimerObj* = object
    interruptIndex*: int
    intc*: ptr IntcObj
    tmr*: uint16
    trr*: uint16
    tcr*: uint16
    tcn*: uint16
    ter*: uint8
    prescaler*: uint32
    interruptAsserted*: bool

  Timer* = ptr TimerObj

proc recomputeInterrupt(t: ptr TimerObj) =
  let asserted = ((t.ter and terRef) != 0'u8) and ((t.tmr and tmrOri) != 0'u16)
  if asserted != t.interruptAsserted:
    t.interruptAsserted = asserted
    if not t.intc.isNil:
      setInternalPending(t.intc, t.interruptIndex, asserted)

proc reset*(t: ptr TimerObj) =
  t.tmr = 0'u16
  t.trr = 0xFFFF'u16
  t.tcr = 0'u16
  t.tcn = 0'u16
  t.ter = 0'u8
  t.prescaler = 0'u32
  recomputeInterrupt(t)

proc initTimer*(t: ptr TimerObj; interruptIndex: int; intc: ptr IntcObj = nil) =
  t.interruptIndex = interruptIndex
  t.intc = intc
  reset(t)

proc writeTmr*(t: ptr TimerObj; val: uint16) =
  t.tmr = val
  if (t.tmr and tmrRst) == 0'u16:
    t.tcn = 0'u16
    t.prescaler = 0'u32
  recomputeInterrupt(t)

proc writeTrr*(t: ptr TimerObj; val: uint16) =
  t.trr = val

proc writeTcn*(t: ptr TimerObj; val: uint16) =
  t.tcn = val

proc writeTer*(t: ptr TimerObj; val: uint8) =
  t.ter = t.ter and not (val and (terRef or terCap))
  recomputeInterrupt(t)

proc readByte*(t: ptr TimerObj; offset: uint32): uint8 =
  case offset
  of tmrOffset: uint8(t.tmr shr 8)
  of tmrOffset + 1: uint8(t.tmr and 0xFF'u16)
  of trrOffset: uint8(t.trr shr 8)
  of trrOffset + 1: uint8(t.trr and 0xFF'u16)
  of tcrOffset: uint8(t.tcr shr 8)
  of tcrOffset + 1: uint8(t.tcr and 0xFF'u16)
  of tcnOffset: uint8(t.tcn shr 8)
  of tcnOffset + 1: uint8(t.tcn and 0xFF'u16)
  of terOffset: t.ter
  else: 0'u8

proc writeByte*(t: ptr TimerObj; offset: uint32; val: uint8) =
  case offset
  of tmrOffset:
    writeTmr(t, (t.tmr and 0x00FF'u16) or (uint16(val) shl 8))
  of tmrOffset + 1:
    writeTmr(t, (t.tmr and 0xFF00'u16) or uint16(val))
  of trrOffset:
    writeTrr(t, (t.trr and 0x00FF'u16) or (uint16(val) shl 8))
  of trrOffset + 1:
    writeTrr(t, (t.trr and 0xFF00'u16) or uint16(val))
  of tcnOffset:
    writeTcn(t, (t.tcn and 0x00FF'u16) or (uint16(val) shl 8))
  of tcnOffset + 1:
    writeTcn(t, (t.tcn and 0xFF00'u16) or uint16(val))
  of terOffset:
    writeTer(t, val)
  else:
    discard

proc tick(t: ptr TimerObj) =
  if t.tcn == t.trr:
    t.ter = t.ter or terRef
    t.tcn = if (t.tmr and tmrFrr) != 0'u16: 0'u16 else: t.tcn + 1'u16
    recomputeInterrupt(t)
  else:
    t.tcn = t.tcn + 1'u16

proc advance*(t: ptr TimerObj; clocks: uint32) =
  if (t.tmr and tmrRst) == 0'u16:
    return
  let divisor = uint32((t.tmr shr tmrPrescalerShift) and 0xFF'u16) + 1'u32
  t.prescaler += clocks
  while t.prescaler >= divisor:
    t.prescaler -= divisor
    tick(t)
