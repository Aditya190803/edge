// WHOOP 4 discovery table. Gen5 wire metadata remains only for legacy transport guards.
import 'package:openstrap_protocol/openstrap_protocol.dart';
import 'signals.dart';

enum TimeAnchor {
  /// The source stamped the reading itself. Every WHOOP record.
  measured,

  /// The instant the sample reached the phone. Approximate, and never to be
  /// written into a column that means "where the beat was".
  arrival,
}

/// The two OBSERVED client delays in the WHOOP 5 bootstrap: 600 ms between the
/// bond completing and notification registration, and 500 ms between the last
/// CCC write and the first command (on a captured link GET_HELLO went out
/// 585 ms after it). The firmware rationale is not documented anywhere, which
/// is exactly why they are per-band values and not a global settle: WHOOP 4's
/// flow is proven without them, and perturbing it for a reason nobody can state
/// is how a working band stops working.
const Duration kGen5PreRegistrationDelay = Duration(milliseconds: 600);
const Duration kGen5PostRegistrationDelay = Duration(milliseconds: 500);

/// The command table for one framed band.
///
/// Every field here was an `if (session.band.isGen5)` in `ble_engine.dart` that
/// chose a VALUE — an opcode, a body, a wire fact. Each is transcribed verbatim
/// from the arm it replaces (`band_registry_test.dart` pins them), and the code
/// around it is now unconditional.
///
/// What is deliberately NOT here: anything that chooses a different SEQUENCE of
/// operations — the gen5 HELLO step, the advertising-name read, the battery-pack
/// follow-up, the deep-buffer unlock, the two INIT state machines, the gen5
/// alarm pre-arm, the historical decoder. Those are behaviour; they stay in the
/// engine where the order can be read top to bottom (ASSUMPTIONS G1-G4 — the
/// `run(BandLink)` move was declined, so there is nowhere else for them to go).
///
/// It is a TABLE, not a policy: no field is computed, and no field decides
/// WHETHER something happens except by being absent ([r10R11Realtime]).
class BandWireCommands {
  /// GET_HELLO and its body. WHOOP 5 does not implement the Harvard opcode.
  final int hello;
  final List<int> helloBody;

  /// GET_ADVERTISING_NAME and its body — a different opcode pair on each
  /// generation, and gen5's takes a revision byte where gen4 takes 0x00.
  final int getAdvertisingName;
  final List<int> getAdvertisingNameBody;

  /// SET_ADVERTISING_NAME. Only the opcode differs; the body
  /// (`[0x01][len][ascii][u32 0]`) is identical on both and stays at the call
  /// site that builds it.
  final int setAdvertisingName;

  /// SEND_R10_R11 (0x3F), the high-rate raw live-stream toggle — or NULL on a
  /// band that does not implement the opcode (a WHOOP 5 console answers
  /// Unknown/Unhandled). Null is what the four live-stream paths read to skip
  /// the toggle; it is an absent command, not a capability claim.
  final int? r10R11Realtime;

  /// Whether ENABLE_OPTICAL_DATA is this band's LIVE optical toggle.
  ///
  /// A wire-semantics fact and a safety boundary, not a preference: on WHOOP 5
  /// the same opcode is the SAVE-to-history toggle, so arming it for a live
  /// stream would write a persistent save-enable that leaves the LEDs on.
  final bool opticalDataIsLiveToggle;

  /// Body of the offload commands (GET_DATA_RANGE, SEND_HISTORICAL_DATA).
  /// gen4 sends a single 0x00; gen5 sends an EMPTY body.
  final List<int> offloadBody;

  const BandWireCommands({
    required this.hello,
    required this.helloBody,
    required this.getAdvertisingName,
    required this.getAdvertisingNameBody,
    required this.setAdvertisingName,
    required this.r10R11Realtime,
    required this.opticalDataIsLiveToggle,
    required this.offloadBody,
  });
}

