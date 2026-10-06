## `sim` - MCF5407 System Integration Module and on-chip peripheral subsystem.
##
## Coordinates on-chip peripherals mapped within the 4-Kbyte MBAR window:
##   MBAR + 0x000..0x03F: SIM configuration and control registers
##   MBAR + 0x040..0x05F: 2-Tier Interrupt Controller
##   MBAR + 0x080..0x0DF: Chip-Select Module (CSAR0-7, CSMR0-7, CSCR0-7)
##   MBAR + 0x100..0x13F: DRAM Controller (DCR, DACR0/1, DMR0/1)
##   MBAR + 0x140..0x17F: General Purpose Timer 0
##   MBAR + 0x180..0x1BF: General Purpose Timer 1
##   MBAR + 0x1C0..0x1FF: UART 0 (DUART Channel A)
##   MBAR + 0x200..0x23F: UART 1
##   MBAR + 0x240..0x27F: Parallel Port (PADDR, PADAT)
##   MBAR + 0x280..0x2BF: I2C / M-Bus Controller

import coldfire/decode_types
import coldfire/intc
import coldfire/timer
import coldfire/uart
import coldfire/mbus

const
  simSpaceSize* = 0x400

type
  CfPortAReadFn* = proc(user: pointer): uint16 {.cdecl.}

  SimObj* = object
    ctx*: pointer
    intc*: IntcObj
    timer0*: TimerObj
    timer1*: TimerObj
    uart0*: UartObj
    uart1*: UartObj
    mbus*: MBusObj
    portAHook*: CfPortAReadFn
    portAUser*: pointer
    engineStrap*: bool
    space*: array[simSpaceSize, uint8]
    writeProtect*: array[simSpaceSize, uint8]

  Sim* = ptr SimObj

