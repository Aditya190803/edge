import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  test('only WHOOP 4 is offered by discovery', () {
    expect(kBandRegistry.map((e) => e.id), ['gen4']);
    expect(kFramedBands.map((e) => e.service), [GattProfile.gen4.service]);
    expect(kWhoopGen4.nameMatcher!('whoop 4'), true);
    expect(kWhoopGen4.nameMatcher!('other band'), false);
  });
  test('WHOOP 4 requires all four safe history characteristics', () {
    expect(kWhoopGen4.requiredCharacteristics, [
      GattProfile.gen4.cmdTo,
      GattProfile.gen4.cmdFrom,
      GattProfile.gen4.events,
      GattProfile.gen4.data,
    ]);
    expect(kWhoopGen4.timeAnchor, TimeAnchor.measured);
    expect(kWhoopGen4.innerVersionOffset, 1);
    expect(kWhoopGen4.innerCounterOffset, 3);
  });
  test('dangerous command gate addresses the real opcode', () {
    final raw = buildCommand(7, Cmd.rebootStrap, const [1], BandProfile.gen4);
    expect(raw[kWhoopGen4.frameOpcodeIndex], Cmd.rebootStrap);
    expect(kWhoopGen4.frameOpcodeIndex, 6);
  });
  test('WHOOP 4 bootstrap wire values remain unchanged', () {
    final commands = kWhoopGen4.commands;
    expect(commands.hello, Cmd.getHelloHarvard);
    expect(commands.helloBody, [0]);
    expect(commands.offloadBody, [0]);
    expect(commands.getAdvertisingName, Cmd.getAdvertisingNameHarvard);
    expect(commands.getAdvertisingNameBody, [0]);
    expect(commands.setAdvertisingName, Cmd.setAdvertisingNameHarvard);
    expect(commands.r10R11Realtime, Cmd.sendR10R11Realtime);
    expect(commands.opticalDataIsLiveToggle, true);
    expect(kWhoopGen4.preRegistrationDelay, Duration.zero);
    expect(kWhoopGen4.postRegistrationDelay, Duration.zero);
    expect(kWhoopGen4.setClockDriftGated, false);
    expect(kWhoopGen4.burstCountGateEnforced, false);
    expect(bandEntryFor(BandProfile.gen4), kWhoopGen4);
  });
}