/// One band the app can discover and connect to.
///
/// The wire format itself stays in `protocol` ([BandProfile] = header length,
/// size-field offset, direction markers; [GattProfile] = the UUID map). This
/// type carries the edge-side facts that live above the codec — discovery and
/// the inner-record field offsets — following the same "it is data, not a
/// branch" pattern rather than inventing a parallel one.
class BandEntry {
  /// Stable identifier. Stamped into `DeviceState.generation` and, downstream,
  /// `device_family` and `decoded_*.source` — so it is a storage key: never
  /// rename a shipped one.
  final String id;

  /// Human label for logs and (later) the pairing UI.
  final String label;

  /// GATT UUID map for this band. NULL for a band that is not a WHOOP-family
  /// six-characteristic link — see the header note.
  final GattProfile? gatt;

  /// Frame envelope profile — header length, size-field offset, header CRC.
  /// NULL means this band sends no envelope at all, which is also what
  /// [isFramed] reports and what the offload engine filters on.
  final BandProfile? wire;

  /// What [TimeAnchor] this band's stored timestamps carry.
  final TimeAnchor timeAnchor;

  final String? _service;

  /// The characteristics a link MUST expose or the connect aborts.
  ///
  /// Defaults to this entry's own four command/notify characteristics, which
  /// is what a WHOOP link genuinely needs. It is a FIELD and not a constant
  /// because demanding four unconditionally is why a second, parallel BLE
  /// stack had to exist at all: a generic HRS device exposes one notify
  /// characteristic and nothing else.
  final List<String>? _requiredCharacteristics;

  /// Offset of the opcode byte within the inner payload
  /// (`[pktType, seq, opcode, body…]`). Framed entries only.
  final int innerOpcodeOffset;

  /// Offset of the record-version byte within a historical record's inner
  /// payload. Framed entries only.
  final int innerVersionOffset;

  /// Offset of the u32-LE record counter within a historical record's inner
  /// payload. Framed entries only.
  final int innerCounterOffset;

  final BandWireCommands? _commands;

  /// This band's command table. Framed entries only — a notify-only sensor has
  /// no command channel at all, which is why this throws rather than answering
  /// with a plausible-looking WHOOP default.
  BandWireCommands get commands => _commands!;

  /// Pause between the bond completing and notification registration, and
  /// between the last CCC write and the first command. [Duration.zero] means
  /// "no pause", which is what every band does unless it has evidence for one.
  final Duration preRegistrationDelay;
  final Duration postRegistrationDelay;

  /// Whether the bootstrap SET_CLOCK is gated on measured drift
  /// (`BootstrapClockGate`) rather than written unconditionally.
  ///
  /// FALSE ON WHOOP 4 ON PURPOSE, and it is not an oversight to be tidied: its
  /// unconditional write is the proven flow, and the WHOOP 5 bootstrap is where
  /// the evidence for gating lives. Flipping it changes a band that works.
  final bool setClockDriftGated;

  /// Whether a burst's declared `expectedPacketCount` is trustworthy enough to
  /// GATE the burst, or is advisory only.
  ///
  /// FALSE ON WHOOP 4 ON PURPOSE. The gap between expected and actual varies
  /// run to run there with no fixed offset, so a hard gate becomes a permanent
  /// stall — 15 validation failures, abort, terminal Stuck — on a band whose
  /// count semantics nothing has pinned. False is also the SAFE default for a
  /// band nobody has measured.
  final bool burstCountGateEnforced;

  /// Whether this band's decoded `console_log` frames are echoed into the
  /// engine log. Debug visibility only — never persisted, never gated on.
  ///
  /// It is per-band because the value of the noise is: WHOOP 5's handshake and
  /// offload are the untested ones, so its console is worth reading. Note that
  /// `protocol` decodes a console frame on BOTH bands, so false here means a
  /// WHOOP 4 that emits one is silently dropped on the floor.
  final bool logsConsoleOutput;

