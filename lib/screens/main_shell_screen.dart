// main_shell_screen.dart
//
// Contenedor con menú inferior (bottom navigation) para las 3
// secciones principales: Inicio, Mapa y Perfil. Cada pestaña conserva
// su propio Scaffold/AppBar/Drawer tal cual ya estaban -- este shell
// solo decide cuál se muestra y agrega la barra de abajo.
//
// Usa IndexedStack (no un simple `body: _paginas[i]`) para que cada
// pestaña mantenga su estado (scroll, futuros ya cargados, etc.) al
// cambiar de una a otra, en vez de reconstruirse de cero cada vez.

import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import 'home_screen.dart';
import 'mapa_tiendas_screen.dart';
import 'mi_perfil_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _indice = 0;

  static const _paginas = [
    HomeScreen(),
    MapaTiendasScreen(),
    MiPerfilScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: IndexedStack(index: _indice, children: _paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        backgroundColor: esOscuro ? AppColors.surfaceDark : Colors.white,
        indicatorColor: AppColors.primary.withOpacity(0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded, color: AppColors.primary),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded, color: AppColors.primary),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.primary),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
