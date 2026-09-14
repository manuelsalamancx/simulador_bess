import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'pantalla_inicio.dart';
import 'calculos.dart';
import 'dashboard_screen.dart';
import 'calculos_auditoria.dart';
import 'dashboard_auditoria.dart';
import 'diseno_optimo_auditoria.dart';

final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier(true);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _migrarDatosAntiguos();
  await _sembrarPreciosPorDefecto();
  runApp(const BessSimulatorApp());
}

// Radiación/precios eran independientes por módulo (sufijos _calc/_aud); ahora
// se comparten. Si ya había datos guardados con el esquema antiguo y todavía no
// existe la clave compartida, los migramos una vez para no perder ese trabajo.
Future<void> _migrarDatosAntiguos() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getStringList('radiacion_8760') == null) {
      final antigua = prefs.getStringList('radiacion_8760_aud') ?? prefs.getStringList('radiacion_8760_calc');
      if (antigua != null) await prefs.setStringList('radiacion_8760', antigua);
    }
    if (prefs.getStringList('precios_8760') == null) {
      final antigua = prefs.getStringList('precios_8760_aud') ?? prefs.getStringList('precios_8760_calc');
      if (antigua != null) await prefs.setStringList('precios_8760', antigua);
    }
    if (prefs.getString('ubicacion_provincia') == null) {
      final antigua = prefs.getString('ubicacion_provincia_aud') ?? prefs.getString('ubicacion_provincia_calc');
      if (antigua != null) {
        await prefs.setString('ubicacion_provincia', antigua);
        await prefs.setString('ubicacion_municipio', prefs.getString('ubicacion_municipio_aud') ?? prefs.getString('ubicacion_municipio_calc') ?? '');
        await prefs.setString('ubicacion_lat', prefs.getString('ubicacion_lat_aud') ?? prefs.getString('ubicacion_lat_calc') ?? '');
        await prefs.setString('ubicacion_lon', prefs.getString('ubicacion_lon_aud') ?? prefs.getString('ubicacion_lon_calc') ?? '');
      }
    }
  } catch (_) {
    // Sin datos antiguos que migrar, o error leyendo localStorage: no pasa nada,
    // simplemente se pedirán los datos de nuevo desde Inicio.
  }
}

// Versión "admin": si nunca se han descargado precios de mercado (primer
// arranque, o localStorage vacío), se precargan de fábrica con un año real
// de ESIOS (España, 2025) incluido en el propio paquete, para no depender de la API
// ni tener que volver a descargarlos cada vez. Comparten dato Dimensionamiento y Auditoría.
Future<void> _sembrarPreciosPorDefecto() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getStringList('precios_8760') == null) {
      final jsonStr = await rootBundle.loadString('assets/precios_default_aud.json');
      final List<dynamic> valores = json.decode(jsonStr);
      await prefs.setStringList('precios_8760', valores.map((e) => e.toString()).toList());
    }
  } catch (_) {
    // Si el asset no está disponible por algún motivo, simplemente no se precarga nada
    // y la app sigue funcionando igual que antes (pidiendo la descarga manual).
  }
}

class BessSimulatorApp extends StatelessWidget {
  const BessSimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        return MaterialApp(
          title: 'Ubora Solar BESS',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: Colors.grey[100],
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0050EF),
              secondary: Color(0xFFD80073),
              surface: Colors.white,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0D0D0D),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD80073),
              secondary: Color(0xFF0050EF),
              surface: Color(0xFF1A1A1A),
            ),
          ),
          home: const MainLayout(),
        );
      },
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _indiceSeleccionado = 0; // Arranca en la pantalla de Inicio

  late final List<Widget> _ventanas = [
    PantallaInicioScreen(onSeleccionarEscenario: _irA), // 0

    // --- SECCIÓN 1: DIMENSIONAMIENTO ---
    const CalculosScreen(),        // 1
    const DashboardScreen(),       // 2

    // --- SECCIÓN 2: AUDITORÍA INVERSA ---
    const CalculosAuditoriaScreen(),      // 3
    const DashboardAuditoriaScreen(),     // 4
    const DisenoOptimoAuditoriaScreen(),  // 5

    // --- SECCIÓN 3: AJUSTES ---
    const AjustesScreen(),         // 6
  ];

  // Usado desde la Pantalla de Inicio (no está dentro del Drawer, así que no cierra nada)
  void _irA(int index) {
    setState(() {
      _indiceSeleccionado = index;
    });
  }

  void _alSeleccionarMenu(int index) {
    setState(() {
      _indiceSeleccionado = index;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 2,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 40,
              errorBuilder: (context, error, stackTrace) => const Text('UBORA', style: TextStyle(color: Color(0xFFD80073), fontWeight: FontWeight.bold, fontSize: 24)),
            ),
            const SizedBox(width: 12),
            Text('Simulador BESS', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
          ],
        ),
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD80073), Color(0xFF0050EF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Text('Menú de Navegación', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            
            _buildDrawerItem(Icons.home, 'Inicio', 0, isDark),

            const Divider(),
            Padding(padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text('DIMENSIONAMIENTO', style: TextStyle(color: isDark ? Colors.grey : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold))),
            _buildDrawerItem(Icons.calculate, 'Cálculos', 1, isDark),
            _buildDrawerItem(Icons.dashboard, 'Dashboard Gráfico', 2, isDark),

            const Divider(),
            Padding(padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text('AUDITORÍA', style: TextStyle(color: isDark ? Colors.grey : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold))),
            _buildDrawerItem(Icons.calculate, 'Cálculos', 3, isDark),
            _buildDrawerItem(Icons.search_rounded, 'Dashboard Auditoría', 4, isDark),
            _buildDrawerItem(Icons.auto_fix_high, 'Diseño Óptimo', 5, isDark),

            const Divider(),
            _buildDrawerItem(Icons.settings, 'Ajustes de Sistema', 6, isDark),
          ],
        ),
      ),
      body: _ventanas[_indiceSeleccionado],
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, int index, bool isDark) {
    bool isSelected = _indiceSeleccionado == index;
    Color activeColor = const Color(0xFFD80073);
    Color inactiveColor = isDark ? Colors.grey : Colors.blueGrey;
    
    return ListTile(
      leading: Icon(icon, color: isSelected ? activeColor : inactiveColor),
      title: Text(title, style: TextStyle(color: isSelected ? (isDark ? Colors.white : Colors.black87) : inactiveColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedTileColor: activeColor.withValues(alpha: 0.1),
      onTap: () => _alSeleccionarMenu(index),
    );
  }
}

class AjustesScreen extends StatelessWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AJUSTES DEL SISTEMA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.surface,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SwitchListTile(
                title: Text('Modo Oscuro (Estilo Ubora Neón)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                subtitle: Text('Cambia entre el tema claro clásico y el tema oscuro corporativo.', style: TextStyle(color: isDark ? Colors.grey : Colors.black54)),
                value: isDarkModeNotifier.value,
                activeThumbColor: const Color(0xFFD80073),
                onChanged: (val) {
                  isDarkModeNotifier.value = val;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}