  /// Extra scan-time name match for a band that advertises its name but not
  /// (reliably) its service UUID. Null for a band with no such fallback.
  ///
  /// This is the per-entry replacement for the `name.contains('whoop')`
  /// literal `scan()` used to carry directly — see `transport.dart`. Takes
  /// the ALREADY-LOWERCASED platform name.
  final bool Function(String lowercaseName)? nameMatcher;

  /// Characteristic a notify-class sensor needs written to (any value, WITH
  /// response) to move the OS into bonded state before it will do anything
  /// else — see `kPebblePairingTriggerUuid`'s doc comment. Null for every
  /// band that either needs no bonding or bonds through `ble_engine`'s own
  /// `createBond()` path (every framed entry).
  final String? bondTriggerCharacteristic;

  /// A framed WHOOP-family band: an envelope, a command characteristic, and a
  /// flash the offload engine trims.
  const BandEntry.framed({
    required this.id,
    required this.label,
    required GattProfile this.gatt,
    required BandProfile this.wire,
    required this.innerOpcodeOffset,
    required this.innerVersionOffset,
    required this.innerCounterOffset,
    required BandWireCommands commands,
    List<String>? requiredCharacteristics,
    this.preRegistrationDelay = Duration.zero,
    this.postRegistrationDelay = Duration.zero,
    this.setClockDriftGated = false,
    this.burstCountGateEnforced = false,
    this.logsConsoleOutput = false,
    this.nameMatcher,
  }) : _requiredCharacteristics = requiredCharacteristics,
       _commands = commands,
       _service = null,
       bondTriggerCharacteristic = null,
       timeAnchor = TimeAnchor.measured;

  /// A notify-only sensor: one service, one or more notify characteristics, no
  /// envelope, no commands, no stored history to offload.
  ///
  /// The record offsets are -1 on purpose. They describe a position inside a
  /// framed payload this band never sends, and a plausible-looking 2/1/3 would
  /// read the wrong byte in silence — which is the exact failure the registry
  /// exists to prevent. -1 throws.
  const BandEntry.notify({
    required this.id,
    required this.label,
    required String service,
    required List<String> characteristics,
    required this.timeAnchor,
    this.bondTriggerCharacteristic,
    this.nameMatcher,
  }) : _service = service,
       _requiredCharacteristics = characteristics,
       gatt = null,
       wire = null,
       // No envelope, no command channel: [commands] throws for the same
       // reason the offsets are -1.
       _commands = null,
       preRegistrationDelay = Duration.zero,
       postRegistrationDelay = Duration.zero,
       setClockDriftGated = false,
       burstCountGateEnforced = false,
       logsConsoleOutput = false,
       innerOpcodeOffset = -1,
       innerVersionOffset = -1,
       innerCounterOffset = -1;

  /// True when this band speaks a framed envelope, i.e. the offload engine can
  /// drive it. The one predicate every WHOOP-only consumer filters on.
  bool get isFramed => wire != null;

  /// Service UUID to advertise-filter the scan on.
  String get service => gatt?.service ?? _service!;

  /// 32-bit prefix used to match this band's service from a scan result or a
  /// discovered service list (case-insensitive `startsWith`).
  String get servicePrefix => service.substring(0, 8);

  List<String> get requiredCharacteristics =>
      _requiredCharacteristics ??
      <String>[gatt!.cmdTo, gatt!.cmdFrom, gatt!.events, gatt!.data];

  /// Index of the opcode byte in a fully-framed packet. Framed entries only —
  /// this is the byte the dangerous-opcode block reads, and a band with no
  /// envelope has no such byte to read.
  int get frameOpcodeIndex => wire!.headerLen + innerOpcodeOffset;
}

bool _nameContainsWhoop(String lowercaseName) =>
    lowercaseName.contains('whoop');

