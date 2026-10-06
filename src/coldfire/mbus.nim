## `mbus` - MCF5407 I2C / M-Bus controller module.
##
## Motorola MCF5407 User's Manual Chapter 8.
## Registers (accessed as bytes):
##   +0x280 MADR: Address register
##   +0x284 MFDR: Frequency divider register
##   +0x288 MBCR: Control register
##   +0x28C MBSR: Status register
##   +0x290 MBDR: Data I/O register

import coldfire/intc

const
  madrOffset* = 0x280'u32
  mfdrOffset* = 0x284'u32
  mbcrOffset* = 0x288'u32
  mbsrOffset* = 0x28C'u32
  mbdrOffset* = 0x290'u32

  menBit*  = 0x80'u8
  mienBit* = 0x40'u8
  mstaBit* = 0x20'u8
  mtxBit*  = 0x10'u8
  txakBit* = 0x08'u8
  rstaBit* = 0x04'u8

  mcfBit*  = 0x80'u8
  maasBit* = 0x40'u8
  mbbBit*  = 0x20'u8
  malBit*  = 0x10'u8
  srwBit*  = 0x04'u8
  mifBit*  = 0x02'u8
  rxakBit* = 0x01'u8

  gMbusInterruptIndex* = 3

type
  I2cSlave* = ref object of RootObj

method start*(s: I2cSlave; addr7: uint8; read: bool): bool {.base.} = false
method write*(s: I2cSlave; byte: uint8): bool {.base.} = false
method read*(s: I2cSlave): uint8 {.base.} = 0xFF'u8
method stop*(s: I2cSlave) {.base.} = discard

type
  MBusObj* = object
    intc*: ptr IntcObj
    slave*: I2cSlave

    madr*: uint8
    mfdr*: uint8
    mbcr*: uint8
    received*: uint8

    busBusy*: bool
    interrupt*: bool
    notAcknowledged*: bool
    addressPhase*: bool
    interruptAsserted*: bool

  MBus* = ptr MBusObj

proc recomputeInterrupt(m: ptr MBusObj) =
  let asserted = ((m.mbcr and mienBit) != 0'u8) and m.interrupt
  if asserted != m.interruptAsserted:
    m.interruptAsserted = asserted
    if not m.intc.isNil:
      setInternalPending(m.intc, gMbusInterruptIndex, asserted)

proc reset*(m: ptr MBusObj) =
  m.madr = 0'u8
  m.mfdr = 0'u8
  m.mbcr = 0'u8
  m.received = 0'u8
  m.busBusy = false
  m.interrupt = false
  m.notAcknowledged = false
  m.addressPhase = false
  m.interruptAsserted = false
  recomputeInterrupt(m)

proc initMBus*(m: ptr MBusObj; intc: ptr IntcObj = nil; slave: I2cSlave = nil) =
  m.intc = intc
  m.slave = slave
  reset(m)

proc setSlave*(m: ptr MBusObj; slave: I2cSlave) =
  m.slave = slave

proc writeControl(m: ptr MBusObj; val: uint8) =
  let wasMaster = (m.mbcr and mstaBit) != 0'u8
  let isMaster  = (val and mstaBit) != 0'u8
  m.mbcr = val

  if not wasMaster and isMaster:
    m.busBusy = true
    m.addressPhase = true
    return

  if wasMaster and not isMaster:
    m.busBusy = false
    m.addressPhase = false
    if not m.slave.isNil:
      m.slave.stop()

proc transmit(m: ptr MBusObj; val: uint8) =
  if (m.mbcr and mstaBit) == 0'u8:
    return
  if m.addressPhase:
    m.addressPhase = false
    let addr7 = val shr 1
    let isRead = (val and 1'u8) != 0'u8
    m.notAcknowledged = if m.slave.isNil: true else: not m.slave.start(addr7, isRead)
  else:
    m.notAcknowledged = if m.slave.isNil: true else: not m.slave.write(val)
  m.interrupt = true
  recomputeInterrupt(m)

proc receive(m: ptr MBusObj): uint8 =
  let res = m.received
  if (m.mbcr and mstaBit) != 0'u8 and (m.mbcr and mtxBit) == 0'u8:
    m.received = if m.slave.isNil: 0xFF'u8 else: m.slave.read()
    m.interrupt = true
    recomputeInterrupt(m)
  res

proc readByte*(m: ptr MBusObj; offset: uint32): uint8 =
  case offset
  of madrOffset: m.madr
  of mfdrOffset: m.mfdr
  of mbcrOffset: m.mbcr
  of mbsrOffset:
    var res = 0'u8
    if m.busBusy: res = res or mbbBit
    if m.interrupt: res = res or mifBit
    if m.notAcknowledged: res = res or rxakBit
    res
  of mbdrOffset:
    receive(m)
  else:
    0'u8

proc writeByte*(m: ptr MBusObj; offset: uint32; val: uint8) =
  case offset
  of madrOffset:
    m.madr = val
  of mfdrOffset:
    m.mfdr = val
  of mbcrOffset:
    writeControl(m, val)
  of mbsrOffset:
    if (val and mifBit) == 0'u8:
      m.interrupt = false
      recomputeInterrupt(m)
  of mbdrOffset:
    transmit(m, val)
  else:
    discard
