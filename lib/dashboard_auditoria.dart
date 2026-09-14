import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardAuditoriaScreen extends StatefulWidget {
  const DashboardAuditoriaScreen({super.key});

  @override
  State<DashboardAuditoriaScreen> createState() => _DashboardAuditoriaScreenState();
}

class _DashboardAuditoriaScreenState extends State<DashboardAuditoriaScreen> {
  // Entradas de Auditoría Inversa
  final TextEditingController _potenciaController = TextEditingController();
  final TextEditingController _horasEqController = TextEditingController(); 
  final TextEditingController _bateriaInstController = TextEditingController(); 
  final TextEditingController _vidaUtilController = TextEditingController();
  final TextEditingController _degradacionController = TextEditingController();
  final TextEditingController _limiteInyController = TextEditingController();
  
  final TextEditingController _capexTotalController = TextEditingController(); 
  final TextEditingController _opexFijoController = TextEditingController();
  final TextEditingController _opexVariableController = TextEditingController();
  final TextEditingController _precioPpaController = TextEditingController();
  final TextEditingController _escaladaPrecioController = TextEditingController();
  final TextEditingController _anoReemplazoController = TextEditingController();
  final TextEditingController _costeReemplazoController = TextEditingController();

  Map<String, String> hInicioMes = {};
  Map<String, String> hFinMes = {};
  String _mesHorasSeleccionado = 'Enero';
  bool _mercadoGlobalActivo = true;

  // KPIs Auditoría
  String bloqueFijoMaxMostrar = '0,00';
  String bateriaInstaladaMostrar = '0,00';
  String lcoeMostrar = '0,00';
  String inyeccionRedMostrar = '0,00';
  String tirMostrar = '0,00';

  String ingresosPpaY1 = '0,00', ingresosMktY1 = '0,00', costeRedY1 = '0,00', opexY1 = '0,00';
  String capexTotalStr = '0,00', flujoCajaY1 = '0,00', totalGastosY1 = '0,00'; 
  
  String ingresosPpaLife = '0,00', ingresosMktLife = '0,00', costeRedLife = '0,00', opexLife = '0,00';
  String reemplazoLife = '0,00', beneficioNetoLife = '0,00', beneficioNetoTotalLife = '0,00';

  List<FlSpot> roiSpots = [];
  double minRoiY = 0;
  double maxRoiY = 0;

  final List<String> mesesNombres = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
  final List<int> diasMes = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  
  List<int> _mesDeCadaHora = List.filled(8760, 0);

  final Color accentMagenta = const Color(0xFFD80073);
  final Color accentBlue = const Color(0xFF0050EF);
  final LinearGradient brandGradient = const LinearGradient(colors: [Color(0xFFD80073), Color(0xFF0050EF)], begin: Alignment.centerLeft, end: Alignment.centerRight);

  @override
  void initState() {
    super.initState();
    _mapearMeses();
    _cargarYCalcularAuditoria();
  }