/// WHOOP 4 ("Harvard", 6108xxxx).
///
/// Every value below is the gen4 arm of an `isGen5` branch that used to live in
/// `ble_engine.dart`, transcribed unchanged. The four session flags are written
/// out rather than left to their defaults because this is a table, and a table
/// that says nothing about a band is not evidence that the band does nothing.
const kWhoopGen4 = BandEntry.framed(
  id: 'gen4',
  label: 'WHOOP 4',
  gatt: GattProfile.gen4,
  wire: BandProfile.gen4,
  innerOpcodeOffset: 2,
  innerVersionOffset: 1,
  innerCounterOffset: 3,
  preRegistrationDelay: Duration.zero,
  postRegistrationDelay: Duration.zero,
  setClockDriftGated: false,
  burstCountGateEnforced: false,
  logsConsoleOutput: false,
  // A gen4 sometimes advertises its name but not a matchable service UUID —
  // see `transport.dart`'s scan(). WHOOP 5 has no such fallback: its `fd4b`
  // member UUID is reliable.
  nameMatcher: _nameContainsWhoop,
  commands: BandWireCommands(
    hello: Cmd.getHelloHarvard,
    helloBody: <int>[0x00],
    getAdvertisingName: Cmd.getAdvertisingNameHarvard,
    getAdvertisingNameBody: <int>[0x00],
    setAdvertisingName: Cmd.setAdvertisingNameHarvard,
    r10R11Realtime: Cmd.sendR10R11Realtime,
    opticalDataIsLiveToggle: true,
    offloadBody: <int>[0x00],
  ),
);

/// WHOOP 5 / MG ("fd4b"). Same inner payload layout as gen4 — only the
/// envelope differs, which is exactly what [BandProfile] models.
const BandEntry kWhoopGen5 = BandEntry.framed(
  id: 'gen5',
  label: 'WHOOP 5',
  gatt: GattProfile.gen5,
  wire: BandProfile.gen5,
  innerOpcodeOffset: 2,
  innerVersionOffset: 1,
  innerCounterOffset: 3,
  preRegistrationDelay: kGen5PreRegistrationDelay,
  postRegistrationDelay: kGen5PostRegistrationDelay,
  setClockDriftGated: true,
  burstCountGateEnforced: true,
  logsConsoleOutput: true,
  commands: BandWireCommands(
    hello: Cmd.getHello,
    helloBody: <int>[0x01],
    getAdvertisingName: Cmd.getCustomAdvertisingName,
    getAdvertisingNameBody: <int>[revision1],
    setAdvertisingName: Cmd.setCustomAdvertisingName,
    // 0x3F answers Unknown/Unhandled on a WHOOP 5 console.
    r10R11Realtime: null,
    // ENABLE_OPTICAL_DATA is the SAVE-to-history toggle here, not the realtime
    // stream (the realtime one is the next opcode up) — arming it for live
    // would write a persistent save-enable on every live-stream start.
    opticalDataIsLiveToggle: false,
    offloadBody: <int>[],
  ),
);

const List<BandEntry> kBandRegistry = [kWhoopGen4];
const List<BandEntry> kFramedBands = [kWhoopGen4];
BandEntry bandEntryFor(BandProfile wire) =>
    wire.type == DeviceType.gen4 ? kWhoopGen4 : kWhoopGen5;
const Map<String, Map<InputSignal, Duration>> kAdapterSignals = {
  'gen4': {
    InputSignal.hr1Hz: Duration(seconds: 1),
    InputSignal.rrIntervals: Duration(seconds: 1),
    InputSignal.accel1Hz: Duration(seconds: 1),
    InputSignal.ppgRedIr: Duration(seconds: 1),
    InputSignal.skinTempRaw: Duration(seconds: 1),
  },
};
Set<InputSignal> declaredSignals(String? adapterId) =>
    kAdapterSignals[adapterId]?.keys.toSet() ?? const {};
