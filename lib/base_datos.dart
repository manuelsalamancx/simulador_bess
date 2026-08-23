import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

class BaseDatosScreen extends StatefulWidget {
  const BaseDatosScreen({super.key});

  @override
  State<BaseDatosScreen> createState() => _BaseDatosScreenState();
}

class _BaseDatosScreenState extends State<BaseDatosScreen> {
  final TextEditingController _latController = TextEditingController(text: '36.72');
  final TextEditingController _lonController = TextEditingController(text: '-4.42');
  final TextEditingController _tokenEsiosController = TextEditingController();

  bool _cargandoPVGIS = false;
  bool _cargandoPrecios = false;
  
  List<double> _radiacion8760 = [];
  List<double> _precios8760 = [];

  final Color accentMagenta = const Color(0xFFD80073);
  final Color accentBlue = const Color(0xFF0050EF);

  @override
  void initState() {
    super.initState();
    _cargarDatosGuardados();
  }

  Future<void> _cargarDatosGuardados() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? radGuardada = prefs.getStringList('radiacion_8760_calc');
    List<String>? preGuardados = prefs.getStringList('precios_8760_calc');

    if (radGuardada != null && radGuardada.length == 8760) {
      _radiacion8760 = radGuardada.map((e) => double.parse(e)).toList();
    }
    if (preGuardados != null && preGuardados.length == 8760) {
      _precios8760 = preGuardados.map((e) => double.parse(e)).toList();
    }
    setState(() {});
  }

  Future<void> _descargarPVGIS() async {
    setState(() => _cargandoPVGIS = true);
    try {
      String lat = _latController.text;
      String lon = _lonController.text;
      
      // Construimos la URL objetivo de PVGIS
String targetUrl = 'https://re.jrc.ec.europa.eu/api/v5_2/seriescalc?lat=$lat&lon=$lon&startyear=2020&endyear=2020&pvcalculation=1&peakpower=1&loss=0&outputformat=json';

// Usamos corsproxy.io, que es mucho más estable para APIs gubernamentales
final url = Uri.parse('https://corsproxy.io/?' + Uri.encodeComponent(targetUrl));
      
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final hourly = data['outputs']['hourly'] as List;
        
        List<double> radTemp = [];
        for (var item in hourly) {
          // PVGIS devuelve W generados para 1kWp. Dividimos entre 1000 para tener factor 0-1
          double p = (item['P'] ?? 0.0).toDouble() / 1000.0;
          radTemp.add(p);
        }

        if (radTemp.length >= 8760) {
          _radiacion8760 = radTemp.sublist(0, 8760);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('radiacion_8760_calc', _radiacion8760.map((e) => e.toString()).toList());
          
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Datos PVGIS (8760h) descargados con éxito!'), backgroundColor: Colors.green));
        }
      } else {
        throw Exception('Error en la API de PVGIS');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    setState(() => _cargandoPVGIS = false);
  }
Future<void> _descargarESIOS() async {
    String token = _tokenEsiosController.text.trim();
    if (token.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, introduce tu Token de ESIOS'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _cargandoPrecios = true);

    try {
      // Pedimos los precios del PVPC (indicador 1001) para un año histórico completo (ej. 2023)
      final url = Uri.parse('https://api.esios.ree.es/indicators/1001?start_date=2023-01-01T00:00:00&end_date=2023-12-31T23:59:59');

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json; application/vnd.esios-api-v1+json',
          'Content-Type': 'application/json',
          'x-api-key': token, // Aquí inyectamos tu llave personal
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final values = data['indicator']['values'] as List;

        List<double> preciosTemp = [];
        for (var item in values) {
          // Extraemos el valor del precio que viene en €/MWh
          preciosTemp.add((item['value'] ?? 0.0).toDouble());
        }

        // Ajustamos la matriz exactamente a 8760 horas (por si los cambios de horario desajustan la longitud)
        if (preciosTemp.length >= 8760) {
          _precios8760 = preciosTemp.sublist(0, 8760);
        } else {
          _precios8760 = List.from(preciosTemp);
          while (_precios8760.length < 8760) {
            _precios8760.add(_precios8760.last); // Rellenamos huecos si es bisiesto/cambio de hora
          }
        }

        final prefs = await SharedPreferences.getInstance();
        // Diferenciador para guardar en Calculadora o en Auditoría
        String claveMemoria = toString().contains('Auditoria') ? 'precios_8760_aud' : 'precios_8760_calc';
        await prefs.setStringList(claveMemoria, _precios8760.map((e) => e.toString()).toList());

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Precios ESIOS descargados con éxito!'), backgroundColor: Colors.green));
      } else {
        throw Exception('Código ${response.statusCode}: Acceso denegado o Token inválido');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }

    setState(() => _cargandoPrecios = false);
  }
  Future<void> _generarPreciosPatron() async {
    setState(() => _cargandoPrecios = true);
    // Simula 8760 horas en base a tu antigua matriz mensual (Para no bloquearte sin Token)
    final Map<String, List<String>> preciosPorDefecto = {
      'Enero': ['101.5', '94.9', '91.6', '88.2', '86.3', '89.9', '100.9', '117.5', '134.2', '133.3', '105.2', '92.6', '87.5', '83.8', '81.9', '83.7', '104.0', '126.8', '140.7', '145.9', '140.8', '134.9', '126.5', '117.0'],
      'Febrero': ['120.9', '114.7', '111.8', '110.4', '108.2', '111.0', '123.9', '152.3', '165.4', '143.9', '111.3', '91.0', '78.2', '75.9', '72.8', '73.4', '91.4', '132.9', '165.0', '186.3', '188.1', '162.7', '148.1', '145.8'],
      'Marzo': ['68.3', '60.6', '58.7', '57.9', '57.5', '59.4', '70.4', '93.7', '84.6', '59.7', '48.4', '42.0', '37.2', '35.9', '36.2', '37.7', '45.2', '59.1', '82.9', '126.3', '129.5', '114.0', '99.0', '94.0'],
      'Abril': ['57.7', '51.4', '51.2', '50.1', '49.6', '51.6', '59.7', '85.8', '84.3', '47.2', '27.7', '18.8', '17.2', '16.8', '16.7', '17.6', '17.3', '18.5', '24.1', '45.7', '84.2', '103.1', '81.2', '64.6'],
      'Mayo': ['54.9', '50.8', '50.0', '48.9', '49.5', '51.4', '54.9', '61.4', '49.1', '31.9', '24.1', '23.6', '23.7', '23.3', '23.3', '24.2', '25.1', '26.8', '30.5', '38.3', '61.2', '84.8', '76.8', '59.5'],
      'Junio': ['117.2', '111.5', '108.6', '107.7', '107.6', '109.2', '116.1', '119.9', '101.5', '71.2', '53.0', '44.6', '41.0', '38.3', '36.7', '37.4', '40.8', '50.7', '69.3', '93.6', '120.1', '148.0', '143.7', '122.9'],
      'Julio': ['110.5', '102.6', '98.6', '95.3', '92.7', '96.0', '104.5', '113.9', '97.9', '70.1', '54.0', '51.0', '50.6', '49.9', '48.2', '48.2', '50.3', '56.2', '65.5', '86.6', '111.5', '134.1', '136.3', '119.0'],
      'Agosto': ['110.5', '103.8', '100.0', '97.0', '96.1', '97.3', '103.2', '114.2', '104.6', '72.1', '49.6', '39.3', '35.6', '32.6', '32.5', '33.7', '40.1', '50.2', '68.4', '97.1', '119.7', '134.3', '125.2', '112.0'],
      'Septiembre': ['96.3', '90.7', '89.8', '87.9', '87.1', '88.6', '93.7', '111.3', '110.0', '80.2', '47.7', '35.1', '30.9', '29.4', '31.9', '29.2', '32.3', '41.9', '63.8', '106.8', '132.7', '140.2', '112.9', '102.6'],
      'Octubre': ['103.7', '98.2', '94.2', '92.7', '93.3', '95.5', '101.7', '118.6', '128.0', '106.0', '76.3', '60.4', '54.4', '51.7', '49.8', '52.6', '60.1', '78.1', '102.0', '130.0', '148.7', '133.6', '114.5', '103.5'],
      'Noviembre': ['79.7', '73.7', '70.6', '68.5', '66.7', '69.6', '78.2', '91.2', '94.7', '68.4', '49.8', '43.6', '42.6', '42.0', '43.1', '50.5', '67.6', '93.3', '107.1', '114.9', '114.2', '104.1', '93.0', '82.7'],
      'Diciembre': ['90.9', '84.9', '81.7', '79.2', '77.2', '79.7', '86.1', '95.6', '105.2', '99.4', '87.1', '78.8', '76.4', '73.8', '74.0', '81.2', '92.5', '106.5', '114.4', '117.9', '120.0', '113.5', '103.3', '93.0'],
    };
    final List<String> mesesNombres = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final List<int> diasMes = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    List<double> preTemp = [];
    for (int m = 0; m < 12; m++) {
      List<String> precMes = preciosPorDefecto[mesesNombres[m]]!;
      for (int d = 0; d < diasMes[m]; d++) {
        for (int h = 0; h < 24; h++) {
          preTemp.add(double.parse(precMes[h]));
        }
      }
    }

    _precios8760 = preTemp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('precios_8760_calc', _precios8760.map((e) => e.toString()).toList());
    
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _cargandoPrecios = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Matriz de Precios Patrón 8760h generada'), backgroundColor: Colors.blue));
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PANEL IZQUIERDO: CONTROLES API
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SISTEMA DE DATOS 8760h', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                const SizedBox(height: 24),
                
                // TARJETA PVGIS
                Card(
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wb_sunny, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text('RADIACIÓN SOLAR (PVGIS API)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: _latController, decoration: const InputDecoration(labelText: 'Latitud', border: OutlineInputBorder(), isDense: true))),
                            const SizedBox(width: 10),
                            Expanded(child: TextFormField(controller: _lonController, decoration: const InputDecoration(labelText: 'Longitud', border: OutlineInputBorder(), isDense: true))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _cargandoPVGIS ? null : _descargarPVGIS,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                            child: _cargandoPVGIS ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white)) : const Text('Descargar Año de PVGIS'),
                          ),
                        ),
                        if (_radiacion8760.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Text('✅ Datos solares cargados (${_radiacion8760.length}h)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                          )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // TARJETA ESIOS
                Card(
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.euro_symbol, color: accentBlue),
                            const SizedBox(width: 8),
                            Text('PRECIOS MERCADO (ESIOS/OMIE)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tokenEsiosController, 
                          decoration: const InputDecoration(labelText: 'Token ESIOS (Opcional)', hintText: 'Pega tu token de REE aquí', border: OutlineInputBorder(), isDense: true),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _cargandoPrecios ? null : _descargarESIOS, 
                                style: ElevatedButton.styleFrom(backgroundColor: accentBlue, foregroundColor: Colors.white),
                                child: const Text('API ESIOS'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _cargandoPrecios ? null : _generarPreciosPatron,
                                style: OutlinedButton.styleFrom(side: BorderSide(color: accentBlue)),
                                child: _cargandoPrecios ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator()) : Text('Año Tipo', style: TextStyle(color: accentBlue)),
                              ),
                            ),
                          ],
                        ),
                        if (_precios8760.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Text('✅ Precios cargados (${_precios8760.length}h)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                          )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 32),

          // PANEL DERECHO: VISUALIZADOR DE PERFIL
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Visualizador de Perfiles 8760h (Primera semana del año)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                  const SizedBox(height: 16),
                  if (_radiacion8760.isEmpty || _precios8760.isEmpty)
                    const Expanded(child: Center(child: Text('Descarga ambos bloques de datos para visualizar')))
                  else
                    Expanded(
                      child: LineChart(
                        LineChartData(
                          minX: 0, maxX: 168, 
                          minY: 0, maxY: 250,
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(168, (i) => FlSpot(i.toDouble(), _radiacion8760[i] * 100)), 
                              isCurved: true, color: Colors.orange, barWidth: 2, dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: List.generate(168, (i) => FlSpot(i.toDouble(), _precios8760[i])),
                              isCurved: true, color: accentBlue, barWidth: 2, dotData: const FlDotData(show: false),
                            ),
                          ],
                          titlesData: const FlTitlesData(rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
                          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (val) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}