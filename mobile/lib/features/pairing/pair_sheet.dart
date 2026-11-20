import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';

Future<void> showPairMachineSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PairMachineSheet(),
  );
}

class _PairMachineSheet extends ConsumerStatefulWidget {
  const _PairMachineSheet();

  @override
  ConsumerState<_PairMachineSheet> createState() => _PairMachineSheetState();
}

class _PairMachineSheetState extends ConsumerState<_PairMachineSheet> {
  int _tabIndex = 0; // 0=QR, 1=LAN, 2=URI
  int _step = 1; // 1=Input, 2=SAS, 3=Success
  bool _busy = false;
  String? _error;

  final _uriCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  List<LANDiscoveredPeer> _lanPeers = const [];
  bool _scanningLan = false;

  PairChallengeInfo? _challenge;
  List<String> _pendingDirect = const [];
  List<String> _pendingRelays = const [];
  String _pairedName = '';
  bool _qrDetected = false;

  bool _hasCameraPermission = false;
  bool _checkingPermission = true;
  MobileScannerController? _scannerCtrl;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _checkingPermission = false);
      return;
    }
    final runtime = ref.read(androidRuntimeProvider);
    final granted = await runtime.requestCameraPermission();
    if (mounted) {
      if (granted && _scannerCtrl == null) {
        _scannerCtrl = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        );
      }
      setState(() {
        _hasCameraPermission = granted;
        _checkingPermission = false;
      });
    }
  }

  @override
  void dispose() {
    _scannerCtrl?.dispose();
    _uriCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanLan() async {
    setState(() {
      _scanningLan = true;
      _error = null;
    });
    try {
      final peers = await ref.read(p2pTransportProvider).discoverLAN(timeoutMs: 500);
      if (mounted) {
        setState(() {
          _lanPeers = peers;
          _scanningLan = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanningLan = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _startPair({
    String? uri,
    String? hostPeerId,
    List<String> directAddrs = const [],
    List<String> relayAddrs = const [],
    String? pin,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
      _pendingDirect = directAddrs;
      _pendingRelays = relayAddrs;
    });

    if (uri != null && uri.isNotEmpty) {
      try {
        final parsed = Uri.parse(uri.trim());
        _pendingDirect = parsed.queryParametersAll['addr'] ?? const [];
        _pendingRelays = parsed.queryParametersAll['relay'] ?? const [];
      } catch (_) {}
    }

    try {
      final challenge = await ref.read(appControllerProvider.notifier).startPairing(
            uri: uri,
            hostPeerId: hostPeerId,
            directAddrs: directAddrs,
            relayAddrs: relayAddrs,
            pin: pin,
          );
      if (mounted) {
        setState(() {
          _busy = false;
          _challenge = challenge;
          _step = 2;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _qrDetected = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _confirmSas(bool accept) async {
    final chal = _challenge;
    if (chal == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final host = await ref.read(appControllerProvider.notifier).confirmPairing(
            chal,
            accept,
            directAddrs: _pendingDirect,
            relayAddrs: _pendingRelays,
          );
      if (!accept) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (host == null) {
        throw StateError('Pairing rejected by host');
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _pairedName = host.name;
          _step = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: c.borderStrong)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pair Remote Machine',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 12),
              if (_step == 1) ...[
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Scan QR')),
                    ButtonSegment(value: 1, label: Text('Nearby LAN')),
                    ButtonSegment(value: 2, label: Text('Paste URI')),
                  ],
                  selected: {_tabIndex},
                  onSelectionChanged: (s) {
                    final next = s.first;
                    setState(() => _tabIndex = next);
                    if (next == 1) unawaited(_scanLan());
                  },
                ),
                const SizedBox(height: 14),
                if (_tabIndex == 0) _buildQrPane(c),
                if (_tabIndex == 1) _buildLanPane(c),
                if (_tabIndex == 2) _buildUriPane(c),
              ] else if (_step == 2) ...[
                _buildSasStep(c),
              ] else ...[
                _buildSuccessStep(c),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrPane(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: Platform.isAndroid
                ? (_checkingPermission
                    ? Container(
                        color: c.codeBg,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_hasCameraPermission
                        ? MobileScanner(
                            controller: _scannerCtrl,
                            onDetect: (capture) {
                              if (_qrDetected || _busy) return;
                              for (final b in capture.barcodes) {
                                final raw = b.rawValue ?? '';
                                if (raw.startsWith('agy://pair')) {
                                  _qrDetected = true;
                                  unawaited(_startPair(uri: raw));
                                  break;
                                }
                              }
                            },
                            errorBuilder: (ctx, err, _) {
                              final isPermission = err.errorCode == MobileScannerErrorCode.permissionDenied;
                              final detail = err.errorDetails?.message;
                              return Container(
                                color: c.codeBg,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPermission ? Icons.videocam_off_outlined : Icons.qr_code_scanner,
                                      size: 40,
                                      color: isPermission ? c.textSecondary : c.accent,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isPermission
                                          ? 'Camera permission denied.\nPlease grant permission in App Settings or use Paste URI.'
                                          : 'Camera unavailable${detail != null && detail.isNotEmpty ? ' ($detail)' : ''}.\nUse Paste URI or Nearby LAN tab.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton(
                                      onPressed: isPermission
                                          ? _checkCameraPermission
                                          : () => unawaited(_scannerCtrl?.start()),
                                      child: Text(isPermission ? 'Retry Permission' : 'Retry Camera'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : Container(
                            color: c.codeBg,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_off_outlined, size: 40, color: c.textSecondary),
                                const SizedBox(height: 10),
                                Text(
                                  'Camera permission is required to scan QR codes.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _checkCameraPermission,
                                  icon: const Icon(Icons.lock_open, size: 16),
                                  label: const Text('Grant Camera Permission'),
                                ),
                              ],
                            ),
                          )))
                : Container(
                    color: c.codeBg,
                    alignment: Alignment.center,
                    child: Text(
                      'QR Scanner runs on Android camera.\nUse Paste URI or Nearby LAN.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.codeBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: const Text(
            'Run on your remote host:\n\$ agyd pair',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFCBD5E1)),
          ),
        ),
      ],
    );
  }

  Widget _buildLanPane(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _scanningLan ? 'Scanning _agy._udp via mDNS...' : '${_lanPeers.length} LAN peer(s) found',
              style: TextStyle(color: c.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            TextButton(onPressed: _scanningLan ? null : _scanLan, child: const Text('Rescan')),
          ],
        ),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-Digit Host PIN (from agyd pair)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 10),
        if (_lanPeers.isEmpty && !_scanningLan)
          Text(
            'No mDNS hosts visible on this subnet. Switch to Paste URI for WAN / Circuit Relay v2 pairing.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          )
        else
          ..._lanPeers.map((p) => Card(
                color: c.surfaceRaised,
                child: ListTile(
                  title: Text(
                    '${p.peerId.substring(0, p.peerId.length.clamp(0, 18))}…',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  subtitle: Text(
                    p.addrs.isNotEmpty ? p.addrs.first : 'mDNS peer',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  trailing: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _startPair(
                              hostPeerId: p.peerId,
                              directAddrs: p.addrs,
                              pin: _pinCtrl.text.trim(),
                            ),
                    child: const Text('Pair'),
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildUriPane(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.content_paste, size: 16),
            label: const Text('Paste from Clipboard', style: TextStyle(fontSize: 12)),
            onPressed: _busy
                ? null
                : () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim() ?? '';
                    if (text.isNotEmpty) {
                      _uriCtrl.text = text;
                    }
                  },
          ),
        ),
        TextField(
          controller: _uriCtrl,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            labelText: 'Pairing URI (agy://pair?...)',
            hintText: 'agy://pair?peer=12D3KooW...&token=...&relay=...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _startPair(uri: _uriCtrl.text),
          child: Text(_busy ? 'Dialing via libp2p...' : 'Dial Peer & Start Handshake'),
        ),
      ],
    );
  }

  Widget _buildSasStep(AppColors c) {
    final chal = _challenge!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accent),
      ),
      child: Column(
        children: [
          Text(
            'SECURITY VERIFICATION CODE',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            chal.sasDigits,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(chal.sasEmojis, style: const TextStyle(fontSize: 26, letterSpacing: 6)),
          const SizedBox(height: 10),
          Text(
            'Confirm this code matches your terminal before trusting ${chal.hostName}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _confirmSas(false),
                  child: const Text('Abort'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : () => _confirmSas(true),
                  child: Text(_busy ? 'Confirming...' : 'Confirm & Trust Host'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep(AppColors c) {
    return Column(
      children: [
        const SizedBox(height: 10),
        CircleAvatar(
          radius: 28,
          backgroundColor: c.successSoft,
          child: Icon(Icons.verified_user, color: c.success, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          '$_pairedName Paired!',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'PeerID added to host allowlist. Ready to stream ACP sessions and upload files.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
