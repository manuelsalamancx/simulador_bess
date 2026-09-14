import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

/// Baterías Standalone: simula una batería de arbitraje puro (sin FV) que
/// hace DOS ciclos de carga/descarga al día contra el precio de mercado.
/// Para cada ciclo se puede elegir una ventana horaria amplia (y la propia
/// simulación escoge, día a día, las horas más baratas/caras dentro de ella
/// según la "duración" de la batería) o fijar las horas exactas de carga y
/// descarga, iguales todos los días del año. Exporta el spread día a día de
/// cada ciclo a CSV.
class BateriasStandaloneScreen extends StatefulWidget {
  const BateriasStandaloneScreen({super.key});

  @override
  State<BateriasStandaloneScreen> createState() => _BateriasStandaloneScreenState();
}

class _BateriasStandaloneScreenState extends State<BateriasStandaloneScreen> {
  static const double _umbralMinimoSpread = 10.0; // €: por debajo de esto, el ciclo no opera ese día
  String _modoSeleccion = 'exacta'; // 'ventana' | 'exacta'
  final TextEditingController _duracionController = TextEditingController(text: '2');

  // Modo "ventana": rango horario amplio por ciclo (se optimiza dentro de él)
  int _cargaIniC1 = 1, _cargaFinC1 = 7;
  int _descargaIniC1 = 10, _descargaFinC1 = 14;
  int _cargaIniC2 = 15, _cargaFinC2 = 17;
  int _descargaIniC2 = 20, _descargaFinC2 = 23;

  // Modo "exacta": horas concretas, fijas cada día del año
  Set<int> _horasCargaC1 = {2, 3};
  Set<int> _horasDescargaC1 = {7, 8};
  Set<int> _horasCargaC2 = {12, 13};
  Set<int> _horasDescargaC2 = {20, 21};

  List<double> _precios8760 = [];
  bool _calculando = false;
  String? _mensajeError;
  List<Map<String, dynamic>> _resultadosDiarios = [];

  String spreadAnualC1 = '0,00', spreadAnualC2 = '0,00', spreadAnualTotal = '0,00';
  String spreadMedioDiaC1 = '0,00', spreadMedioDiaC2 = '0,00';
  List<double> _spreadMensual = List.filled(12, 0.0);

  final Color accentMagenta = const Color(0xFFD80073);
  final Color accentBlue = const Color(0xFF0050EF);

  final List<int> _diasMes = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final List<String> _mesesAbrev = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  void initState() {
    super.initState();
    _cargarYCalcular();
  }

  String formatoEuro(double value, {int decimales = 2}) {
    String fixed = value.toStringAsFixed(decimales);
    List<String> parts = fixed.split('.');
    String intPart = parts[0];
    String decPart = parts.length > 1 ? parts[1] : '';
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formattedInt = intPart.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return decimales > 0 ? '$formattedInt,$decPart' : formattedInt;
  }

  Future<void> _cargarYCalcular() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _modoSeleccion = prefs.getString('bs_modo') ?? 'exacta';
      _duracionController.text = prefs.getString('bs_duracion') ?? '2';

      _cargaIniC1 = prefs.getInt('bs_carga_ini_c1') ?? 1;
      _cargaFinC1 = prefs.getInt('bs_carga_fin_c1') ?? 7;
      _descargaIniC1 = prefs.getInt('bs_descarga_ini_c1') ?? 10;
      _descargaFinC1 = prefs.getInt('bs_descarga_fin_c1') ?? 14;
      _cargaIniC2 = prefs.getInt('bs_carga_ini_c2') ?? 15;
      _cargaFinC2 = prefs.getInt('bs_carga_fin_c2') ?? 17;
      _descargaIniC2 = prefs.getInt('bs_descarga_ini_c2') ?? 20;
      _descargaFinC2 = prefs.getInt('bs_descarga_fin_c2') ?? 23;

