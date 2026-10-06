## `intc` - the MCF5407 two-tier interrupt controller.
##
## The interrupt controller arbitrates among internal peripheral sources and
## the external interrupt pins, according to MCF5407 User's Manual Chapter 9.
##
## Internal interrupt sources have an Interrupt Control Register (ICR).
## Registers:
##   MBAR + 0x006: IRQPAR (Interrupt Port Assignment Register)
##   MBAR + 0x040: IPR (Interrupt Pending Register, 32-bit)
##   MBAR + 0x044: IMR (Interrupt Mask Register, 32-bit)
##   MBAR + 0x04B: AVR (Autovector Register)
##   MBAR + 0x04C..0x057: ICR0..ICR11
##
## Within-level arbitration order (MCF5407UM Table 9-3):
##   IP = 11 (rank 0, highest)
##   IP = 10 (rank 1)
##   External pin at level (rank 2)
##   IP = 01 (rank 3)
##   IP = 00 (rank 4, lowest)

import coldfire/decode_types

const
  irqparOffset* = 0x006'u32
  avrOffset*    = 0x04B'u32
  icrBase*      = 0x04C'u32
  icrCount*     = 12
  internalSourceCount* = 10

type
  ExternalPin* = enum
    pinIrq7 = 0
    pinIrq5 = 1
    pinIrq3 = 2
    pinIrq1 = 3

  IntcObj* = object
    ctx*: pointer
    irqpar*: uint8
    avr*: uint8
    icr*: array[icrCount, uint8]
    ipr*: uint32
    imr*: uint32
    internalPending*: array[internalSourceCount, bool]
    externalPending*: array[4, bool]
    internalVector*: array[internalSourceCount, uint8]
    externalVector*: array[4, uint8]
    lastLevel*: int
    lastVector*: uint8
    lastAutovector*: bool
    presentedToCore*: bool

  Intc* = ptr IntcObj

proc internalRank(icr: uint8): int =
  let ip = icr and 0x03'u8
  case ip
  of 3'u8: 0
  of 2'u8: 1
  of 1'u8: 3
  else: 4

proc externalLevel(pin: int; irqpar: uint8): int =
  case pin
  of 0: 7
  of 1: (if (irqpar and 0x04'u8) != 0'u8: 4 else: 5)
  of 2: (if (irqpar and 0x02'u8) != 0'u8: 6 else: 3)
  of 3: (if (irqpar and 0x01'u8) != 0'u8: 2 else: 1)
  else: 0

proc presentToCore(ctx: MCF5407Ctx; level: cint; vector: uint8; autovector: bool) =
  if ctx.isNil:
    return
  if level == 7 and ctx.irqLevel != 7:
    ctx.irq7Armed = true
    ctx.irq7Vector = vector
    ctx.irq7Autovector = autovector
  ctx.irqLevel = level
  ctx.irqVector = vector
  ctx.irqAutovector = autovector

proc recomputeAndPresent*(intc: ptr IntcObj) =
  var bestLevel = 0
  var bestRank = 5
  var bestOrder = 0
  var winValid = false
  var winLevel = 0
  var winVector = 0'u8
  var winAutovector = false

  for i in 0 ..< internalSourceCount:
    if not intc.internalPending[i]:
      continue
    let icr = intc.icr[i]
    let level = int((icr shr 2) and 0x07'u8)
    if level == 0:
      continue
    let rank = internalRank(icr)
    if level > bestLevel or
       (level == bestLevel and rank < bestRank) or
       (level == bestLevel and rank == bestRank and i < bestOrder):
      bestLevel = level
      bestRank = rank
      bestOrder = i
      winValid = true
      winLevel = level
      winVector = intc.internalVector[i]
      winAutovector = ((icr and 0x80'u8) != 0'u8) or (((intc.avr shr level) and 1'u8) != 0'u8)

  for p in 0 .. 3:
    if not intc.externalPending[p]:
      continue
    let level = externalLevel(p, intc.irqpar)
    if level == 0:
      continue
    let rank = 2
    let order = p + internalSourceCount
    if level > bestLevel or
       (level == bestLevel and rank < bestRank) or
       (level == bestLevel and rank == bestRank and order < bestOrder):
      bestLevel = level
      bestRank = rank
      bestOrder = order
      winValid = true
      winLevel = level
      winVector = intc.externalVector[p]
      winAutovector = (((intc.avr shr level) and 1'u8) != 0'u8)

  intc.lastLevel = if winValid: winLevel else: 0
  intc.lastVector = if winValid: winVector else: 0'u8
  intc.lastAutovector = if winValid: winAutovector else: false

  if not intc.ctx.isNil:
    let coreCtx = cast[MCF5407Ctx](intc.ctx)
    if winValid:
      intc.presentedToCore = true
      presentToCore(coreCtx, cint(winLevel), winVector, winAutovector)
    elif intc.presentedToCore:
      intc.presentedToCore = false
      presentToCore(coreCtx, 0, 0'u8, false)

proc reset*(intc: ptr IntcObj) =
  intc.irqpar = 0'u8
  intc.avr = 0'u8
  for i in 0 ..< icrCount:
    intc.icr[i] = 0'u8
  intc.ipr = 0'u32
  intc.imr = 0'u32
  for i in 0 ..< internalSourceCount:
    intc.internalPending[i] = false
    intc.internalVector[i] = 0'u8
  for p in 0 .. 3:
    intc.externalPending[p] = false
    intc.externalVector[p] = 0'u8
  intc.lastLevel = 0
  intc.lastVector = 0'u8
  intc.lastAutovector = false
  if intc.presentedToCore:
    intc.presentedToCore = false
    if not intc.ctx.isNil:
      presentToCore(cast[MCF5407Ctx](intc.ctx), 0, 0'u8, false)

proc initIntc*(intc: ptr IntcObj; ctx: pointer) =
  intc.ctx = ctx
  intc.presentedToCore = false
  reset(intc)

proc readRegister*(intc: ptr IntcObj; offset: uint32): uint8 =
  if offset == irqparOffset:
    intc.irqpar
  elif offset == avrOffset:
    intc.avr
  elif offset >= icrBase and offset < icrBase + uint32(icrCount):
    intc.icr[offset - icrBase]
  else:
    0'u8

proc writeRegister*(intc: ptr IntcObj; offset: uint32; value: uint8) =
  if offset == irqparOffset:
    intc.irqpar = value
  elif offset == avrOffset:
    intc.avr = value
  elif offset >= icrBase and offset < icrBase + uint32(icrCount):
    intc.icr[offset - icrBase] = value
  else:
    return
  recomputeAndPresent(intc)

proc setInternalPending*(intc: ptr IntcObj; index: int; asserted: bool) =
  if index >= 0 and index < internalSourceCount:
    intc.internalPending[index] = asserted
    recomputeAndPresent(intc)

proc setExternalPending*(intc: ptr IntcObj; pin: int; asserted: bool) =
  if pin >= 0 and pin < 4:
    intc.externalPending[pin] = asserted
    recomputeAndPresent(intc)

proc setInternalVector*(intc: ptr IntcObj; index: int; vector: uint8) =
  if index >= 0 and index < internalSourceCount:
    intc.internalVector[index] = vector
    recomputeAndPresent(intc)

proc setExternalVector*(intc: ptr IntcObj; pin: int; vector: uint8) =
  if pin >= 0 and pin < 4:
    intc.externalVector[pin] = vector
    recomputeAndPresent(intc)
