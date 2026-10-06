## `uart` - MCF5407 DUART Channel A module.
##
## Motorola MCF5407 User's Manual Chapter 14.
## Registers (accessed as bytes):
##   +0x00 UMR1/UMR2: Mode registers
##   +0x04 USR (read) / UCSR (write): Status / Clock Select
##   +0x08 UCR (write): Command register
##   +0x0C URB (read) / UTB (write): Receiver / Transmitter buffer
##   +0x10 UIPCR (read) / UACR (write): Input Port Change / Auxiliary Control
##   +0x14 UISR (read) / UIMR (write): Interrupt Status / Interrupt Mask
##   +0x18 UBG1: Baud rate prescale MSB
##   +0x1C UBG2: Baud rate prescale LSB
##   +0x30 UIVR: Interrupt Vector Register (reset $0F)
##   +0x34 UIP: Input Port
##   +0x38 UOP1: Output Port Bit Set
##   +0x3C UOP0: Output Port Bit Reset

import coldfire/intc

const
  usrRb*    = 0x80'u8
  usrFe*    = 0x40'u8
  usrPe*    = 0x20'u8
  usrOe*    = 0x10'u8
  usrTxEmp* = 0x08'u8
  usrTxRdy* = 0x04'u8
  usrFfull* = 0x02'u8
  usrRxRdy* = 0x01'u8

  uisrCos*   = 0x80'u8
  uisrDb*    = 0x04'u8
  uisrRxRdy* = 0x02'u8
  uisrTxRdy* = 0x01'u8

  gUart0Vector* = 0x42'u8
  gUart0InterruptIndex* = 4
  gUart1InterruptIndex* = 5

type
  UartTxFn* = proc(user: pointer; channel: cint; byte: uint8) {.cdecl.}

  UartObj* = object
    channel*: cint
    interruptIndex*: int
    intc*: ptr IntcObj
    txCallback*: UartTxFn
    txUser*: pointer

    umr1*: uint8
    umr2*: uint8
    modeUmr1*: bool
    ucsr*: uint8
    uacr*: uint8
    uimr*: uint8
    ubg1*: uint8
    ubg2*: uint8
    uivr*: uint8

    rxFifo*: array[4, uint8]
    rxCount*: int
    rxHead*: int

    txEnabled*: bool
    rxEnabled*: bool
    txHolding*: uint8
    txHoldingValid*: bool
    interruptAsserted*: bool

  Uart* = ptr UartObj

proc usr*(u: ptr UartObj): uint8 =
  var res = 0'u8
  if u.txEnabled:
    if not u.txHoldingValid:
      res = res or (usrTxEmp or usrTxRdy)
    else:
      res = res or usrTxRdy
  else:
    res = res or usrTxEmp
  if u.rxCount > 0:
    res = res or usrRxRdy
  if u.rxCount >= 4:
    res = res or usrFfull
  res

proc uisr*(u: ptr UartObj): uint8 =
  var res = 0'u8
  if u.rxCount > 0:
    res = res or uisrRxRdy
  if u.txEnabled and not u.txHoldingValid:
    res = res or uisrTxRdy
  res

proc recomputeInterrupt(u: ptr UartObj) =
  let st = uisr(u)
  let asserted = (st and u.uimr) != 0'u8
  if asserted != u.interruptAsserted:
    u.interruptAsserted = asserted
    if not u.intc.isNil:
      setInternalVector(u.intc, u.interruptIndex, u.uivr)
      setInternalPending(u.intc, u.interruptIndex, asserted)

proc reset*(u: ptr UartObj) =
  u.umr1 = 0'u8
  u.umr2 = 0'u8
  u.modeUmr1 = true
  u.ucsr = 0'u8
  u.uacr = 0'u8
  u.uimr = 0'u8
  u.ubg1 = 0'u8
  u.ubg2 = 0'u8
  u.uivr = 0x0F'u8
  u.rxCount = 0
  u.rxHead = 0
  u.txEnabled = false
  u.rxEnabled = false
  u.txHoldingValid = false
  u.interruptAsserted = false
  recomputeInterrupt(u)