proc registerRange(sim: Sim; offset: uint32; length: int; protect: uint8 = 0'u8) =
  for i in 0 ..< length:
    let idx = int(offset) + i
    if idx < simSpaceSize:
      sim.writeProtect[idx] = protect

proc initRegisters(sim: Sim) =
  for i in 0 ..< simSpaceSize:
    sim.space[i] = 0'u8
    sim.writeProtect[i] = 0xFF'u8

  # SIM registers
  sim.registerRange(0x000'u32, 4) # RSR, SYPCR, SWIVR, SWSR
  sim.space[0x000] = 0x80'u8      # RSR HRST=1
  sim.space[0x002] = 0x0F'u8      # SWIVR reset $0F

  sim.registerRange(0x004'u32, 2) # PAR
  sim.registerRange(0x006'u32, 1) # IRQPAR
  sim.registerRange(0x008'u32, 1) # PLLCR
  sim.registerRange(0x00C'u32, 1) # MPARK

  # Chip selects CS0..CS7 (CSARn, CSMRn, CSCRn)
  for cs in 0 .. 7:
    let base = 0x080'u32 + uint32(cs * 12)
    sim.registerRange(base, 2)       # CSARn
    sim.registerRange(base + 4, 4)   # CSMRn
    sim.registerRange(base + 10, 2)  # CSCRn

  # DRAM controller
  sim.registerRange(0x100'u32, 2) # DCR
  sim.registerRange(0x108'u32, 4) # DACR0
  sim.registerRange(0x10C'u32, 4) # DMR0
  sim.registerRange(0x110'u32, 4) # DACR1
  sim.registerRange(0x114'u32, 4) # DMR1

  # Model strap (UIPCR at 0x1D0)
  sim.space[0x1D0] = 0x0E'u8
  sim.writeProtect[0x1D0] = 0xFF'u8

  # Parallel port
  sim.registerRange(0x244'u32, 2) # PADDR
  sim.registerRange(0x248'u32, 2) # PADAT
  # PADAT bit 9 (0x0200) is an input strap: byte 0x248 bit 1 is protected
  sim.writeProtect[0x248] = 0x02'u8

proc reset*(sim: Sim) =
  sim.initRegisters()
  if sim.engineStrap:
    sim.space[0x1D0] = sim.space[0x1D0] or 0x01'u8
  reset(addr sim.intc)
  reset(addr sim.timer0)
  reset(addr sim.timer1)
  reset(addr sim.uart0)
  reset(addr sim.uart1)
  reset(addr sim.mbus)

proc newSim*(ctx: MCF5407Ctx): Sim =
  result = create(SimObj)
  result.ctx = cast[pointer](ctx)
  result.portAHook = nil
  result.portAUser = nil
  result.engineStrap = false
  initIntc(addr result.intc, cast[pointer](ctx))
  initTimer(addr result.timer0, 1, addr result.intc)
  initTimer(addr result.timer1, 2, addr result.intc)
  initUart(addr result.uart0, 0, gUart0InterruptIndex, addr result.intc)
  initUart(addr result.uart1, 1, gUart1InterruptIndex, addr result.intc)
  initMBus(addr result.mbus, addr result.intc)
  reset(result)

proc ensureSim*(ctx: MCF5407Ctx): Sim =
  if ctx.sim.isNil:
    let s = newSim(ctx)
    ctx.sim = cast[pointer](s)
    s
  else:
    cast[Sim](ctx.sim)

proc freeSim*(ctx: MCF5407Ctx) =
  if not ctx.sim.isNil:
    let s = cast[Sim](ctx.sim)
    dealloc(s)
    ctx.sim = nil

proc resetSim*(ctx: MCF5407Ctx) =
  if not ctx.sim.isNil:
    reset(cast[Sim](ctx.sim))

proc readByteInternal(sim: Sim; offset: uint32): uint8 =
  if offset == irqparOffset or offset == avrOffset or
     (offset >= icrBase and offset < icrBase + uint32(icrCount)):
    readRegister(addr sim.intc, offset)
  elif offset >= 0x140'u32 and offset <= 0x153'u32:
    readByte(addr sim.timer0, offset - 0x140'u32)
  elif offset >= 0x180'u32 and offset <= 0x193'u32:
    readByte(addr sim.timer1, offset - 0x180'u32)
  elif offset == 0x1D0'u32:
    let base = readByte(addr sim.uart0, offset - 0x1C0'u32)
    if sim.engineStrap: (base or 0x01'u8) else: (base and not 0x01'u8)
  elif offset >= 0x1C0'u32 and offset < 0x200'u32:
    readByte(addr sim.uart0, offset - 0x1C0'u32)
  elif offset >= 0x200'u32 and offset < 0x240'u32:
    readByte(addr sim.uart1, offset - 0x200'u32)
  elif (offset == 0x248'u32 or offset == 0x249'u32) and not sim.portAHook.isNil:
    let rows = sim.portAHook(sim.portAUser) and not 0x0200'u16
    if offset == 0x248'u32:
      uint8((rows shr 8) and 0xFF'u16)
    else:
      uint8(rows and 0xFF'u16)
  elif offset >= 0x280'u32 and offset <= 0x293'u32:
    readByte(addr sim.mbus, offset)
  elif int(offset) < simSpaceSize:
    sim.space[int(offset)]
  else:
    0'u8

proc writeByteInternal(sim: Sim; offset: uint32; val: uint8) =
  if offset == irqparOffset or offset == avrOffset or
     (offset >= icrBase and offset < icrBase + uint32(icrCount)):
    writeRegister(addr sim.intc, offset, val)
  elif offset >= 0x140'u32 and offset <= 0x153'u32:
    writeByte(addr sim.timer0, offset - 0x140'u32, val)
  elif offset >= 0x180'u32 and offset <= 0x193'u32:
    writeByte(addr sim.timer1, offset - 0x180'u32, val)
  elif offset >= 0x1C0'u32 and offset < 0x200'u32:
    writeByte(addr sim.uart0, offset - 0x1C0'u32, val)
  elif offset >= 0x200'u32 and offset < 0x240'u32:
    writeByte(addr sim.uart1, offset - 0x200'u32, val)
  elif offset >= 0x280'u32 and offset <= 0x293'u32:
    writeByte(addr sim.mbus, offset, val)
  elif int(offset) < simSpaceSize:
    let prot = sim.writeProtect[int(offset)]
    sim.space[int(offset)] = (sim.space[int(offset)] and prot) or (val and not prot)

proc isIntcOwned(offset: uint32): bool =
  offset == irqparOffset or offset == avrOffset or
     (offset >= icrBase and offset < icrBase + uint32(icrCount))

proc isByteAccessOnly(offset: uint32; size: uint8): bool =
  for b in 0 ..< int(size):
    let targetAddr = offset + uint32(b)
    if isIntcOwned(targetAddr):
      return true
    if (targetAddr >= 0x1C0'u32 and targetAddr < 0x240'u32) or
       (targetAddr >= 0x280'u32 and targetAddr <= 0x293'u32):
      return true
  false

proc simRead*(sim: Sim; offset: uint32; size: uint8;
              st: var Mcf5407BusStatus): uint32 =
  st = Mcf5407BusStatus.busOk
  if offset + uint32(size) > uint32(simSpaceSize):
    st = Mcf5407BusStatus.busUnmapped
    return 0'u32

  if size != 1 and size != 2 and size != 4:
    st = Mcf5407BusStatus.busSizeIllegal
    return 0'u32

  if isByteAccessOnly(offset, size) and size != 1:
    st = Mcf5407BusStatus.busSizeIllegal
    return 0'u32

  var res = 0'u32
  for b in 0 ..< int(size):
    res = (res shl 8) or uint32(readByteInternal(sim, offset + uint32(b)))
  res

proc simWrite*(sim: Sim; offset: uint32; size: uint8; value: uint32;
               st: var Mcf5407BusStatus) =
  st = Mcf5407BusStatus.busOk
  if offset + uint32(size) > uint32(simSpaceSize):
    st = Mcf5407BusStatus.busUnmapped
    return

  if size != 1 and size != 2 and size != 4:
    st = Mcf5407BusStatus.busSizeIllegal
    return

  if isByteAccessOnly(offset, size) and size != 1:
    st = Mcf5407BusStatus.busSizeIllegal
    return

  for b in 0 ..< int(size):
    let shift = (int(size) - 1 - b) * 8
    let byteVal = uint8((value shr shift) and 0xFF'u32)
    writeByteInternal(sim, offset + uint32(b), byteVal)

proc advanceTimers*(sim: Sim; clocks: uint32) =
  advance(addr sim.timer0, clocks)
  advance(addr sim.timer1, clocks)

proc uartReceive*(sim: Sim; channel: int; byte: uint8): cint =
  if channel == 0:
    receive(addr sim.uart0, byte)
  elif channel == 1:
    receive(addr sim.uart1, byte)
  else:
    -1

proc setMidiOut*(sim: Sim; fn: UartTxFn; user: pointer) =
  setMidiOut(addr sim.uart0, fn, user)

proc setExternalPending*(sim: Sim; pin: int; asserted: bool) =
  setExternalPending(addr sim.intc, pin, asserted)

proc setExternalVector*(sim: Sim; pin: int; vector: uint8) =
  setExternalVector(addr sim.intc, pin, vector)

proc setI2cSlave*(sim: Sim; slave: I2cSlave) =
  setSlave(addr sim.mbus, slave)

# ===========================================================================
# Canonical On-Chip Peripheral C ABI Exports
# ===========================================================================

proc cf_uart_rx_byte*(ctx: MCF5407Ctx; channel: cint; byte: uint8): cint
    {.exportc: "cf_uart_rx_byte", cdecl, dynlib.} =
  if ctx.isNil or channel < 0 or channel > 1:
    return -1
  let s = ensureSim(ctx)
  let u = if channel == 0: addr s.uart0 else: addr s.uart1
  receive(u, byte)

proc cf_uart_set_tx_handler*(ctx: MCF5407Ctx; channel: cint; fn: UartTxFn;
                             user: pointer): cint
    {.exportc: "cf_uart_set_tx_handler", cdecl, dynlib.} =
  if ctx.isNil or channel < 0 or channel > 1:
    return -1
  let s = ensureSim(ctx)
  let u = if channel == 0: addr s.uart0 else: addr s.uart1
  u.txCallback = fn
  u.txUser = user
  0

proc cf_uart_get_usr*(ctx: MCF5407Ctx; channel: cint): uint8
    {.exportc: "cf_uart_get_usr", cdecl, dynlib.} =
  if ctx.isNil or channel < 0 or channel > 1:
    return 0'u8
  let s = ensureSim(ctx)
  let u = if channel == 0: addr s.uart0 else: addr s.uart1
  usr(u)

proc cf_timer_tick*(ctx: MCF5407Ctx; cycles: uint32)
    {.exportc: "cf_timer_tick", cdecl, dynlib.} =
  if ctx.isNil:
    return
  advanceTimers(ensureSim(ctx), cycles)

proc cf_set_irq_pin*(ctx: MCF5407Ctx; pin: cint; asserted: cint)
    {.exportc: "cf_set_irq_pin", cdecl, dynlib.} =
  if ctx.isNil or pin < 0 or pin > 3:
    return
  let s = ensureSim(ctx)
  setExternalPending(addr s.intc, int(pin), asserted != 0)

proc cf_intc_get_presented_level*(ctx: MCF5407Ctx): cint
    {.exportc: "cf_intc_get_presented_level", cdecl, dynlib.} =
  if ctx.isNil:
    return 0
  let s = ensureSim(ctx)
  cint(s.intc.lastLevel)

proc cf_intc_get_presented_vector*(ctx: MCF5407Ctx): uint8
    {.exportc: "cf_intc_get_presented_vector", cdecl, dynlib.} =
  if ctx.isNil:
    return 0'u8
  let s = ensureSim(ctx)
  s.intc.lastVector

proc cf_intc_get_presented_autovector*(ctx: MCF5407Ctx): cint
    {.exportc: "cf_intc_get_presented_autovector", cdecl, dynlib.} =
  if ctx.isNil:
    return 0
  let s = ensureSim(ctx)
  if s.intc.lastAutovector: cint(1) else: cint(0)

proc cf_mbar_read*(ctx: MCF5407Ctx; offset: uint32; size: cint;
                   status: ptr Mcf5407BusStatus): uint32
    {.exportc: "cf_mbar_read", cdecl, dynlib.} =
  if ctx.isNil:
    if not status.isNil:
      status[] = Mcf5407BusStatus.busFault
    return 0'u32
  var st = Mcf5407BusStatus.busOk
  result = simRead(ensureSim(ctx), offset, uint8(size), st)
  if not status.isNil:
    status[] = st

proc cf_mbar_write*(ctx: MCF5407Ctx; offset: uint32; size: cint; value: uint32;
                    status: ptr Mcf5407BusStatus)
    {.exportc: "cf_mbar_write", cdecl, dynlib.} =
  if ctx.isNil:
    if not status.isNil:
      status[] = Mcf5407BusStatus.busFault
    return
  var st = Mcf5407BusStatus.busOk
  simWrite(ensureSim(ctx), offset, uint8(size), value, st)
  if not status.isNil:
    status[] = st

proc cf_sim_set_port_a_hook*(ctx: MCF5407Ctx; hook: CfPortAReadFn;
                             user: pointer)
    {.exportc: "cf_sim_set_port_a_hook", cdecl, dynlib.} =
  if ctx.isNil:
    return
  let s = ensureSim(ctx)
  s.portAHook = hook
  s.portAUser = user

proc cf_sim_set_engine_strap*(ctx: MCF5407Ctx; engineStrap: cint)
    {.exportc: "cf_sim_set_engine_strap", cdecl, dynlib.} =
  if ctx.isNil:
    return
  let s = ensureSim(ctx)
  s.engineStrap = (engineStrap != 0)
  if s.engineStrap:
    s.space[0x1D0] = s.space[0x1D0] or 0x01'u8
  else:
    s.space[0x1D0] = s.space[0x1D0] and not 0x01'u8
  s.writeProtect[0x248] = s.writeProtect[0x248] or 0x02'u8
