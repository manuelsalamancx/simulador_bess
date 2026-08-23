import 'package:flutter/material.dart';
import 'base_datos.dart'; 
import 'calculos.dart';   
import 'dashboard_screen.dart'; 
import 'base_datos_auditoria.dart';
import 'calculos_auditoria.dart';
import 'dashboard_auditoria.dart';

final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier(true);

void main() {
  runApp(const BessSimulatorApp());
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
  int _indiceSeleccionado = 2; // Arranca en Dashboard (Bloque Fijo)

  final List<Widget> _ventanas = [
    // --- SECCIÓN 1: DIMENSIONAMIENTO ---
    const BaseDatosScreen(),       // 0
    const CalculosScreen(),        // 1
    const DashboardScreen(),       // 2
    
    // --- SECCIÓN 2: AUDITORÍA INVERSA ---
    const BaseDatosAuditoriaScreen(),     // 3
    const CalculosAuditoriaScreen(),      // 4
    const DashboardAuditoriaScreen(),     // 5

    // --- SECCIÓN 3: AJUSTES ---
    const AjustesScreen(),         // 6
  ];

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
            
            Padding(padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8), child: Text('DIMENSIONAMIENTO', style: TextStyle(color: isDark ? Colors.grey : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold))),
            _buildDrawerItem(Icons.storage, 'Base de Datos', 0, isDark),
            _buildDrawerItem(Icons.calculate, 'Cálculos', 1, isDark),
            _buildDrawerItem(Icons.dashboard, 'Dashboard Gráfico', 2, isDark),
            
            const Divider(),
            Padding(padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text('AUDITORÍA', style: TextStyle(color: isDark ? Colors.grey : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold))),
            _buildDrawerItem(Icons.storage, 'Base de Datos', 3, isDark),
            _buildDrawerItem(Icons.calculate, 'Cálculos', 4, isDark),
            _buildDrawerItem(Icons.search_rounded, 'Dashboard Auditoría', 5, isDark),

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