  void _mapearMeses() {
    int currentHour = 0;
    for (int m = 0; m < 12; m++) {
      for (int d = 0; d < diasMes[m]; d++) {
        for (int h = 0; h < 24; h++) {
          if (currentHour < 8760) {
            _mesDeCadaHora[currentHour] = m;
            currentHour++;
          }
        }
      }
    }
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

  double _calcularTIR(List<double> flujos) {
    double minRate = -0.99; 
    double maxRate = 100.0; 
    double guess = 0.0;
    
    for (int i = 0; i < 100; i++) {
      guess = (minRate + maxRate) / 2;
      double npv = 0.0;
      for (int t = 0; t < flujos.length; t++) {
        npv += flujos[t] / pow(1 + guess, t);
      }
      if (npv > 0) {
        minRate = guess;
      } else {
        maxRate = guess;
      }
    }
    return guess * 100; 
  }

  Future<void> _cargarYCalcularAuditoria() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _potenciaController.text = prefs.getString('potencia_fv_aud') ?? '13.47';
      _horasEqController.text = prefs.getString('horas_eq_aud') ?? '2100';
      _bateriaInstController.text = prefs.getString('bateria_inst_aud') ?? '22';
      _vidaUtilController.text = prefs.getString('vida_util_aud') ?? '25';
      _degradacionController.text = prefs.getString('degradacion_fv_aud') ?? '0.5';
      _limiteInyController.text = prefs.getString('limite_iny_aud') ?? '10'; 
      _capexTotalController.text = prefs.getString('capex_total_aud') ?? '10000000';
      _opexFijoController.text = prefs.getString('opex_fijo_aud') ?? '1500';
      _opexVariableController.text = prefs.getString('opex_var_aud') ?? '5';
      _precioPpaController.text = prefs.getString('precio_ppa_aud') ?? '40';
      _escaladaPrecioController.text = prefs.getString('escalada_precio_aud') ?? '2';
      _anoReemplazoController.text = prefs.getString('ano_reemplazo_aud') ?? '12';
      _costeReemplazoController.text = prefs.getString('coste_reemplazo_aud') ?? '100000';
      _mercadoGlobalActivo = prefs.getBool('mercado_activo_aud') ?? true;
      
      for (String m in mesesNombres) {
        hInicioMes[m] = prefs.getString('h_inicio_aud_$m') ?? '1';
        hFinMes[m] = prefs.getString('h_fin_aud_$m') ?? '4';
      }
    });
    await _ejecutarMatematicas8760Aud();
  }

  Future<void> _guardarParametros() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('potencia_fv_aud', _potenciaController.text);
    await prefs.setString('horas_eq_aud', _horasEqController.text);
    await prefs.setString('bateria_inst_aud', _bateriaInstController.text);
    await prefs.setString('vida_util_aud', _vidaUtilController.text);
    await prefs.setString('degradacion_fv_aud', _degradacionController.text);
    await prefs.setString('limite_iny_aud', _limiteInyController.text);
    await prefs.setString('capex_total_aud', _capexTotalController.text);
    await prefs.setString('opex_fijo_aud', _opexFijoController.text);
    await prefs.setString('opex_var_aud', _opexVariableController.text);
    await prefs.setString('precio_ppa_aud', _precioPpaController.text);
    await prefs.setString('escalada_precio_aud', _escaladaPrecioController.text);
    await prefs.setString('ano_reemplazo_aud', _anoReemplazoController.text);
    await prefs.setString('coste_reemplazo_aud', _costeReemplazoController.text);
    await prefs.setBool('mercado_activo_aud', _mercadoGlobalActivo);
    
    await prefs.setString('h_inicio_aud_$_mesHorasSeleccionado', hInicioMes[_mesHorasSeleccionado]!);
    await prefs.setString('h_fin_aud_$_mesHorasSeleccionado', hFinMes[_mesHorasSeleccionado]!);
    
    await _ejecutarMatematicas8760Aud();

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Auditoría Recalculada'), backgroundColor: accentMagenta, duration: const Duration(seconds: 1)));
  }

  Future<void> _aplicarHorasATodos() async {
    final prefs = await SharedPreferences.getInstance();
    String ini = hInicioMes[_mesHorasSeleccionado]!;
    String fin = hFinMes[_mesHorasSeleccionado]!;
    for (String m in mesesNombres) {
      hInicioMes[m] = ini;
      hFinMes[m] = fin;
      await prefs.setString('h_inicio_aud_$m', ini);
      await prefs.setString('h_fin_aud_$m', fin);
    }
    await _ejecutarMatematicas8760Aud();
  }

  // --- MOTOR 8760 AUDITORÍA INVERSA ---
  Future<void> _ejecutarMatematicas8760Aud() async {
    final prefs = await SharedPreferences.getInstance();
    
    List<String>? radStrs = prefs.getStringList('radiacion_8760');
    List<String>? preStrs = prefs.getStringList('precios_8760');

    if (radStrs == null || preStrs == null || radStrs.length < 8760 || preStrs.length < 8760) {
      setState(() {
        bloqueFijoMaxMostrar = "Faltan Datos";
        bateriaInstaladaMostrar = "Ve a Inicio";
      });
      return;
    }

    List<double> radiacionBase = radStrs.map((e) => double.parse(e)).toList();
    List<double> precios = preStrs.map((e) => double.parse(e)).toList();

    double pot = double.tryParse(_potenciaController.text.replaceAll(',', '.')) ?? 20.0;
    double horasEq = double.tryParse(_horasEqController.text.replaceAll(',', '.')) ?? 2100.0;
    double bateriaInst = double.tryParse(_bateriaInstController.text.replaceAll(',', '.')) ?? 40.0;
    int vidaUtil = int.tryParse(_vidaUtilController.text) ?? 25;
    double deg = double.tryParse(_degradacionController.text.replaceAll(',', '.')) ?? 0.5;
    double limitIny = double.tryParse(_limiteInyController.text.replaceAll(',', '.')) ?? 15.0;
    
    double capexTotal = double.tryParse(_capexTotalController.text.replaceAll(',', '.')) ?? 15000000;
    double opexFijo = double.tryParse(_opexFijoController.text.replaceAll(',', '.')) ?? 1500;
    double opexVar = double.tryParse(_opexVariableController.text.replaceAll(',', '.')) ?? 5;
    double precioPpa = double.tryParse(_precioPpaController.text.replaceAll(',', '.')) ?? 40;
    double escaladaPrecio = double.tryParse(_escaladaPrecioController.text.replaceAll(',', '.')) ?? 0.0;
    int anoReemplazo = int.tryParse(_anoReemplazoController.text) ?? 12;
    double costeReemplazo = double.tryParse(_costeReemplazoController.text.replaceAll(',', '.')) ?? 100000;

    // Escalar la radiación PVGIS para que cuadre con las Horas Equivalentes teóricas de auditoría
    double rBaseAnnual = radiacionBase.fold(0, (sum, item) => sum + item);
    double eTarget = pot * horasEq; 
    double factorEscala = rBaseAnnual > 0 ? (eTarget / rBaseAnnual) : 0;
    List<double> radiacion = radiacionBase.map((e) => e * factorEscala / pot).toList(); // Factorizado como factor de rendimiento

    // Generar array booleano de horas de mercado 8760
    List<bool> isMercadoActivoList = List.filled(8760, false);
    if (_mercadoGlobalActivo) {
      for (int h = 0; h < 8760; h++) {
        int mesIdx = _mesDeCadaHora[h];
        String nombreMes = mesesNombres[mesIdx];
        int hIni = int.tryParse(hInicioMes[nombreMes] ?? '1') ?? 1;
        int hFin = int.tryParse(hFinMes[nombreMes] ?? '4') ?? 4;
        
        int hrDia = h % 24;
        List<int> hList = [];
        int actual = hIni;
        while (true) {
          hList.add(actual);
          if (actual == hFin) break;
          actual = (actual + 1) % 24;
        }
        isMercadoActivoList[h] = hList.contains(hrDia);
      }
    }

    double totalGenY1 = 0;
    for(int h=0; h<8760; h++) {
       totalGenY1 += radiacion[h] * pot;
    }

    // 1. CÁLCULO DEL BLOQUE FIJO MÁXIMO CON BATERÍA LIMITADA
    double low = 0.0;
    double high = pot * 2.0; 
    double maxBaseload = 0.0;

    for (int iter = 0; iter < 50; iter++) {
      double mid = (low + high) / 2;
      bool aguantatTodoElAno = true;
      double soc = bateriaInst; // Batería finita real instalada

      for (int h = 0; h < 8760; h++) {
        double genHr = radiacion[h] * pot;
        bool inMkt = isMercadoActivoList[h];
        
        double net = inMkt ? genHr : (genHr - mid);
        soc += net;
        
        if (soc > bateriaInst) soc = bateriaInst;
        if (soc < 0.1 * bateriaInst) { 
          // En auditoría, se penaliza si la batería baja del 10% SOC estructural
          aguantatTodoElAno = false;
          break;
        }
      }

      if (aguantatTodoElAno) {
        maxBaseload = mid; 
        low = mid;
      } else {
        high = mid; 
      }
    }

    // 2. SIMULACIÓN DETALLADA DEL AÑO 1 CON RESTRICCIONES
    double totalInyY1 = 0.0, totalWastedY1 = 0.0, totalMktRevY1 = 0.0, totalGridCostY1 = 0.0;
    double socReal = bateriaInst;

    for (int h = 0; h < 8760; h++) {
      double genHr = radiacion[h] * pot;
      double precioHr = precios[h];
      bool inMkt = isMercadoActivoList[h];

      double net = inMkt ? genHr : (genHr - maxBaseload);
      double socNext = socReal + net;
      double curt = 0.0;
      double compMkt = inMkt ? maxBaseload : 0.0; 

      if (socNext > bateriaInst) {
        curt = socNext - bateriaInst;
        socNext = bateriaInst;
      }
      if (socNext < 0.1 * bateriaInst) socNext = 0.1 * bateriaInst;

      double injected = min(curt, limitIny);
      double wasted = curt - injected;
      
      totalInyY1 += injected; 
      totalWastedY1 += wasted;
      totalMktRevY1 += injected * precioHr; 
      totalGridCostY1 += compMkt * precioHr;

      socReal = socNext;
    }

    // 3. FINANZAS Y VIDA ÚTIL
    double opexTotalY1 = opexFijo + (opexVar * totalGenY1);
    double ppaRevAnual = maxBaseload * 24 * 365 * precioPpa;
    double avgMktPrice = totalInyY1 > 0 ? (totalMktRevY1 / totalInyY1) : 0;
    double baseCurtailment = totalInyY1 + totalWastedY1;

    List<FlSpot> spots = [];
    double cumulative = -capexTotal;
    spots.add(FlSpot(0, cumulative / 1000000));
    minRoiY = cumulative / 1000000;
    maxRoiY = 0;
    int paybackY = -1;
    
    double acuIngresosPpa = 0.0, acuIngresosMkt = 0.0, acuCosteRed = 0.0, acuOpex = 0.0, acuReemplazo = 0.0, totalGenLife = 0.0;
    List<double> flujosCaja = [-capexTotal];

    for (int y = 1; y <= vidaUtil; y++) {
      double degMult = pow(1 - (deg / 100), y - 1).toDouble();
      // Escalada anual del precio de la energía en el mercado (el PPA queda fijo: es un precio pactado)
      double escalMult = pow(1 + (escaladaPrecio / 100), y - 1).toDouble();
      double genY = totalGenY1 * degMult;
      double lostGen = totalGenY1 - genY;
      totalGenLife += genY;

      double curtY = max(0, baseCurtailment - lostGen);
      double inyY = min(curtY, totalInyY1);
      double mktRevY = inyY * avgMktPrice * escalMult;
      double gridCostY = totalGridCostY1 * escalMult;
      double opexY = opexFijo + (opexVar * genY);

      acuIngresosPpa += ppaRevAnual; acuIngresosMkt += mktRevY; acuCosteRed += gridCostY; acuOpex += opexY;

      double cf = ppaRevAnual + mktRevY - gridCostY - opexY;
      if (y == anoReemplazo) {
        double rep = (bateriaInst * costeReemplazo);
        cf -= rep;
        acuReemplazo += rep;
      }
      
      flujosCaja.add(cf);
      cumulative += cf;
      double cumM = cumulative / 1000000;
      spots.add(FlSpot(y.toDouble(), cumM));

      if (cumM < minRoiY) minRoiY = cumM;
      if (cumM > maxRoiY) maxRoiY = cumM;
      if (paybackY == -1 && cumulative >= 0) paybackY = y;
    }

    double tirCalculada = _calcularTIR(flujosCaja);
    double totalCosteLife = capexTotal + acuOpex + acuCosteRed + acuReemplazo;
    double lcoe = totalGenLife > 0 ? (totalCosteLife / totalGenLife) : 0.0;

    setState(() {
      bloqueFijoMaxMostrar = formatoEuro(maxBaseload);
      bateriaInstaladaMostrar = formatoEuro(bateriaInst);
      lcoeMostrar = formatoEuro(lcoe);
      inyeccionRedMostrar = formatoEuro(totalInyY1 / 1000); 
      tirMostrar = formatoEuro(tirCalculada);

      ingresosPpaY1 = formatoEuro(ppaRevAnual);
      ingresosMktY1 = formatoEuro(totalMktRevY1);
      // Negamos aquí: si hay muchas horas de precio negativo, comprar en el mercado
      // puede salir gratis o incluso generar ingreso, y el signo debe reflejarlo.
      costeRedY1 = formatoEuro(-totalGridCostY1);
      opexY1 = formatoEuro(opexTotalY1);
      totalGastosY1 = formatoEuro(totalGridCostY1 + opexTotalY1);
      capexTotalStr = formatoEuro(capexTotal);
      flujoCajaY1 = formatoEuro(ppaRevAnual + totalMktRevY1 - totalGridCostY1 - opexTotalY1);

      ingresosPpaLife = formatoEuro(acuIngresosPpa);
      ingresosMktLife = formatoEuro(acuIngresosMkt);
      costeRedLife = formatoEuro(-acuCosteRed);
      opexLife = formatoEuro(acuOpex);
      reemplazoLife = formatoEuro(acuReemplazo);
      beneficioNetoLife = formatoEuro(cumulative + capexTotal);
      beneficioNetoTotalLife = formatoEuro(cumulative); // Beneficio de operación menos el CAPEX inicial
      roiSpots = spots;
    });
  }

  void _mostrarTablaHoras(bool isDark) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.schedule, color: isDark ? accentMagenta : Colors.orange),
              const SizedBox(width: 10),
              Text('Horas Mercado Auditoría', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: mesesNombres.length,
              itemBuilder: (context, index) {
                String m = mesesNombres[index];
                return ListTile(
                  title: Text(m, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  trailing: Text(
                    '${hInicioMes[m]!.padLeft(2, '0')}:00 - ${hFinMes[m]!.padLeft(2, '0')}:00', 
                    style: TextStyle(color: isDark ? accentBlue : Colors.orange.shade900)
                  ),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar', style: TextStyle(color: isDark ? Colors.white : Colors.black87)))],
        );
      },
    );
  }

  void _mostrarExplicacion(String tipo, bool isDark) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              Icon(tipo == 'lcoe' || tipo == 'tir' ? Icons.account_balance : Icons.info, color: isDark ? accentMagenta : (tipo == 'lcoe' || tipo == 'tir' ? Colors.indigo : Colors.orange)),
              const SizedBox(width: 10),
              Text(
                tipo == 'bloque' ? 'Cálculo del Bloque Fijo' : tipo == 'lcoe' ? 'Cálculo del LCOE' : tipo == 'tir' ? 'Tasa Interna de Retorno (TIR)' : 'Cálculo de Batería',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tipo == 'bloque' 
                    ? 'Motor 8760h: Se evalúan las 8760 horas reales del año frente a la demanda, forzando a que la batería instalada real nunca baje del 10% SOC en todo el año. Se encuentra así el bloque fijo matemático máximo que puede entregar la planta auditada.'
                    : tipo == 'lcoe'
                    ? 'El LCOE (Levelized Cost of Energy) representa el coste medio de generar 1 MWh a lo largo de toda la vida del proyecto.\n\nFórmula:\n(CAPEX Total + OPEX Acumulado + Compras de Red + Reemplazo de Baterías) / Generación Fotovoltaica Total (con degradación).'
                    : tipo == 'tir'
                    ? 'La TIR es la tasa de descuento que hace que el Valor Actual Neto (VAN) de todos los flujos de caja del proyecto (inversión inicial e ingresos/gastos futuros) sea igual a cero.'
                    : 'Es el tamaño de batería nominal auditada introducida manualmente en los parámetros de la planta activa.',
                  style: TextStyle(height: 1.4, color: isDark ? Colors.grey : Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))),
          ],
        );
      },
    );
  }

  Widget _buildDropdownFieldStr(String label, String currentValue, List<String> items, ValueChanged<String?> onChanged, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              dropdownColor: Theme.of(context).colorScheme.surface,
              initialValue: currentValue,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentMagenta : Colors.orange.shade400)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentBlue : Colors.orange, width: 2)),
              ),
              items: items.map((item) => DropdownMenuItem(
                value: item,
                child: Align(alignment: Alignment.centerRight, child: Text(item, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFieldHoras(String label, String currentValue, ValueChanged<String?> onChanged, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: isDark ? Colors.grey : Colors.black87))),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              dropdownColor: Theme.of(context).colorScheme.surface,
              initialValue: currentValue,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.orange.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentBlue.withValues(alpha: 0.5) : Colors.orange.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentMagenta : Colors.orange, width: 2)),
              ),
              items: List.generate(24, (index) => DropdownMenuItem(
                value: index.toString(),
                child: Align(alignment: Alignment.centerRight, child: Text('${index.toString().padLeft(2, '0')}:00', style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87))),
              )),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionHeader(String titulo, IconData icono, Color colorClaro, bool isDark, {Widget? extraWidget}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icono, color: isDark ? accentBlue : colorClaro, size: 24),
              const SizedBox(width: 8),
              Text(titulo.toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : colorClaro, letterSpacing: 1.2)),
            ],
          ),
          if (extraWidget != null) extraWidget,
        ],
      ),
    );
  }

  Widget _buildInputCard(List<Widget> children, bool isDark) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16.0), child: Column(children: children)),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, String suffix, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: isDark ? Colors.grey : Colors.black87))),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done, 
              onFieldSubmitted: (_) => _guardarParametros(),
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                suffixText: ' $suffix',
                suffixStyle: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54),
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.green.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentBlue.withValues(alpha: 0.3) : Colors.green.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentMagenta : Colors.green, width: 2)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICardSimple(String titulo, String valor, String unidad, Color colorClaro, bool isDark, {VoidCallback? onTapIcon}) {
    return Card(
      elevation: isDark ? 6 : 4,
      shadowColor: isDark ? accentMagenta.withValues(alpha: 0.4) : colorClaro.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16), 
          gradient: isDark 
            ? brandGradient 
            : LinearGradient(colors: [colorClaro.withValues(alpha: 0.8), colorClaro], begin: Alignment.topLeft, end: Alignment.bottomRight)
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    titulo,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                ),
                if (onTapIcon != null) ...[
                  const SizedBox(width: 6),
                  InkWell(onTap: onTapIcon, child: const Icon(Icons.info_outline, color: Colors.white, size: 18)),
                ]
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(valor, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 4),
                Text(unidad, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaFinanzas(String concepto, String valor, bool isDark, {bool isBold = false, Color? colorClaro}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(concepto, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: isDark ? Colors.grey : Colors.black87, fontSize: 13)),
          Text(valor, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 14 : 13, color: isDark ? Colors.white : (colorClaro ?? Colors.black87))),
        ],
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
          // PANEL IZQUIERDO: INPUTS
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSeccionHeader('Parámetros de Planta Activa', Icons.engineering, Colors.indigo, isDark),
                  _buildInputCard([
                    _buildInputField('Potencia FV Instalada', _potenciaController, 'MW', isDark),
                    _buildInputField('Horas Equivalentes', _horasEqController, 'h/año', isDark),
                    _buildInputField('Batería Instalada', _bateriaInstController, 'MWh', isDark),
                    _buildInputField('Vida Útil Proyecto', _vidaUtilController, 'Años', isDark),
                  ], isDark),
                  const SizedBox(height: 16),
                  
                  _buildSeccionHeader('Degradación e Inyección', Icons.trending_down, Colors.teal, isDark),
                  _buildInputCard([
                    _buildInputField('Degradación Anual FV', _degradacionController, '%', isDark),
                    _buildInputField('Límite Inyección Red', _limiteInyController, 'MW', isDark),
                  ], isDark),
                  const SizedBox(height: 16),
                  
                  _buildSeccionHeader('Horas Mercado (Red)', Icons.access_time, Colors.orange, isDark,
                    extraWidget: IconButton(icon: Icon(Icons.info_outline, color: isDark ? accentMagenta : Colors.orange), onPressed: () => _mostrarTablaHoras(isDark))
                  ),
                  Card(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: isDark ? 4 : 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: Text('Permitir Entrada a Mercado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                            value: _mercadoGlobalActivo,
                            activeThumbColor: isDark ? accentMagenta : Colors.orange,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) {
                              setState(() => _mercadoGlobalActivo = val);
                              _guardarParametros();
                            },
                          ),
                          const Divider(),
                          _buildDropdownFieldStr('Mes a editar', _mesHorasSeleccionado, mesesNombres, (val) {
                            setState(() => _mesHorasSeleccionado = val!);
                          }, isDark),
                          _buildDropdownFieldHoras('Hora Inicio', hInicioMes[_mesHorasSeleccionado] ?? '1', (val) {
                            setState(() => hInicioMes[_mesHorasSeleccionado] = val!);
                            _guardarParametros();
                          }, isDark),
                          _buildDropdownFieldHoras('Hora Fin', hFinMes[_mesHorasSeleccionado] ?? '4', (val) {
                            setState(() => hFinMes[_mesHorasSeleccionado] = val!);
                            _guardarParametros();
                          }, isDark),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _aplicarHorasATodos,
                              icon: Icon(Icons.copy_all, size: 16, color: isDark ? Colors.white : Colors.orange),
                              label: Text('Aplicar a todos los meses', style: TextStyle(color: isDark ? Colors.white : Colors.orange)),
                              style: OutlinedButton.styleFrom(side: BorderSide(color: isDark ? accentMagenta : Colors.orange)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildSeccionHeader('Costes de la Planta', Icons.attach_money, Colors.green, isDark),
                  _buildInputCard([
                    _buildInputField('CAPEX Total Planta', _capexTotalController, '€', isDark),
                    _buildInputField('OPEX Fijo', _opexFijoController, '€/año', isDark), 
                    _buildInputField('OPEX Variable', _opexVariableController, '€/MWh', isDark),
                    _buildInputField('Precio Acuerdo PPA', _precioPpaController, '€/MWh', isDark),
                    _buildInputField('Escalada Precio Mercado', _escaladaPrecioController, '%/año', isDark),
                  ], isDark),
                  const SizedBox(height: 16),

                  _buildSeccionHeader('Reemplazo BESS', Icons.battery_charging_full, Colors.purple, isDark),
                  _buildInputCard([
                    _buildInputField('Año de Reemplazo', _anoReemplazoController, 'Años', isDark),
                    _buildInputField('Coste Reemplazo', _costeReemplazoController, '€/MWh', isDark),
                  ], isDark),
                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: isDark ? brandGradient : const LinearGradient(colors: [Colors.indigo, Colors.indigoAccent]),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _guardarParametros,
                      icon: const Icon(Icons.screen_search_desktop_rounded, color: Colors.white),
                      label: const Text('AUDITAR PLANTA (CALCULAR)', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 24),

          // PANEL DERECHO: RESULTADOS
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSeccionHeader('Auditoría Inversa y Retorno', Icons.analytics, Colors.blueGrey, isDark),
                  
                  // KPIs Row 1
                  Row(
                    children: [
                      Expanded(child: _buildKPICardSimple('BLOQUE FIJO MÁX', bloqueFijoMaxMostrar, 'MW', Colors.orange, isDark, onTapIcon: () => _mostrarExplicacion('bloque', isDark))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPICardSimple('BATERÍA INST.', bateriaInstaladaMostrar, 'MWh', Colors.purple, isDark, onTapIcon: () => _mostrarExplicacion('bateria', isDark))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPICardSimple('LCOE', lcoeMostrar, '€/MWh', Colors.indigo, isDark, onTapIcon: () => _mostrarExplicacion('lcoe', isDark))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPICardSimple('INYECCIÓN RED Y1', inyeccionRedMostrar, 'GWh', Colors.blue, isDark)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildKPICardSimple('TIR', tirMostrar, '%', Colors.teal, isDark, onTapIcon: () => _mostrarExplicacion('tir', isDark))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Resumen Financiero Row 2
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Card(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: isDark ? 4 : 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Resumen Financiero: AÑO 1', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                                Divider(color: isDark ? Colors.white24 : Colors.black12),
                                _buildFilaFinanzas('Ingresos PPA', '$ingresosPpaY1 €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Ingresos Mercado', '$ingresosMktY1 €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Coste Red (Mercado)', '$costeRedY1 €', isDark, colorClaro: costeRedY1.startsWith('-') ? Colors.red : Colors.green),
                                _buildFilaFinanzas('OPEX Anual', '-$opexY1 €', isDark, colorClaro: Colors.red),
                                Divider(color: isDark ? Colors.white24 : Colors.black12, thickness: 1),
                                _buildFilaFinanzas('Flujo de Caja Neto', '$flujoCajaY1 €', isDark, colorClaro: Colors.blueGrey, isBold: true),
                                const SizedBox(height: 12),
                                _buildFilaFinanzas('CAPEX Inicial Total', '-$capexTotalStr €', isDark, colorClaro: Colors.redAccent, isBold: true),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: isDark ? 4 : 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Resumen Vida Útil: ${_vidaUtilController.text} AÑOS', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                                Divider(color: isDark ? Colors.white24 : Colors.black12),
                                _buildFilaFinanzas('Total Ingresos PPA', '$ingresosPpaLife €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Total Mercado', '$ingresosMktLife €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Total Coste Red', '$costeRedLife €', isDark, colorClaro: costeRedLife.startsWith('-') ? Colors.red : Colors.green),
                                _buildFilaFinanzas('Total OPEX', '-$opexLife €', isDark, colorClaro: Colors.red),
                                _buildFilaFinanzas('Coste Reemplazo BESS', '-$reemplazoLife €', isDark, colorClaro: Colors.red),
                                Divider(color: isDark ? Colors.white24 : Colors.black12),
                                _buildFilaFinanzas('Beneficio de Operación', '$beneficioNetoLife €', isDark, colorClaro: Colors.blueGrey, isBold: true),
                                _buildFilaFinanzas('CAPEX Inicial Total', '-$capexTotalStr €', isDark, colorClaro: Colors.redAccent),
                                Divider(color: isDark ? Colors.white24 : Colors.black12, thickness: 1),
                                _buildFilaFinanzas(
                                  'Beneficio Neto Total',
                                  '$beneficioNetoTotalLife €',
                                  isDark,
                                  colorClaro: beneficioNetoTotalLife.startsWith('-') ? Colors.redAccent : Colors.green,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Gráfica de Retorno de Inversión (ROI)
                  SizedBox(
                    height: 400,
                    child: Card(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: isDark ? 4 : 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Evolución del Flujo de Caja Acumulado (M€)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                            const SizedBox(height: 16),
                            Expanded(
                              child: LineChart(
                                LineChartData(
                                  lineTouchData: LineTouchData(
                                    touchTooltipData: LineTouchTooltipData(
                                      getTooltipItems: (List<LineBarSpot> touchedSpots) => touchedSpots.map((spot) => LineTooltipItem('Año ${spot.x.toInt()}\n${formatoEuro(spot.y)} M€', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))).toList(),
                                    ),
                                  ),
                                  minX: 0, 
                                  maxX: double.tryParse(_vidaUtilController.text) ?? 25, 
                                  minY: minRoiY < 0 ? minRoiY * 1.1 : 0, 
                                  maxY: maxRoiY > 0 ? maxRoiY * 1.1 : 10,
                                  extraLinesData: ExtraLinesData(
                                    horizontalLines: [HorizontalLine(y: 0, color: isDark ? accentMagenta : Colors.red, strokeWidth: 2, dashArray: [5, 5])],
                                  ),
                                  gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
                                  titlesData: FlTitlesData(
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 5, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54))))),
                                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(formatoEuro(v, decimales: 1), style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54)))),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: roiSpots,
                                      isCurved: true, 
                                      color: isDark ? accentBlue : Colors.teal, 
                                      barWidth: 3, 
                                      dotData: const FlDotData(show: false),
                                      belowBarData: BarAreaData(
                                        show: true, 
                                        gradient: isDark 
                                          ? LinearGradient(colors: [accentBlue.withValues(alpha: 0.5), accentMagenta.withValues(alpha: 0.1)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                                          : null,
                                        color: isDark ? null : Colors.teal.withValues(alpha: 0.2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
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