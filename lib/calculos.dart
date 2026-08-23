// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

class CalculosScreen extends StatefulWidget {
  const CalculosScreen({super.key});

  @override
  State<CalculosScreen> createState() => _CalculosScreenState();
}

class _CalculosScreenState extends State<CalculosScreen> with WidgetsBindingObserver {
  final List<String> meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
  String mesSeleccionado = 'Enero';

  double potencia = 20.0;
  double rendimiento = 0.8;
  double limiteIny = 15.0;
  double bloqueFijoGlobal = 2.56;
  double bateriaNominal = 0.0;
  bool mercadoGlobalActivo = true;

  List<double> generacionDiaria = List.filled(24, 0.0);
  List<double> energiaBateriaPerfil = List.filled(24, 0.0); 
  List<double> socPerfil = List.filled(24, 0.0); 
  List<double> curtailmentPerfil = List.filled(24, 0.0);
  List<double> mercadoUsadoPerfil = List.filled(24, 0.0);
  List<int> horasMercadoActivas = [];

  Map<String, String> hInicioMes = {};
  Map<String, String> hFinMes = {};
  Map<String, bool> usaMercadoMes = {};

  final Map<String, List<String>> radiacionPorDefecto = {
    'Enero': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.056', '0.236', '0.391', '0.504', '0.564', '0.564', '0.504', '0.391', '0.236', '0.056', '0.0', '0.0', '0.0', '0.0', '0.0'],
    'Febrero': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.146', '0.317', '0.459', '0.562', '0.616', '0.616', '0.562', '0.459', '0.317', '0.146', '0.0', '0.0', '0.0', '0.0', '0.0'],
    'Marzo': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.094', '0.275', '0.437', '0.57', '0.663', '0.712', '0.712', '0.663', '0.57', '0.437', '0.275', '0.094', '0.0', '0.0', '0.0', '0.0'],
    'Abril': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.18', '0.35', '0.499', '0.62', '0.704', '0.747', '0.747', '0.704', '0.62', '0.499', '0.35', '0.18', '0.0', '0.0', '0.0', '0.0'],
    'Mayo': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.113', '0.269', '0.412', '0.535', '0.633', '0.702', '0.737', '0.737', '0.702', '0.633', '0.535', '0.412', '0.269', '0.113', '0.0', '0.0', '0.0'],
    'Junio': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.164', '0.321', '0.463', '0.586', '0.683', '0.75', '0.784', '0.784', '0.75', '0.683', '0.586', '0.463', '0.321', '0.164', '0.0', '0.0', '0.0'],
    'Julio': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.157', '0.325', '0.479', '0.611', '0.715', '0.788', '0.825', '0.825', '0.788', '0.715', '0.611', '0.479', '0.325', '0.157', '0.0', '0.0', '0.0'],
    'Agosto': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.058', '0.246', '0.421', '0.574', '0.696', '0.781', '0.825', '0.825', '0.781', '0.696', '0.574', '0.421', '0.246', '0.058', '0.0', '0.0', '0.0'],
    'Septiembre': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.119', '0.309', '0.478', '0.616', '0.714', '0.764', '0.764', '0.714', '0.616', '0.478', '0.309', '0.119', '0.0', '0.0', '0.0', '0.0'],
    'Octubre': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.181', '0.368', '0.523', '0.635', '0.693', '0.693', '0.635', '0.523', '0.368', '0.181', '0.0', '0.0', '0.0', '0.0', '0.0'],
    'Noviembre': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.078', '0.263', '0.422', '0.538', '0.599', '0.599', '0.538', '0.422', '0.263', '0.078', '0.0', '0.0', '0.0', '0.0', '0.0'],
    'Diciembre': ['0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.0', '0.036', '0.209', '0.359', '0.469', '0.527', '0.527', '0.469', '0.359', '0.209', '0.036', '0.0', '0.0', '0.0', '0.0', '0.0'],
  };

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    for (String m in meses) {
      hInicioMes[m] = prefs.getString('h_inicio_calc_$m') ?? '1';
      hFinMes[m] = prefs.getString('h_fin_calc_$m') ?? '4';
    }
    await _calcularTodo();
  }

  Future<void> _calcularTodo() async {
    final prefs = await SharedPreferences.getInstance();

    potencia = double.tryParse(prefs.getString('potencia_fv')?.replaceAll(',', '.') ?? '20.0') ?? 20.0;
    rendimiento = double.tryParse(prefs.getString('rendimiento')?.replaceAll(',', '.') ?? '0.8') ?? 0.8;
    limiteIny = double.tryParse(prefs.getString('limite_iny')?.replaceAll(',', '.') ?? '15.0') ?? 15.0;
    mercadoGlobalActivo = prefs.getBool('mercado_activo') ?? true;

    double minBaseload = double.infinity;
    Map<String, List<int>> horasListMes = {};

    for (String m in meses) {
      int hIni = int.tryParse(hInicioMes[m] ?? '1') ?? 1;
      int hFin = int.tryParse(hFinMes[m] ?? '4') ?? 4;
      List<int> hList = [];
      int actual = hIni;
      while (true) {
        hList.add(actual);
        if (actual == hFin) break;
        actual = (actual + 1) % 24;
      }
      horasListMes[m] = hList;

      List<String>? radGuardada = prefs.getStringList('radiacion_calc_$m');
      List<String> radBase = radGuardada ?? radiacionPorDefecto[m]!;
      double genTotalMes = 0.0;
      for (int i = 0; i < 24; i++) {
        genTotalMes += (double.tryParse(radBase[i].replaceAll(',', '.')) ?? 0.0) * potencia * rendimiento;
      }
      double baseload = mercadoGlobalActivo ? (genTotalMes / (24 - hList.length)) : (genTotalMes / 24.0);
      if (baseload < minBaseload) minBaseload = baseload;
    }

    for (String m in meses) {
      if (!mercadoGlobalActivo) {
        usaMercadoMes[m] = false;
      } else {
        List<String>? radGuardada = prefs.getStringList('radiacion_calc_$m');
        List<String> radBase = radGuardada ?? radiacionPorDefecto[m]!;
        double genTotalMes = 0.0;
        for (int i = 0; i < 24; i++) {
          genTotalMes += (double.tryParse(radBase[i].replaceAll(',', '.')) ?? 0.0) * potencia * rendimiento;
        }
        usaMercadoMes[m] = genTotalMes < (minBaseload * 24.0);
      }
    }

    double maxBateria = 0.0;
    for (String m in meses) {
      List<String>? radGuardada = prefs.getStringList('radiacion_calc_$m');
      List<String> radBase = radGuardada ?? radiacionPorDefecto[m]!;
      double bateriaMes = 0.0;
      for (int i = 0; i < 24; i++) {
        double genHr = (double.tryParse(radBase[i].replaceAll(',', '.')) ?? 0.0) * potencia * rendimiento;
        double deficit = genHr - minBaseload;
        bool inMkt = usaMercadoMes[m]! && horasListMes[m]!.contains(i);
        if (deficit < 0 && !inMkt) bateriaMes += deficit.abs();
      }
      if (bateriaMes > maxBateria) maxBateria = bateriaMes;
    }
    
    bateriaNominal = maxBateria / 0.9;
    bloqueFijoGlobal = minBaseload;

    await _simularMesPantalla(mesSeleccionado, horasListMes[mesSeleccionado]!);
  }

  Future<void> _simularMesPantalla(String mes, List<int> hList) async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? radGuardada = prefs.getStringList('radiacion_calc_$mes');
    List<String> radBase = radGuardada ?? radiacionPorDefecto[mes]!;

    List<double> tempGen = List.filled(24, 0.0);
    List<double> tempEnergiaBat = List.filled(24, 0.0);
    List<double> tempSoc = List.filled(24, 0.0);
    List<double> tempCurt = List.filled(24, 0.0);
    List<double> tempMkt = List.filled(24, 0.0);

    bool usaMkt = usaMercadoMes[mes]!;
    double socActual = bateriaNominal;

    for (int h = 0; h < 72; h++) {
      int hr = h % 24;
      double genHr = (double.tryParse(radBase[hr].replaceAll(',', '.')) ?? 0.0) * potencia * rendimiento;
      bool inMkt = usaMkt && hList.contains(hr);
      
      double net = inMkt ? genHr : (genHr - bloqueFijoGlobal);
      double socNext = socActual + net;
      double curt = 0.0;

      if (socNext > bateriaNominal) {
        curt = socNext - bateriaNominal;
        socNext = bateriaNominal;
      }
      if (socNext < 0.1 * bateriaNominal) {
        socNext = 0.1 * bateriaNominal;
      }

      if (h >= 48) {
        double injected = curt > limiteIny ? limiteIny : curt;
        
        tempGen[hr] = genHr;
        tempEnergiaBat[hr] = socActual; 
        tempSoc[hr] = bateriaNominal > 0 ? (socActual / bateriaNominal) * 100.0 : 0.0; 
        tempCurt[hr] = injected; 
        tempMkt[hr] = inMkt ? bloqueFijoGlobal : 0.0;
      }
      socActual = socNext;
    }

    setState(() {
      generacionDiaria = tempGen;
      energiaBateriaPerfil = tempEnergiaBat;
      socPerfil = tempSoc;
      curtailmentPerfil = tempCurt;
      mercadoUsadoPerfil = tempMkt;
      horasMercadoActivas = usaMkt ? hList : [];
    });
  }

  void _abrirTablaDatos() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text('DATOS DE SIMULACIÓN (MWh)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(flex: 1, child: Text('Hora', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                  Expanded(flex: 2, child: Text('Gen.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                  Expanded(flex: 2, child: Text('Fijo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                  Expanded(flex: 2, child: Text('Bat(MWh)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                  Expanded(flex: 2, child: Text('SOC(%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                  Expanded(flex: 2, child: Text('Red', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                  Expanded(flex: 2, child: Text('Inyección', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.grey : Colors.black87))),
                ],
              ),
              Divider(thickness: 2, color: isDark ? Colors.white24 : Colors.black12),
              Expanded(
                child: ListView.builder(
                  itemCount: 24,
                  itemBuilder: (context, i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(flex: 1, child: Text('${i.toString().padLeft(2,'0')}:00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
                          Expanded(flex: 2, child: Text(generacionDiaria[i].toStringAsFixed(2), style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
                          Expanded(flex: 2, child: Text(bloqueFijoGlobal.toStringAsFixed(2), style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
                          Expanded(flex: 2, child: Text(energiaBateriaPerfil[i].toStringAsFixed(2), style: TextStyle(color: isDark ? const Color(0xFF0050EF) : Colors.blue, fontWeight: FontWeight.bold, fontSize: 13))),
                          Expanded(flex: 2, child: Text('${socPerfil[i].toStringAsFixed(1)} %', style: TextStyle(color: socPerfil[i] <= 11 ? (isDark ? const Color(0xFFD80073) : Colors.red) : Colors.green, fontWeight: FontWeight.bold, fontSize: 13))),
                          Expanded(flex: 2, child: Text(mercadoUsadoPerfil[i].toStringAsFixed(2), style: const TextStyle(color: Colors.orange, fontSize: 13))),
                          Expanded(flex: 2, child: Text(curtailmentPerfil[i].toStringAsFixed(2), style: TextStyle(color: isDark ? Colors.purpleAccent : Colors.purple, fontSize: 13))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    List<RangeAnnotations> annotationsGraph = [];
    if (horasMercadoActivas.isNotEmpty) {
      List<VerticalRangeAnnotation> verticalAnns = [];
      for (int h in horasMercadoActivas) {
        verticalAnns.add(VerticalRangeAnnotation(x1: h - 0.5, x2: h + 0.5, color: Colors.orange.withValues(alpha: 0.2)));
      }
      annotationsGraph.add(RangeAnnotations(verticalRangeAnnotations: verticalAnns));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ANÁLISIS DE GENERACIÓN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('Mes: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? const Color(0xFF0050EF).withValues(alpha: 0.5) : Colors.blueGrey.shade200)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          value: mesSeleccionado,
                          items: meses.map((String mes) => DropdownMenuItem<String>(value: mes, child: Text(mes, style: TextStyle(color: isDark ? Colors.white : Colors.black87)))).toList(),
                          onChanged: (String? nuevoMes) async {
                            if (nuevoMes != null) {
                              setState(() => mesSeleccionado = nuevoMes);
                              await _calcularTodo();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: isDark ? const LinearGradient(colors: [Color(0xFFD80073), Color(0xFF0050EF)]) : null,
                    color: isDark ? null : Colors.blueGrey,
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _abrirTablaDatos,
                    icon: const Icon(Icons.table_chart, color: Colors.white),
                    label: const Text('VER TABLA DE DATOS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                )
              ],
            ),
          ),
          
          const SizedBox(width: 32),

          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Generación Solar y Baseload Fijo (MWh)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                        const SizedBox(height: 16),
                        Expanded(
                          child: LineChart(
                            LineChartData(
                              rangeAnnotations: annotationsGraph.isNotEmpty ? annotationsGraph.first : RangeAnnotations(),
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                    return touchedSpots.map((spot) {
                                      String tipo = '';
                                      if (spot.barIndex == 0) {
                                        tipo = 'Generación';
                                      } else if (spot.barIndex == 1) tipo = 'Bloque Fijo';
                                      else if (spot.barIndex == 2) tipo = 'Inyección Red';
                                      return LineTooltipItem(
                                        '$tipo\n${spot.x.toInt()}:00 -> ${spot.y.toStringAsFixed(2)} MWh',
                                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                              minX: 0, maxX: 23, minY: 0, maxY: potencia + 2,
                              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (val) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
                              titlesData: FlTitlesData(
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 3, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('${v.toInt()}:00', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54))))),
                                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(1), style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)))),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: List.generate(24, (i) => FlSpot(i.toDouble(), generacionDiaria[i])),
                                  isCurved: true, preventCurveOverShooting: true, color: Colors.lightGreen, barWidth: 4, dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: true, color: Colors.lightGreen.withValues(alpha: 0.3)),
                                ),
                                LineChartBarData(
                                  spots: [const FlSpot(0, 0), const FlSpot(23, 0)].map((s) => FlSpot(s.x, bloqueFijoGlobal)).toList(),
                                  isCurved: false, color: Colors.orange, barWidth: 2.5, dotData: const FlDotData(show: false), dashArray: [5, 5],
                                ),
                                LineChartBarData(
                                  spots: List.generate(24, (i) => FlSpot(i.toDouble(), curtailmentPerfil[i])),
                                  isCurved: true, preventCurveOverShooting: true, color: isDark ? const Color(0xFFD80073) : Colors.redAccent, barWidth: 2, dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: true, color: (isDark ? const Color(0xFFD80073) : Colors.redAccent).withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estado de Carga de la Batería (SOC %)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF0050EF) : Colors.purple)),
                        const SizedBox(height: 16),
                        Expanded(
                          child: LineChart(
                            LineChartData(
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (List<LineBarSpot> touchedSpots) => touchedSpots.map((spot) => LineTooltipItem('${spot.x.toInt()}:00 -> ${spot.y.toStringAsFixed(1)} %', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))).toList(),
                                ),
                              ),
                              minX: 0, maxX: 23, minY: 0, maxY: 105,
                              extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: 10, color: Colors.red, strokeWidth: 2, dashArray: [5,5], label: HorizontalLineLabel(show: true, labelResolver: (l) => 'Límite 10%', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))]),
                              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (val) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
                              titlesData: FlTitlesData(
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 3, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('${v.toInt()}:00', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54))))),
                                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)))),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: List.generate(24, (i) => FlSpot(i.toDouble(), socPerfil[i])),
                                  isCurved: true, preventCurveOverShooting: true, color: isDark ? const Color(0xFF0050EF) : Colors.purple, barWidth: 4, dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: true, color: (isDark ? const Color(0xFF0050EF) : Colors.purple).withValues(alpha: 0.2)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}