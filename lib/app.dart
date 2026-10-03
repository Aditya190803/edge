import 'dart:async';
import 'package:flutter/material.dart';
import 'ble/android_background.dart';
import 'bridge/coordinator.dart';
import 'health/bridge_health_export.dart';

class BridgeApp extends StatefulWidget {
  const BridgeApp({super.key, required this.coordinator});
  final BridgeCoordinator coordinator;
  @override
  State<BridgeApp> createState() => _BridgeAppState();
}

class _BridgeAppState extends State<BridgeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The service owns the coordinator beyond this Activity's lifetime.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.coordinator.refreshStatus());
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WHOOP 4 Bridge',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: BridgeScreen(coordinator: widget.coordinator),
  );
  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff245a48),
      brightness: brightness,
    ),
  );
}

class BridgeScreen extends StatelessWidget {
  const BridgeScreen({super.key, required this.coordinator});
  final BridgeCoordinator coordinator;

  Future<void> _action(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _time(DateTime? value) {
    if (value == null) return 'Not yet';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.day}/${local.month} ${two(local.hour)}:${two(local.minute)}';
  }

  String get _connection {
    if (coordinator.paused) return 'Sync paused';
    if (coordinator.state.autoReconnectPaused) {
      return 'Reconnect needs attention';
    }
    if (coordinator.state.needsRepairGuide) {
      return 'Bluetooth pairing needs repair';
    }
    if (coordinator.busy) return 'Syncing';
    return switch (coordinator.state.connection) {
      'connected' || 'listening' || 'ready' => 'Connected',
      'connecting' || 'reconnecting' => 'Connecting',
      _ => 'Waiting for your band',
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: coordinator,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('WHOOP 4 Bridge')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  'Your band. Your health app.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sync WHOOP 4 to Health Connect without a WHOOP account or subscription. View your data in a compatible health app.',
                ),
                const SizedBox(height: 24),
                if (!coordinator.initialized) ...[
                  if (coordinator.initializationError == null)
                    const LinearProgressIndicator(),
                  if (coordinator.initializationError != null) ...[
                    _notice(context, coordinator.initializationError!),
                    FilledButton(
                      onPressed: () => _action(context, coordinator.initialize),
                      child: const Text('Retry startup'),
                    ),
                  ],
                ] else if (coordinator.paired == null) ...[
                  const Text(
                    'Close the official WHOOP app. Keep your charged band nearby and put it into pairing mode if it cannot be found.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: coordinator.scanning || coordinator.busy
                        ? null
                        : () => _action(context, coordinator.scan),
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(
                      coordinator.scanning ? 'Searching…' : 'Find WHOOP 4',
                    ),
                  ),
                  if (coordinator.scanning) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  for (final result in coordinator.scanResults)
                    ListTile(
                      leading: const Icon(Icons.watch_outlined),
                      title: Text(
                        result.device.platformName.isEmpty
                            ? 'WHOOP 4'
                            : result.device.platformName,
                      ),
                      subtitle: Text(result.device.remoteId.str),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !coordinator.busy,
                      onTap: () =>
                          _action(context, () => coordinator.pair(result)),
                    ),
                ] else ...[
                  _section(context, 'Band', [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bluetooth),
                      title: Text(coordinator.paired!.serial ?? 'WHOOP 4'),
                      subtitle: Text(_connection),
                      trailing: Text(
                        coordinator.state.batteryPct == null
                            ? '—'
                            : '${coordinator.state.batteryPct!.round()}%',
                      ),
                    ),
                    _row('Latest band data', _time(coordinator.lastDataAt)),
                    _row('Last health export', _time(coordinator.lastExportAt)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: coordinator.busy || coordinator.paused
                          ? null
                          : () => _action(context, coordinator.syncNow),
                      icon: const Icon(Icons.sync),
                      label: Text(coordinator.busy ? 'Syncing…' : 'Sync now'),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Background sync'),
                      subtitle: const Text(
                        'Keeps syncing when this screen closes.',
                      ),
                      value: !coordinator.paused,
                      onChanged: (value) =>
                          _action(context, () => coordinator.setPaused(!value)),
                    ),
                  ]),
                ],
                if (coordinator.error != null) ...[
                  const SizedBox(height: 16),
                  _notice(context, coordinator.error!),
                ],
                if (coordinator.initialized) ...[
                  const SizedBox(height: 24),
                  _section(context, 'Health Connect', [
                    const Text(
                      'Shares heart rate, sleep stages, HRV, resting heart rate and respiratory rate. Nightly metrics need sufficient sleep data. Missing measurements stay absent.',
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send data to Health Connect'),
                      subtitle: const Text(
                        'Grant access to the data you want to share.',
                      ),
                      value: coordinator.healthSyncEnabled,
                      onChanged: (value) => _action(
                        context,
                        () => coordinator.setHealthSyncEnabled(value),
                      ),
                    ),
                    if (coordinator.healthState ==
                            HealthLinkState.notInstalled ||
                        coordinator.healthState == HealthLinkState.needsUpdate)
                      OutlinedButton(
                        onPressed: () => _action(
                          context,
                          BridgeHealthExporter.shared.install,
                        ),
                        child: const Text('Install or update Health Connect'),
                      ),
                    TextButton(
                      onPressed: () => _action(
                        context,
                        BridgeHealthExporter.shared.openSettings,
                      ),
                      child: const Text('Health Connect permissions'),
                    ),
                    const Text(
                      'In your health app, enable reading from Health Connect. Its dashboard may refresh later than the data store.',
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _section(context, 'Background access', [
                    Text(
                      coordinator.batteryOptimizationIgnored
                          ? 'Battery optimization exemption is enabled.'
                          : 'Allow unrestricted battery use for more reliable screen-off syncing.',
                    ),
                    if (!coordinator.batteryOptimizationIgnored)
                      TextButton(
                        onPressed: () => _action(context, () async {
                          await AndroidBackground.requestIgnoreBatteryOptimizations();
                          await coordinator.refreshStatus();
                        }),
                        child: const Text('Allow background battery use'),
                      ),
                    TextButton(
                      onPressed: () => _action(
                        context,
                        AndroidBackground.openOemAutostartSettings,
                      ),
                      child: const Text('App background settings'),
                    ),
                    const Text(
                      'A quiet notification keeps the Bluetooth service running. Force-stopping the app stops syncing until you reopen it.',
                    ),
                  ]),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: coordinator.busy
                        ? null
                        : () => _deleteLocal(context),
                    child: const Text('Delete local data'),
                  ),
                  if (coordinator.paired != null)
                    TextButton(
                      onPressed: () => _forget(context),
                      child: const Text('Forget band'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _deleteLocal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete local data?'),
        content: const Text(
          'Stops syncing, forgets the band, and deletes data saved on this phone. Health Connect records remain. Data already removed from the band cannot be downloaded again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _action(context, coordinator.deleteLocalData);
    }
  }

  Future<void> _forget(BuildContext context) async {
    final forget = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this band?'),
        content: const Text(
          'Stops syncing and removes pairing. Your saved data and Health Connect records remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget band'),
          ),
        ],
      ),
    );
    if (forget == true && context.mounted) {
      await _action(context, coordinator.unpair);
    }
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      );
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
  Widget _notice(BuildContext context, String message) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}
