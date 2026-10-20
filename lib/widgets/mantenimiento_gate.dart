import 'dart:async';
import 'package:flutter/material.dart';
import '../core/supabase_client.dart';

class MantenimientoGate extends StatefulWidget {
  final Widget child;
  const MantenimientoGate({super.key, required this.child});
  @override
  State<MantenimientoGate> createState() => _MantenimientoGateState();
}

class _MantenimientoGateState extends State<MantenimientoGate>
    with WidgetsBindingObserver {
  bool _mantenimiento = false;
  bool _esAdmin = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisar();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _revisar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _revisar();
  }

  Future<void> _revisar() async {
    try {
      final r = await supabase
          .from('configuracion_app')
          .select('valor')
          .eq('clave', 'modo_mantenimiento')
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      final activo = r?['valor'] == true;
      var admin = _esAdmin;
      if (activo && supabase.auth.currentUser != null) {
        try {
          admin = (await supabase.rpc('es_admin')) == true;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _mantenimiento = activo;
          _esAdmin = admin;
        });
      }
    } catch (_) {
      // Sin red o error: no bloqueamos a nadie.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_mantenimiento || _esAdmin) return widget.child;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_rounded, size: 64),
                const SizedBox(height: 16),
                Text('Estamos en mantenimiento',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Volvemos en unos minutos. Gracias por tu paciencia.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