      _horasCargaC1 = (prefs.getStringList('bs_horas_carga_c1') ?? ['2', '3']).map(int.parse).toSet();
      _horasDescargaC1 = (prefs.getStringList('bs_horas_descarga_c1') ?? ['7', '8']).map(int.parse).toSet();
      _horasCargaC2 = (prefs.getStringList('bs_horas_carga_c2') ?? ['12', '13']).map(int.parse).toSet();
      _horasDescargaC2 = (prefs.getStringList('bs_horas_descarga_c2') ?? ['20', '21']).map(int.parse).toSet();
    });
    await _guardar();
    await _calcular();
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bs_modo', _modoSeleccion);
    await prefs.setString('bs_duracion', _duracionController.text);
    await prefs.setInt('bs_carga_ini_c1', _cargaIniC1);
    await prefs.setInt('bs_carga_fin_c1', _cargaFinC1);
    await prefs.setInt('bs_descarga_ini_c1', _descargaIniC1);
    await prefs.setInt('bs_descarga_fin_c1', _descargaFinC1);
    await prefs.setInt('bs_carga_ini_c2', _cargaIniC2);
    await prefs.setInt('bs_carga_fin_c2', _cargaFinC2);
    await prefs.setInt('bs_descarga_ini_c2', _descargaIniC2);
    await prefs.setInt('bs_descarga_fin_c2', _descargaFinC2);
    await prefs.setStringList('bs_horas_carga_c1', _horasCargaC1.map((e) => e.toString()).toList());
    await prefs.setStringList('bs_horas_descarga_c1', _horasDescargaC1.map((e) => e.toString()).toList());
    await prefs.setStringList('bs_horas_carga_c2', _horasCargaC2.map((e) => e.toString()).toList());
    await prefs.setStringList('bs_horas_descarga_c2', _horasDescargaC2.map((e) => e.toString()).toList());
  }

  List<int> _rangoHoras(int inicio, int fin) {
    List<int> horas = [];
    int actual = inicio;
    while (true) {
      horas.add(actual);
      if (actual == fin) break;
      actual = (actual + 1) % 24;
    }
    return horas;
  }

  // Para un día concreto (24 precios), calcula el spread de un ciclo: en modo
  // "ventana" escoge las `duracion` horas más baratas/caras dentro del rango
  // dado; en modo "exacta" usa siempre las mismas horas fijas.
  Map<String, dynamic> _calcularCiclo(List<double> horasDia, int cargaIni, int cargaFin, int descargaIni, int descargaFin, Set<int> horasCargaFijas, Set<int> horasDescargaFijas, int duracion) {
    List<int> horasCarga;
    List<int> horasDescarga;
    if (_modoSeleccion == 'ventana') {
      List<int> ventanaCarga = _rangoHoras(cargaIni, cargaFin);
      ventanaCarga.sort((a, b) => horasDia[a].compareTo(horasDia[b]));
      horasCarga = ventanaCarga.take(duracion).toList();

      List<int> ventanaDescarga = _rangoHoras(descargaIni, descargaFin);
      ventanaDescarga.sort((a, b) => horasDia[b].compareTo(horasDia[a]));
      horasDescarga = ventanaDescarga.take(duracion).toList();
    } else {
      horasCarga = horasCargaFijas.toList();
      horasDescarga = horasDescargaFijas.toList();
    }

    double costoCarga = horasCarga.fold(0.0, (s, h) => s + horasDia[h]);
    double ingresoDescarga = horasDescarga.fold(0.0, (s, h) => s + horasDia[h]);
    double precioCargaProm = horasCarga.isNotEmpty ? costoCarga / horasCarga.length : 0.0;
    double precioDescargaProm = horasDescarga.isNotEmpty ? ingresoDescarga / horasDescarga.length : 0.0;
    double spreadBruto = ingresoDescarga - costoCarga;

    // Si ese día el spread no llega al mínimo (o es negativo), la batería no
    // opera ese ciclo: ni carga ni descarga, spread queda a 0.
    bool opera = spreadBruto >= _umbralMinimoSpread;

    List<int> horasCargaOrdenadas = List.from(horasCarga)..sort();
    List<int> horasDescargaOrdenadas = List.from(horasDescarga)..sort();
    String horasTexto(List<int> horas) => horas.map((h) => h.toString().padLeft(2, '0')).join('-');

    return {
      'precioCarga': opera ? precioCargaProm : 0.0,
      'precioDescarga': opera ? precioDescargaProm : 0.0,
      // Spread en €/MWh: comparable directo con Precio Carga/Descarga (su resta).
      // Spread en € (más abajo) es ese valor YA MULTIPLICADO por las horas de la
      // batería ese día — es el dinero total, no otro precio distinto.
      'spreadPorMwh': opera ? (precioDescargaProm - precioCargaProm) : 0.0,
      'horas': horasCarga.length,
      'spread': opera ? spreadBruto : 0.0,
      'opera': opera,
      'horasCarga': opera ? horasTexto(horasCargaOrdenadas) : '',
      'horasDescarga': opera ? horasTexto(horasDescargaOrdenadas) : '',
    };
  }

  Future<void> _calcular() async {
    setState(() {
      _calculando = true;
      _mensajeError = null;
    });

    final prefs = await SharedPreferences.getInstance();
    List<String>? preStrs = prefs.getStringList('precios_8760');
    if (preStrs == null || preStrs.length < 8760) {
      setState(() {
        _calculando = false;
        _mensajeError = 'Faltan precios de mercado. Ve a Inicio y descárgalos primero.';
        _resultadosDiarios = [];
      });
      return;
    }
    _precios8760 = preStrs.map((e) => double.parse(e)).toList();

    int duracion = int.tryParse(_duracionController.text) ?? 2;
    if (duracion < 1) duracion = 1;

    List<Map<String, dynamic>> filas = [];
    double sumaC1 = 0, sumaC2 = 0;
    List<double> sumaMensual = List.filled(12, 0.0);
    DateTime fechaBase = DateTime(DateTime.now().year - 1, 1, 1);
    int diaGlobal = 0;

    for (int m = 0; m < 12; m++) {
      for (int d = 0; d < _diasMes[m]; d++) {
        if (diaGlobal >= 365) break;
        List<double> horasDia = _precios8760.sublist(diaGlobal * 24, diaGlobal * 24 + 24);

        Map<String, dynamic> c1 = _calcularCiclo(horasDia, _cargaIniC1, _cargaFinC1, _descargaIniC1, _descargaFinC1, _horasCargaC1, _horasDescargaC1, duracion);
        Map<String, dynamic> c2 = _calcularCiclo(horasDia, _cargaIniC2, _cargaFinC2, _descargaIniC2, _descargaFinC2, _horasCargaC2, _horasDescargaC2, duracion);

        double spreadC1 = c1['spread'] as double;
        double spreadC2 = c2['spread'] as double;
        sumaC1 += spreadC1;
        sumaC2 += spreadC2;
        sumaMensual[m] += spreadC1 + spreadC2;

        DateTime fecha = fechaBase.add(Duration(days: diaGlobal));
        filas.add({
          'fecha': fecha,
          'precioCargaC1': c1['precioCarga'], 'precioDescargaC1': c1['precioDescarga'], 'spreadMwhC1': c1['spreadPorMwh'], 'horasC1': c1['horas'], 'spreadC1': spreadC1, 'operoC1': c1['opera'],
          'horasCargaC1': c1['horasCarga'], 'horasDescargaC1': c1['horasDescarga'],
          'precioCargaC2': c2['precioCarga'], 'precioDescargaC2': c2['precioDescarga'], 'spreadMwhC2': c2['spreadPorMwh'], 'horasC2': c2['horas'], 'spreadC2': spreadC2, 'operoC2': c2['opera'],
          'horasCargaC2': c2['horasCarga'], 'horasDescargaC2': c2['horasDescarga'],
          'spreadTotal': spreadC1 + spreadC2,
        });
        diaGlobal++;
      }
    }

    setState(() {
      _calculando = false;
      _resultadosDiarios = filas;
      spreadAnualC1 = formatoEuro(sumaC1);
      spreadAnualC2 = formatoEuro(sumaC2);
      spreadAnualTotal = formatoEuro(sumaC1 + sumaC2);
      spreadMedioDiaC1 = formatoEuro(sumaC1 / 365);
      spreadMedioDiaC2 = formatoEuro(sumaC2 / 365);
      _spreadMensual = sumaMensual;
    });
  }

  void _exportarCsv() {
    if (_resultadosDiarios.isEmpty) return;
    StringBuffer sb = StringBuffer();
    sb.writeln('Fecha;'
        'Horas Carga C1;Horas Descarga C1;Precio Carga C1 (€/MWh);Precio Descarga C1 (€/MWh);Spread C1 (€/MWh);Horas Batería C1;Spread Total C1 (€);Operó C1;'
        'Horas Carga C2;Horas Descarga C2;Precio Carga C2 (€/MWh);Precio Descarga C2 (€/MWh);Spread C2 (€/MWh);Horas Batería C2;Spread Total C2 (€);Operó C2;'
        'Spread Total Dia (€)');
    for (var fila in _resultadosDiarios) {
      DateTime f = fila['fecha'];
      String fechaStr = '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
      sb.writeln('$fechaStr;'
          '${fila['horasCargaC1']};${fila['horasDescargaC1']};${_csvNum(fila['precioCargaC1'])};${_csvNum(fila['precioDescargaC1'])};${_csvNum(fila['spreadMwhC1'])};${fila['horasC1']};${_csvNum(fila['spreadC1'])};${_siNo(fila['operoC1'])};'
          '${fila['horasCargaC2']};${fila['horasDescargaC2']};${_csvNum(fila['precioCargaC2'])};${_csvNum(fila['precioDescargaC2'])};${_csvNum(fila['spreadMwhC2'])};${fila['horasC2']};${_csvNum(fila['spreadC2'])};${_siNo(fila['operoC2'])};'
          '${_csvNum(fila['spreadTotal'])}');
    }
    final bytes = utf8.encode(sb.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'spread_baterias_standalone.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  String _csvNum(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  String _siNo(bool v) => v ? 'Sí' : 'No';

  Widget _chipHora(int hora, Set<int> seleccionadas, Color color, bool isDark) {
    bool activa = seleccionadas.contains(hora);
    return InkWell(
      onTap: () {
        setState(() {
          if (activa) {
            seleccionadas.remove(hora);
          } else {
            seleccionadas.add(hora);
          }
        });
        _guardar();
        _calcular();
      },
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: activa ? color : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: activa ? color : Colors.grey.withValues(alpha: 0.4)),
        ),
        child: Text('$hora', style: TextStyle(fontSize: 11, color: activa ? Colors.white : (isDark ? Colors.grey : Colors.black54), fontWeight: activa ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _selectorHorasExactas(String titulo, Set<int> horas, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
        const SizedBox(height: 6),
        Wrap(children: List.generate(24, (h) => _chipHora(h, horas, color, isDark))),
      ],
    );
  }

  Widget _dropdownHora(String label, int valor, ValueChanged<int> onChanged, bool isDark) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: DropdownButtonFormField<int>(
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(), labelStyle: const TextStyle(fontSize: 11)),
          items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00', style: const TextStyle(fontSize: 12)))),
          onChanged: (v) {
            onChanged(v!);
            _guardar();
            _calcular();
          },
        ),
      ),
    );
  }

  Widget _tarjetaCiclo(String titulo, bool isDark, {required int cargaIni, required int cargaFin, required int descargaIni, required int descargaFin, required ValueChanged<int> onCargaIni, required ValueChanged<int> onCargaFin, required ValueChanged<int> onDescargaIni, required ValueChanged<int> onDescargaFin, required Set<int> horasCargaFijas, required Set<int> horasDescargaFijas}) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.blueGrey)),
            const SizedBox(height: 12),
            if (_modoSeleccion == 'ventana') ...[
              Text('Ventana de Carga', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.black54)),
              Row(children: [_dropdownHora('Inicio', cargaIni, onCargaIni, isDark), _dropdownHora('Fin', cargaFin, onCargaFin, isDark)]),
              const SizedBox(height: 10),
              Text('Ventana de Descarga', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.black54)),
              Row(children: [_dropdownHora('Inicio', descargaIni, onDescargaIni, isDark), _dropdownHora('Fin', descargaFin, onDescargaFin, isDark)]),
            ] else ...[
              _selectorHorasExactas('Horas de Carga', horasCargaFijas, accentBlue, isDark),
              const SizedBox(height: 10),
              _selectorHorasExactas('Horas de Descarga', horasDescargaFijas, Colors.orange, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKPI(String titulo, String valor, String unidad, Color color, bool isDark) {
    return Card(
      elevation: isDark ? 6 : 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [color.withValues(alpha: 0.85), color], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Column(
          children: [
            Text(titulo, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Flexible(child: Text(valor, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Text(unidad, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('BATERÍAS STANDALONE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    child: Text('Arbitraje puro de precio de mercado: 2 ciclos de carga/descarga al día, sin FV.', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)),
                  ),
                  Card(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.blue.withValues(alpha: 0.3))),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Regla de operación: cada ciclo solo carga y descarga en los días donde el spread (ingreso de descarga − coste de carga) es de al menos ${formatoEuro(_umbralMinimoSpread, decimales: 0)} €. '
                              'Si ese día el spread sería menor o negativo, ese ciclo no opera (ni carga ni descarga) y su spread queda en 0 €.\n\n'
                              'En el CSV: "Precio Carga/Descarga" son la media €/MWh de esas horas. "Spread (€/MWh)" es la resta directa de esos dos precios. "Spread Total (€)" es ese mismo spread multiplicado por las horas de batería usadas ese ciclo — por eso puede parecer mucho mayor que la simple resta de los dos precios.',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ventana', label: Text('Ventana', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'exacta', label: Text('Horas Exactas', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_modoSeleccion},
                    onSelectionChanged: (s) {
                      setState(() => _modoSeleccion = s.first);
                      _guardar();
                      _calcular();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_modoSeleccion == 'ventana')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: TextFormField(
                        controller: _duracionController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        decoration: const InputDecoration(labelText: 'Duración Batería (horas)', suffixText: 'h', border: OutlineInputBorder(), isDense: true),
                        onFieldSubmitted: (_) {
                          _guardar();
                          _calcular();
                        },
                      ),
                    ),
                  _tarjetaCiclo('CICLO 1', isDark,
                      cargaIni: _cargaIniC1, cargaFin: _cargaFinC1, descargaIni: _descargaIniC1, descargaFin: _descargaFinC1,
                      onCargaIni: (v) => setState(() => _cargaIniC1 = v), onCargaFin: (v) => setState(() => _cargaFinC1 = v),
                      onDescargaIni: (v) => setState(() => _descargaIniC1 = v), onDescargaFin: (v) => setState(() => _descargaFinC1 = v),
                      horasCargaFijas: _horasCargaC1, horasDescargaFijas: _horasDescargaC1),
                  const SizedBox(height: 16),
                  _tarjetaCiclo('CICLO 2', isDark,
                      cargaIni: _cargaIniC2, cargaFin: _cargaFinC2, descargaIni: _descargaIniC2, descargaFin: _descargaFinC2,
                      onCargaIni: (v) => setState(() => _cargaIniC2 = v), onCargaFin: (v) => setState(() => _cargaFinC2 = v),
                      onDescargaIni: (v) => setState(() => _descargaIniC2 = v), onDescargaFin: (v) => setState(() => _descargaFinC2 = v),
                      horasCargaFijas: _horasCargaC2, horasDescargaFijas: _horasDescargaC2),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: [accentMagenta, accentBlue])),
                    child: ElevatedButton.icon(
                      onPressed: (_calculando || _resultadosDiarios.isEmpty) ? null : _exportarCsv,
                      icon: const Icon(Icons.download, color: Colors.white),
                      label: const Text('DESCARGAR CSV (SPREAD DIARIO)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mensajeError != null)
                    Card(
                      color: Colors.red.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.red)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.red), const SizedBox(width: 12), Expanded(child: Text(_mensajeError!, style: TextStyle(color: isDark ? Colors.white : Colors.black87)))]),
                      ),
                    )
                  else ...[
                    Row(children: [
                      Expanded(child: _buildKPI('SPREAD ANUAL CICLO 1', spreadAnualC1, '€/MW', accentBlue, isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPI('SPREAD ANUAL CICLO 2', spreadAnualC2, '€/MW', Colors.orange, isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPI('SPREAD ANUAL TOTAL', spreadAnualTotal, '€/MW', accentMagenta, isDark)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _buildKPI('SPREAD MEDIO/DÍA C1', spreadMedioDiaC1, '€/MW', accentBlue, isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPI('SPREAD MEDIO/DÍA C2', spreadMedioDiaC2, '€/MW', Colors.orange, isDark)),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 320,
                      child: Card(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: isDark ? 4 : 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Spread Mensual Acumulado (€/MW instalado)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                              const SizedBox(height: 16),
                              Expanded(
                                child: BarChart(
                                  BarChartData(
                                    minY: 0,
                                    barGroups: _spreadMensual.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: e.value, color: accentMagenta, width: 16, borderRadius: BorderRadius.circular(4))])).toList(),
                                    titlesData: FlTitlesData(
                                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (v, m) => Text(formatoEuro(v, decimales: 0), style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54)))),
                                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                                        int i = v.toInt();
                                        if (i < 0 || i > 11) return const SizedBox.shrink();
                                        return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_mesesAbrev[i], style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54)));
                                      })),
                                    ),
                                    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
                                    borderData: FlBorderData(show: false),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: isDark ? 4 : 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Primeros días del año (vista previa)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                            const SizedBox(height: 12),
                            Table(
                              columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
                              children: [
                                TableRow(children: [
                                  Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                                  Text('Spread C1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                                  Text('Spread C2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                                  Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                                ]),
                                ...(_resultadosDiarios.take(8).map((fila) {
                                  DateTime f = fila['fecha'];
                                  return TableRow(children: [
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54))),
                                    Text('${formatoEuro(fila['spreadC1'])} €', style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                                    Text('${formatoEuro(fila['spreadC2'])} €', style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)),
                                    Text('${formatoEuro(fila['spreadTotal'])} €', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                                  ]);
                                })),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