proc initUart*(u: ptr UartObj; channel: cint; interruptIndex: int; intc: ptr IntcObj = nil) =
  u.channel = channel
  u.interruptIndex = interruptIndex
  u.intc = intc
  u.txCallback = nil
  u.txUser = nil
  reset(u)
  if not u.intc.isNil:
    setInternalVector(u.intc, u.interruptIndex, u.uivr)

proc setMidiOut*(u: ptr UartObj; fn: UartTxFn; user: pointer) =
  u.txCallback = fn
  u.txUser = user

proc receive*(u: ptr UartObj; byte: uint8): cint =
  if not u.rxEnabled:
    return -2
  if u.rxCount >= 4:
    return -2
  let tail = (u.rxHead + u.rxCount) mod 4
  u.rxFifo[tail] = byte
  u.rxCount += 1
  recomputeInterrupt(u)
  0

proc transmitComplete*(u: ptr UartObj) =
  u.txHoldingValid = false
  recomputeInterrupt(u)

proc command(u: ptr UartObj; cmd: uint8) =
  let rc = (cmd shr 4) and 0x07'u8
  case rc
  of 1: # Reset MR pointer to MR1
    u.modeUmr1 = true
  of 2: # Reset receiver
    u.rxEnabled = false
    u.rxCount = 0
    u.rxHead = 0
  of 3: # Reset transmitter
    u.txEnabled = false
    u.txHoldingValid = false
  of 4: # Reset error status
    discard
  of 5: # Reset break change interrupt
    discard
  else:
    discard

  let txCmd = (cmd shr 2) and 0x03'u8
  case txCmd
  of 1: u.txEnabled = true
  of 2: u.txEnabled = false
  else: discard

  let rxCmd = cmd and 0x03'u8
  case rxCmd
  of 1: u.rxEnabled = true
  of 2: u.rxEnabled = false
  else: discard

  recomputeInterrupt(u)

proc readByte*(u: ptr UartObj; offset: uint32): uint8 =
  case offset
  of 0x00'u32:
    if u.modeUmr1:
      u.modeUmr1 = false
      u.umr1
    else:
      u.umr2
  of 0x04'u32:
    usr(u)
  of 0x0C'u32:
    if u.rxCount > 0:
      let byte = u.rxFifo[u.rxHead]
      u.rxHead = (u.rxHead + 1) mod 4
      u.rxCount -= 1
      recomputeInterrupt(u)
      byte
    else:
      0'u8
  of 0x10'u32:
    0x0E'u8 # ColdFire model strap bits
  of 0x14'u32:
    uisr(u)
  of 0x18'u32:
    u.ubg1
  of 0x1C'u32:
    u.ubg2
  of 0x30'u32:
    u.uivr
  of 0x34'u32:
    0xFF'u8 # Input port
  else:
    0'u8

proc writeByte*(u: ptr UartObj; offset: uint32; val: uint8) =
  case offset
  of 0x00'u32:
    if u.modeUmr1:
      u.umr1 = val
      u.modeUmr1 = false
    else:
      u.umr2 = val
  of 0x04'u32:
    u.ucsr = val
  of 0x08'u32:
    command(u, val)
  of 0x0C'u32: # UTB (Transmitter buffer)
    if u.txEnabled:
      u.txHolding = val
      u.txHoldingValid = true
      if not u.txCallback.isNil:
        u.txCallback(u.txUser, u.channel, val)
        u.txHoldingValid = false
      recomputeInterrupt(u)
  of 0x10'u32:
    u.uacr = val
  of 0x14'u32:
    u.uimr = val
    recomputeInterrupt(u)
  of 0x18'u32:
    u.ubg1 = val
  of 0x1C'u32:
    u.ubg2 = val
  of 0x30'u32:
    u.uivr = val
    if not u.intc.isNil and u.interruptAsserted:
      setInternalVector(u.intc, u.interruptIndex, u.uivr)
  of 0x38'u32, 0x3C'u32:
    discard
  else:
    discard
