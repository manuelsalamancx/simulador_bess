import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

/// Diseño óptimo: en vez de auditar una FV+batería reales, el usuario fija un
/// Bloque de Potencia objetivo y los costes unitarios de FV y batería, y el motor
/// busca la combinación FV+batería de menor CAPEX que sostiene ese bloque las 8760h
/// reales del año (mismo criterio de tolerancia cero que la Auditoría Inversa).
class DisenoOptimoAuditoriaScreen extends StatefulWidget {
  const DisenoOptimoAuditoriaScreen({super.key});

  @override
  State<DisenoOptimoAuditoriaScreen> createState() => _DisenoOptimoAuditoriaScreenState();
}

class _DisenoOptimoAuditoriaScreenState extends State<DisenoOptimoAuditoriaScreen> {
  final TextEditingController _bloqueObjetivoController = TextEditingController();
  final TextEditingController _horasEqController = TextEditingController();
  final TextEditingController _costeFvController = TextEditingController();
  final TextEditingController _costeBatController = TextEditingController();
  final TextEditingController _vidaUtilController = TextEditingController();
  final TextEditingController _degradacionController = TextEditingController();
  final TextEditingController _limiteInyController = TextEditingController();

  final TextEditingController _opexFijoController = TextEditingController();
  final TextEditingController _opexVariableController = TextEditingController();
  final TextEditingController _precioPpaController = TextEditingController();
  final TextEditingController _escaladaPrecioController = TextEditingController();
  final TextEditingController _anoReemplazoController = TextEditingController();
  final TextEditingController _costeReemplazoController = TextEditingController();

  // Modos "Solo FV" / "Solo Batería": aquí la FV y/o la batería son datos
  // directos (no se buscan), y en vez de un precio PPA fijo se resuelve el
  // LCOE (precio) que hace que la TIR del proyecto sea exactamente 5% o 10%.
  String _modo = 'optimizar'; // 'optimizar' | 'solo_fv' | 'solo_bateria'
  final TextEditingController _fvDirectaController = TextEditingController();
  final TextEditingController _costeFvKwController = TextEditingController();
  final TextEditingController _bateriaPotDirectaController = TextEditingController();
  final TextEditingController _bateriaMwhDirectaController = TextEditingController();
  final TextEditingController _costeBatValorController = TextEditingController();
  String _costeBatUnidad = 'kW'; // 'kW' | 'MW'
  String _tasaDetalle = '10'; // '5' | '10' | 'manual': qué precio se usa para el detalle mostrado

  String get _etiquetaDetalle => _tasaDetalle == '5' ? '5% TIR' : (_tasaDetalle == '10' ? '10% TIR' : 'PPA manual');

  Map<String, String> hInicioMes = {};
  Map<String, String> hFinMes = {};
  String _mesHorasSeleccionado = 'Enero';
  bool _mercadoGlobalActivo = true;
  bool _calculando = false;
  String? _mensajeError;

  // Resultado de la optimización
  String fvOptimaMostrar = '0,00';
  String bateriaOptimaMostrar = '0,00';
  String bloqueFijoMaxMostrar = '0,00';
  String lcoeMostrar = '0,00';
  String inyeccionRedMostrar = '0,00';
  String tirMostrar = '0,00';

  String ingresosPpaY1 = '0,00', ingresosMktY1 = '0,00', costeRedY1 = '0,00', opexY1 = '0,00';
  String capexTotalStr = '0,00', flujoCajaY1 = '0,00';

  String ingresosPpaLife = '0,00', ingresosMktLife = '0,00', costeRedLife = '0,00', opexLife = '0,00';
  String reemplazoLife = '0,00', beneficioNetoLife = '0,00', beneficioNetoTotalLife = '0,00';
  String lcoe5Mostrar = '0,00', lcoe10Mostrar = '0,00';

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
    _cargarYCalcular();
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

  Future<void> _cargarYCalcular() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bloqueObjetivoController.text = prefs.getString('bloque_objetivo_opt') ?? '2';
      _horasEqController.text = prefs.getString('horas_eq_opt') ?? '2100';
      _costeFvController.text = prefs.getString('coste_fv_opt') ?? '450000';
      _costeBatController.text = prefs.getString('coste_bat_opt') ?? '150000';
      _vidaUtilController.text = prefs.getString('vida_util_opt') ?? '25';
      _degradacionController.text = prefs.getString('degradacion_opt') ?? '0.5';
      _limiteInyController.text = prefs.getString('limite_iny_opt') ?? '10';
      _opexFijoController.text = prefs.getString('opex_fijo_opt') ?? '1500';
      _opexVariableController.text = prefs.getString('opex_var_opt') ?? '5';
      _precioPpaController.text = prefs.getString('precio_ppa_opt') ?? '40';
      _escaladaPrecioController.text = prefs.getString('escalada_precio_opt') ?? '2';
      _anoReemplazoController.text = prefs.getString('ano_reemplazo_opt') ?? '12';
      _costeReemplazoController.text = prefs.getString('coste_reemplazo_opt') ?? '100000';
      _mercadoGlobalActivo = prefs.getBool('mercado_activo_opt') ?? true;

      _modo = prefs.getString('modo_opt') ?? 'optimizar';
      _fvDirectaController.text = prefs.getString('fv_directa_opt') ?? '10';
      _costeFvKwController.text = prefs.getString('coste_fv_kw_opt') ?? '450';
      _bateriaPotDirectaController.text = prefs.getString('bateria_pot_directa_opt') ?? '2';
      _bateriaMwhDirectaController.text = prefs.getString('bateria_mwh_directa_opt') ?? '8';
      _costeBatValorController.text = prefs.getString('coste_bat_valor_opt') ?? '150';
      _costeBatUnidad = prefs.getString('coste_bat_unidad_opt') ?? 'kW';
      _tasaDetalle = prefs.getString('tasa_detalle_opt') ?? '10';

      for (String m in mesesNombres) {
        hInicioMes[m] = prefs.getString('h_inicio_opt_$m') ?? '1';
        hFinMes[m] = prefs.getString('h_fin_opt_$m') ?? '4';
      }
    });
    await _guardarYCalcular();
  }

  Future<void> _guardarYCalcular() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bloque_objetivo_opt', _bloqueObjetivoController.text);
    await prefs.setString('horas_eq_opt', _horasEqController.text);
    await prefs.setString('coste_fv_opt', _costeFvController.text);
    await prefs.setString('coste_bat_opt', _costeBatController.text);
    await prefs.setString('vida_util_opt', _vidaUtilController.text);
    await prefs.setString('degradacion_opt', _degradacionController.text);
    await prefs.setString('limite_iny_opt', _limiteInyController.text);
    await prefs.setString('opex_fijo_opt', _opexFijoController.text);
    await prefs.setString('opex_var_opt', _opexVariableController.text);
    await prefs.setString('precio_ppa_opt', _precioPpaController.text);
    await prefs.setString('escalada_precio_opt', _escaladaPrecioController.text);
    await prefs.setString('ano_reemplazo_opt', _anoReemplazoController.text);
    await prefs.setString('coste_reemplazo_opt', _costeReemplazoController.text);
    await prefs.setBool('mercado_activo_opt', _mercadoGlobalActivo);
    await prefs.setString('h_inicio_opt_$_mesHorasSeleccionado', hInicioMes[_mesHorasSeleccionado] ?? '1');
    await prefs.setString('h_fin_opt_$_mesHorasSeleccionado', hFinMes[_mesHorasSeleccionado] ?? '4');

    await prefs.setString('modo_opt', _modo);
    await prefs.setString('fv_directa_opt', _fvDirectaController.text);
    await prefs.setString('coste_fv_kw_opt', _costeFvKwController.text);
    await prefs.setString('bateria_pot_directa_opt', _bateriaPotDirectaController.text);
    await prefs.setString('bateria_mwh_directa_opt', _bateriaMwhDirectaController.text);
    await prefs.setString('coste_bat_valor_opt', _costeBatValorController.text);
    await prefs.setString('coste_bat_unidad_opt', _costeBatUnidad);
    await prefs.setString('tasa_detalle_opt', _tasaDetalle);

    if (_modo == 'solo_fv') {
      await _calcularEscenarioDirecto(conBateria: false);
    } else if (_modo == 'solo_bateria') {
      await _calcularEscenarioDirecto(conBateria: true);
    } else {
      await _optimizarDiseno();
    }
  }

  Future<void> _aplicarHorasATodos() async {
    final prefs = await SharedPreferences.getInstance();
    String ini = hInicioMes[_mesHorasSeleccionado] ?? '1';
    String fin = hFinMes[_mesHorasSeleccionado] ?? '4';
    for (String m in mesesNombres) {
      hInicioMes[m] = ini;
      hFinMes[m] = fin;
      await prefs.setString('h_inicio_opt_$m', ini);
      await prefs.setString('h_fin_opt_$m', fin);
    }
    await _optimizarDiseno();
  }

  // ¿Sostiene una batería+FV concretas el bloque objetivo las 8760h reales, sin bajar
  // nunca del 10% de SOC? (mismo criterio que la Auditoría Inversa)
  bool _esFactible(double pot, double bateriaInst, double bloqueObjetivo, List<double> radiacion, List<bool> isMercadoActivoList) {
    double soc = bateriaInst;
    for (int h = 0; h < 8760; h++) {
      double genHr = radiacion[h] * pot;
      double net = isMercadoActivoList[h] ? genHr : (genHr - bloqueObjetivo);
      soc += net;
      if (soc > bateriaInst) soc = bateriaInst;
      if (soc < 0.1 * bateriaInst) return false;
    }
    return true;
  }

  // FV mínima que sostiene el bloque objetivo con una batería dada. Devuelve null si
  // ninguna FV (por grande que sea) lo consigue con esa batería.
  double? _buscarPotenciaMinima(double bloqueObjetivo, double bateriaInst, List<double> radiacion, List<bool> isMercadoActivoList) {
    double high = bloqueObjetivo > 0 ? bloqueObjetivo : 1.0;
    int expandIter = 0;
    while (!_esFactible(high, bateriaInst, bloqueObjetivo, radiacion, isMercadoActivoList) && expandIter < 45) {
      high *= 2;
      expandIter++;
    }
    if (!_esFactible(high, bateriaInst, bloqueObjetivo, radiacion, isMercadoActivoList)) return null;

    double low = 0.0;
    for (int iter = 0; iter < 45; iter++) {
      double mid = (low + high) / 2;
      if (_esFactible(mid, bateriaInst, bloqueObjetivo, radiacion, isMercadoActivoList)) {
        high = mid;
      } else {
        low = mid;
      }
    }
    return high;
  }

  // La batería mínima absoluta que necesitarías aunque instalaras FV infinita: la mayor
  // "sangría" acumulada de horas sin mercado y sin luz (las horas de mercado ni drenan
  // ni permiten recargar, así que no rompen la racha de "sin recarga posible").
  double _calcularBateriaMinimaAbsoluta(double bloqueObjetivo, List<double> radiacion, List<bool> isMercadoActivoList) {
    double maxDrenaje = 0.0;
    double drenajeActual = 0.0;
    for (int i = 0; i < 8760 * 2; i++) {
      int h = i % 8760;
      if (radiacion[h] <= 0.0) {
        if (!isMercadoActivoList[h]) drenajeActual += bloqueObjetivo;
        if (drenajeActual > maxDrenaje) maxDrenaje = drenajeActual;
      } else {
        drenajeActual = 0.0;
      }
    }
    return maxDrenaje / 0.9;
  }

  List<bool> _construirMercadoActivo() {
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
    return isMercadoActivoList;
  }

  // Simula un año (8760h) con una FV y batería DADAS (no se buscan). Sin
  // batería (bateriaInst=0) es el escenario "Solo FV": lo que sobra se vende
  // a mercado, lo que falta se compra de mercado, hora a hora. Con batería,
  // esta amortigua primero y solo se recurre a la red cuando se agota (o se
  // llena) — el "1 ciclo/día" natural de carga de día y descarga de noche.
  Map<String, double> _simularAnio(double pot, double bateriaInst, double bloqueObjetivo, List<double> radiacion, List<double> precios, List<bool> isMercadoActivoList, double limitIny) {
    double soc = bateriaInst;
    double totalGen = 0, totalIny = 0, totalWasted = 0, totalMktRev = 0, totalGridCost = 0;
    for (int h = 0; h < 8760; h++) {
      double genHr = radiacion[h] * pot;
      totalGen += genHr;
      double precioHr = precios[h];
      bool inMkt = isMercadoActivoList[h];
      double socNext;
      double compraRedBase;
      if (inMkt) {
        socNext = soc + genHr;
        compraRedBase = bloqueObjetivo;
      } else {
        socNext = soc + (genHr - bloqueObjetivo);
        compraRedBase = 0;
      }
      double curt = 0;
      if (socNext > bateriaInst) {
        curt = socNext - bateriaInst;
        socNext = bateriaInst;
      }
      double extra = 0;
      if (socNext < 0) {
        extra = -socNext;
        socNext = 0;
      }
      double injected = min(curt, limitIny);
      double wasted = curt - injected;
      totalIny += injected;
      totalWasted += wasted;
      totalMktRev += injected * precioHr;
      totalGridCost += (compraRedBase + extra) * precioHr;
      soc = socNext;
    }
    return {'gen': totalGen, 'iny': totalIny, 'wasted': totalWasted, 'mktRev': totalMktRev, 'gridCost': totalGridCost};
  }

  // Modos "Solo FV" / "Solo Batería": FV (y batería) son datos directos. En vez
  // de asumir un precio PPA, se resuelve algebraicamente el precio (LCOE) que
  // hace VAN=0 a una tasa objetivo fija (5% y 10%): como los ingresos PPA son
  // lineales en el precio (bloque × 8760h × precio cada año) y el resto de la
  // caja no depende del precio, VAN(r) = a(r) + b(r)·precio es una recta, y el
  // precio que la anula sale de forma directa (sin bisección ni tanteo).
  Future<void> _calcularEscenarioDirecto({required bool conBateria}) async {
    setState(() {
      _calculando = true;
      _mensajeError = null;
    });

    final prefs = await SharedPreferences.getInstance();
    List<String>? radStrs = prefs.getStringList('radiacion_8760');
    List<String>? preStrs = prefs.getStringList('precios_8760');

    if (radStrs == null || preStrs == null || radStrs.length < 8760 || preStrs.length < 8760) {
      setState(() {
        _calculando = false;
        fvOptimaMostrar = 'Faltan Datos';
        bateriaOptimaMostrar = 'Ve a Inicio';
      });
      return;
    }

    List<double> radiacionBase = radStrs.map((e) => double.parse(e)).toList();
    List<double> precios = preStrs.map((e) => double.parse(e)).toList();

    double bloqueObjetivo = double.tryParse(_bloqueObjetivoController.text.replaceAll(',', '.')) ?? 1.0;
    double horasEq = double.tryParse(_horasEqController.text.replaceAll(',', '.')) ?? 2100.0;
    double pot = double.tryParse(_fvDirectaController.text.replaceAll(',', '.')) ?? 0.0;
    double bateriaPotMW = conBateria ? (double.tryParse(_bateriaPotDirectaController.text.replaceAll(',', '.')) ?? 0.0) : 0.0;
    double bateriaInst = conBateria ? (double.tryParse(_bateriaMwhDirectaController.text.replaceAll(',', '.')) ?? 0.0) : 0.0;
    int vidaUtil = int.tryParse(_vidaUtilController.text) ?? 25;
    double deg = double.tryParse(_degradacionController.text.replaceAll(',', '.')) ?? 0.5;
    double limitIny = double.tryParse(_limiteInyController.text.replaceAll(',', '.')) ?? 15.0;
    double opexFijo = double.tryParse(_opexFijoController.text.replaceAll(',', '.')) ?? 1500;
    double opexVar = double.tryParse(_opexVariableController.text.replaceAll(',', '.')) ?? 5;
    double escaladaPrecio = double.tryParse(_escaladaPrecioController.text.replaceAll(',', '.')) ?? 0.0;
    int anoReemplazo = int.tryParse(_anoReemplazoController.text) ?? 12;
    double costeReemplazoUnit = double.tryParse(_costeReemplazoController.text.replaceAll(',', '.')) ?? 100000;

    double capexTotal;
    if (conBateria) {
      double costeBatValor = double.tryParse(_costeBatValorController.text.replaceAll(',', '.')) ?? 0.0;
      double costeBatPorMW = _costeBatUnidad == 'kW' ? costeBatValor * 1000 : costeBatValor;
      capexTotal = bateriaPotMW * costeBatPorMW;
    } else {
      double costeFvKw = double.tryParse(_costeFvKwController.text.replaceAll(',', '.')) ?? 0.0;
      capexTotal = pot * 1000 * costeFvKw;
    }

    double rBaseAnnual = radiacionBase.fold(0.0, (sum, item) => sum + item);
    List<double> radiacion = rBaseAnnual > 0 ? radiacionBase.map((e) => e * horasEq / rBaseAnnual).toList() : List.filled(8760, 0.0);
    // "Solo FV" no tiene batería: no existen "horas de entrada a mercado" como
    // ventana de arbitraje (eso solo tiene sentido si hay batería que aprovechar).
    // Cada hora se resuelve solo por generación vs bloque: sobra → se vende a
    // mercado; falta (incluida toda hora sin sol) → se compra a mercado.
    List<bool> isMercadoActivoList = conBateria ? _construirMercadoActivo() : List.filled(8760, false);

    double kPpaPorAnio = bloqueObjetivo * 24 * 365;

    List<double> flujosBaseSinPpa = [];
    List<double> gridCostPorAnio = [], mktRevPorAnio = [], opexPorAnio = [], genPorAnio = [], inyPorAnio = [];
    double acuOpex = 0.0, acuReemplazo = 0.0, totalGenLife = 0.0;

    for (int y = 1; y <= vidaUtil; y++) {
      double degMult = pow(1 - (deg / 100), y - 1).toDouble();
      double potY = pot * degMult;
      Map<String, double> res = _simularAnio(potY, bateriaInst, bloqueObjetivo, radiacion, precios, isMercadoActivoList, limitIny);
      double escalMult = pow(1 + (escaladaPrecio / 100), y - 1).toDouble();
      double mktRevY = res['mktRev']! * escalMult;
      double gridCostY = res['gridCost']! * escalMult;
      double opexY = opexFijo + (opexVar * res['gen']!);
      double rep = 0.0;
      if (conBateria && y == anoReemplazo) {
        rep = bateriaInst * costeReemplazoUnit;
        acuReemplazo += rep;
      }
      flujosBaseSinPpa.add(mktRevY - gridCostY - opexY - rep);
      gridCostPorAnio.add(gridCostY);
      mktRevPorAnio.add(mktRevY);
      opexPorAnio.add(opexY);
      genPorAnio.add(res['gen']!);
      inyPorAnio.add(res['iny']!);
      acuOpex += opexY;
      totalGenLife += res['gen']!;
    }

    double resolverPrecio(double tasa) {
      double a = -capexTotal;
      double b = 0.0;
      for (int y = 1; y <= vidaUtil; y++) {
        double disc = pow(1 + tasa, y).toDouble();
        b += kPpaPorAnio / disc;
        a += flujosBaseSinPpa[y - 1] / disc;
      }
      return b != 0 ? -a / b : 0.0;
    }

    double precio5 = resolverPrecio(0.05);
    double precio10 = resolverPrecio(0.10);
    double precioManual = double.tryParse(_precioPpaController.text.replaceAll(',', '.')) ?? 0.0;
    double precioDetalle = _tasaDetalle == '5' ? precio5 : (_tasaDetalle == '10' ? precio10 : precioManual);
    double ppaRevAnual = kPpaPorAnio * precioDetalle;

    List<FlSpot> spots = [FlSpot(0, -capexTotal / 1000000)];
    double cumulative = -capexTotal;
    minRoiY = cumulative / 1000000;
    maxRoiY = 0;
    double acuIngresosPpa = 0.0, acuIngresosMkt = 0.0, acuCosteRed = 0.0;
    List<double> flujosCaja = [-capexTotal];

    for (int y = 1; y <= vidaUtil; y++) {
      double cf = ppaRevAnual + flujosBaseSinPpa[y - 1];
      acuIngresosPpa += ppaRevAnual;
      acuIngresosMkt += mktRevPorAnio[y - 1];
      acuCosteRed += gridCostPorAnio[y - 1];
      flujosCaja.add(cf);
      cumulative += cf;
      double cumM = cumulative / 1000000;
      spots.add(FlSpot(y.toDouble(), cumM));
      if (cumM < minRoiY) minRoiY = cumM;
      if (cumM > maxRoiY) maxRoiY = cumM;
    }

    double tirCalculada = _calcularTIR(flujosCaja);
    double totalCosteLife = capexTotal + acuOpex + acuCosteRed + acuReemplazo;
    double lcoeClasico = totalGenLife > 0 ? (totalCosteLife / totalGenLife) : 0.0;

    setState(() {
      _calculando = false;
      fvOptimaMostrar = formatoEuro(pot);
      bateriaOptimaMostrar = formatoEuro(bateriaInst);
      bloqueFijoMaxMostrar = formatoEuro(bloqueObjetivo);
      lcoe5Mostrar = formatoEuro(precio5);
      lcoe10Mostrar = formatoEuro(precio10);
      lcoeMostrar = formatoEuro(lcoeClasico);
      inyeccionRedMostrar = formatoEuro(inyPorAnio[0] / 1000);
      tirMostrar = formatoEuro(tirCalculada);

      ingresosPpaY1 = formatoEuro(ppaRevAnual);
      ingresosMktY1 = formatoEuro(mktRevPorAnio[0]);
      costeRedY1 = formatoEuro(-gridCostPorAnio[0]);
      opexY1 = formatoEuro(opexPorAnio[0]);
      capexTotalStr = formatoEuro(capexTotal);
      flujoCajaY1 = formatoEuro(flujosCaja[1]);

      ingresosPpaLife = formatoEuro(acuIngresosPpa);
      ingresosMktLife = formatoEuro(acuIngresosMkt);
      costeRedLife = formatoEuro(-acuCosteRed);
      opexLife = formatoEuro(acuOpex);
      reemplazoLife = formatoEuro(acuReemplazo);
      beneficioNetoLife = formatoEuro(cumulative + capexTotal);
      beneficioNetoTotalLife = formatoEuro(cumulative);
      roiSpots = spots;
    });
  }

  Future<void> _optimizarDiseno() async {
    setState(() {
      _calculando = true;
      _mensajeError = null;
    });

    final prefs = await SharedPreferences.getInstance();
    List<String>? radStrs = prefs.getStringList('radiacion_8760');
    List<String>? preStrs = prefs.getStringList('precios_8760');

    if (radStrs == null || preStrs == null || radStrs.length < 8760 || preStrs.length < 8760) {
      setState(() {
        _calculando = false;
        fvOptimaMostrar = 'Faltan Datos';
        bateriaOptimaMostrar = 'Ve a Inicio';
      });
      return;
    }

    List<double> radiacionBase = radStrs.map((e) => double.parse(e)).toList();
    List<double> precios = preStrs.map((e) => double.parse(e)).toList();

    double bloqueObjetivo = double.tryParse(_bloqueObjetivoController.text.replaceAll(',', '.')) ?? 1.0;
    double horasEq = double.tryParse(_horasEqController.text.replaceAll(',', '.')) ?? 2100.0;
    double costeFv = double.tryParse(_costeFvController.text.replaceAll(',', '.')) ?? 450000;
    double costeBat = double.tryParse(_costeBatController.text.replaceAll(',', '.')) ?? 150000;
    int vidaUtil = int.tryParse(_vidaUtilController.text) ?? 25;
    double deg = double.tryParse(_degradacionController.text.replaceAll(',', '.')) ?? 0.5;
    double limitIny = double.tryParse(_limiteInyController.text.replaceAll(',', '.')) ?? 15.0;
    double opexFijo = double.tryParse(_opexFijoController.text.replaceAll(',', '.')) ?? 1500;
    double opexVar = double.tryParse(_opexVariableController.text.replaceAll(',', '.')) ?? 5;
    double precioPpa = double.tryParse(_precioPpaController.text.replaceAll(',', '.')) ?? 40;
    double escaladaPrecio = double.tryParse(_escaladaPrecioController.text.replaceAll(',', '.')) ?? 0.0;
    int anoReemplazo = int.tryParse(_anoReemplazoController.text) ?? 12;
    double costeReemplazo = double.tryParse(_costeReemplazoController.text.replaceAll(',', '.')) ?? 100000;

    double rBaseAnnual = radiacionBase.fold(0, (sum, item) => sum + item);
    // radiacion[h] no depende de la FV: es la forma horaria real del recurso solar,
    // reescalada para que su suma anual sea "Horas Equivalentes".
    List<double> radiacion = rBaseAnnual > 0 ? radiacionBase.map((e) => e * horasEq / rBaseAnnual).toList() : List.filled(8760, 0.0);

    List<bool> isMercadoActivoList = _construirMercadoActivo();

    // 1. Batería mínima absoluta (aunque instalaras FV infinita)
    double bateriaMinAbs = _calcularBateriaMinimaAbsoluta(bloqueObjetivo, radiacion, isMercadoActivoList);
    if (bateriaMinAbs <= 0) bateriaMinAbs = 0.01;

    // 2. Búsqueda ternaria del tamaño de batería que minimiza el CAPEX total
    //    (FV_mínima(batería)*costeFv + batería*costeBat).
    double costoTotal(double bateria) {
      double? fv = _buscarPotenciaMinima(bloqueObjetivo, bateria, radiacion, isMercadoActivoList);
      if (fv == null) return double.infinity;
      return fv * costeFv + bateria * costeBat;
    }

    double lo = bateriaMinAbs * 1.001;
    double hi = bateriaMinAbs * 20 + 100;
    for (int i = 0; i < 40; i++) {
      double m1 = lo + (hi - lo) / 3;
      double m2 = hi - (hi - lo) / 3;
      if (costoTotal(m1) <= costoTotal(m2)) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    double bateriaOptima = (lo + hi) / 2;
    double? fvOptima = _buscarPotenciaMinima(bloqueObjetivo, bateriaOptima, radiacion, isMercadoActivoList);

    if (fvOptima == null) {
      setState(() {
        _calculando = false;
        _mensajeError = 'No se ha encontrado una combinación válida. Prueba a subir el límite de batería o bajar el Bloque de Potencia Objetivo.';
        fvOptimaMostrar = '-';
        bateriaOptimaMostrar = '-';
      });
      return;
    }

    double pot = fvOptima;
    double bateriaInst = bateriaOptima;
    double capexTotal = pot * costeFv + bateriaInst * costeBat;

    double totalGenY1 = 0;
    for (int h = 0; h < 8760; h++) {
      totalGenY1 += radiacion[h] * pot;
    }

    // Bloque Fijo Máx real con la combinación encontrada (debería coincidir con el objetivo)
    double low2 = 0.0, high2 = pot * 2.0, maxBaseload = 0.0;
    for (int iter = 0; iter < 50; iter++) {
      double mid = (low2 + high2) / 2;
      bool aguanta = true;
      double soc = bateriaInst;
      for (int h = 0; h < 8760; h++) {
        double genHr = radiacion[h] * pot;
        bool inMkt = isMercadoActivoList[h];
        double net = inMkt ? genHr : (genHr - mid);
        soc += net;
        if (soc > bateriaInst) soc = bateriaInst;
        if (soc < 0.1 * bateriaInst) {
          aguanta = false;
          break;
        }
      }
      if (aguanta) {
        maxBaseload = mid;
        low2 = mid;
      } else {
        high2 = mid;
      }
    }

    // Simulación detallada Año 1
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

    double opexTotalY1 = opexFijo + (opexVar * totalGenY1);
    double ppaRevAnual = maxBaseload * 24 * 365 * precioPpa;
    double avgMktPrice = totalInyY1 > 0 ? (totalMktRevY1 / totalInyY1) : 0;
    double baseCurtailment = totalInyY1 + totalWastedY1;

    List<FlSpot> spots = [];
    double cumulative = -capexTotal;
    spots.add(FlSpot(0, cumulative / 1000000));
    minRoiY = cumulative / 1000000;
    maxRoiY = 0;

    double acuIngresosPpa = 0.0, acuIngresosMkt = 0.0, acuCosteRed = 0.0, acuOpex = 0.0, acuReemplazo = 0.0, totalGenLife = 0.0;
    List<double> flujosCaja = [-capexTotal];

    for (int y = 1; y <= vidaUtil; y++) {
      double degMult = pow(1 - (deg / 100), y - 1).toDouble();
      double escalMult = pow(1 + (escaladaPrecio / 100), y - 1).toDouble();
      double genY = totalGenY1 * degMult;
      double lostGen = totalGenY1 - genY;
      totalGenLife += genY;

      double curtY = max(0, baseCurtailment - lostGen);
      double inyY = min(curtY, totalInyY1);
      double mktRevY = inyY * avgMktPrice * escalMult;
      double gridCostY = totalGridCostY1 * escalMult;
      double opexY = opexFijo + (opexVar * genY);

      acuIngresosPpa += ppaRevAnual;
      acuIngresosMkt += mktRevY;
      acuCosteRed += gridCostY;
      acuOpex += opexY;

      double cf = ppaRevAnual + mktRevY - gridCostY - opexY;
      if (y == anoReemplazo) {
        double rep = bateriaInst * costeReemplazo;
        cf -= rep;
        acuReemplazo += rep;
      }

      flujosCaja.add(cf);
      cumulative += cf;
      double cumM = cumulative / 1000000;
      spots.add(FlSpot(y.toDouble(), cumM));
      if (cumM < minRoiY) minRoiY = cumM;
      if (cumM > maxRoiY) maxRoiY = cumM;
    }

    double tirCalculada = _calcularTIR(flujosCaja);
    double totalCosteLife = capexTotal + acuOpex + acuCosteRed + acuReemplazo;
    double lcoe = totalGenLife > 0 ? (totalCosteLife / totalGenLife) : 0.0;

    setState(() {
      _calculando = false;
      fvOptimaMostrar = formatoEuro(pot);
      bateriaOptimaMostrar = formatoEuro(bateriaInst);
      bloqueFijoMaxMostrar = formatoEuro(maxBaseload);
      lcoeMostrar = formatoEuro(lcoe);
      inyeccionRedMostrar = formatoEuro(totalInyY1 / 1000);
      tirMostrar = formatoEuro(tirCalculada);

      ingresosPpaY1 = formatoEuro(ppaRevAnual);
      ingresosMktY1 = formatoEuro(totalMktRevY1);
      costeRedY1 = formatoEuro(-totalGridCostY1);
      opexY1 = formatoEuro(opexTotalY1);
      capexTotalStr = formatoEuro(capexTotal);
      flujoCajaY1 = formatoEuro(ppaRevAnual + totalMktRevY1 - totalGridCostY1 - opexTotalY1);

      ingresosPpaLife = formatoEuro(acuIngresosPpa);
      ingresosMktLife = formatoEuro(acuIngresosMkt);
      costeRedLife = formatoEuro(-acuCosteRed);
      opexLife = formatoEuro(acuOpex);
      reemplazoLife = formatoEuro(acuReemplazo);
      beneficioNetoLife = formatoEuro(cumulative + capexTotal);
      beneficioNetoTotalLife = formatoEuro(cumulative);
      roiSpots = spots;
    });
  }

  void _mostrarExplicacion(String tipo, bool isDark) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.info, color: isDark ? accentMagenta : Colors.orange),
              const SizedBox(width: 10),
              Text(
                tipo == 'bloque' ? 'Bloque Conseguido' : tipo == 'fv' ? 'FV Óptima' : tipo == 'bat' ? 'Batería Óptima' : 'Cómo se optimiza',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ],
          ),
          content: Text(
            tipo == 'bloque'
                ? 'El bloque fijo que realmente sostiene la combinación FV+batería encontrada, recalculado de forma independiente. Debe coincidir con tu Bloque Potencia Objetivo — si no coincide exactamente, es solo redondeo numérico de la búsqueda.'
                : tipo == 'fv'
                ? 'La potencia FV mínima que, junto con la batería óptima, sostiene el Bloque de Potencia objetivo las 8760h reales del año sin bajar nunca del 10% de SOC.'
                : tipo == 'bat'
                ? 'El tamaño de batería que, combinado con la FV óptima, minimiza el CAPEX total (FV × coste/MW + Batería × coste/MWh) para sostener el bloque objetivo.'
                : 'Para cada tamaño de batería posible existe una FV mínima que sostiene el bloque (más batería → menos FV hace falta, y viceversa). Se busca el punto de esa curva con menor CAPEX combinado.',
            style: TextStyle(height: 1.4, color: isDark ? Colors.grey : Colors.black54),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))),
          ],
        );
      },
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
              onFieldSubmitted: (_) => _guardarYCalcular(),
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
              isExpanded: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentMagenta : Colors.orange.shade400)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentBlue : Colors.orange, width: 2)),
              ),
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)))).toList(),
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
              isExpanded: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.orange.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentBlue.withValues(alpha: 0.5) : Colors.orange.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? accentMagenta : Colors.orange, width: 2)),
              ),
              items: List.generate(24, (index) => DropdownMenuItem(value: index.toString(), child: Text('${index.toString().padLeft(2, '0')}:00', style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)))),
              onChanged: onChanged,
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
          gradient: isDark ? brandGradient : LinearGradient(colors: [colorClaro.withValues(alpha: 0.8), colorClaro], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(titulo, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
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
                Flexible(child: Text(valor, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
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

  Widget _legendaDot(Color color, String texto, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
      ],
    );
  }

  // Desplegable explicativo de "Solo FV": sin batería, cada hora se decide solo
  // comparando generación vs bloque. La gráfica es un día TIPO ilustrativo (no
  // sale de la simulación real de 8760h) para que se vea de un vistazo el
  // mecanismo: mediodía sobra energía (se vende a mercado), noche/bajo sol
  // falta (se compra a mercado).
  Widget _buildExplicacionSoloFv(bool isDark) {
    double potEj = double.tryParse(_fvDirectaController.text.replaceAll(',', '.')) ?? 10.0;
    double bloqueEj = double.tryParse(_bloqueObjetivoController.text.replaceAll(',', '.')) ?? 2.0;
    if (potEj <= 0) potEj = 10.0;
    if (bloqueEj <= 0) bloqueEj = 2.0;

    List<double> genDia = List.generate(24, (h) {
      if (h < 6 || h > 20) return 0.0;
      double x = (h - 6) / 14.0;
      return potEj * sin(x * pi).clamp(0.0, 1.0);
    });
    List<double> ventaMercado = List.generate(24, (h) => max(0.0, genDia[h] - bloqueEj));
    List<double> compraMercado = List.generate(24, (h) => max(0.0, bloqueEj - genDia[h]));
    double maxY = [potEj, bloqueEj].reduce(max) + 1;

    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Icon(Icons.help_outline, color: isDark ? accentMagenta : Colors.orange),
          title: Text('¿Cómo funciona "Solo FV"?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
          subtitle: Text('Explicación + día tipo', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin batería, cada hora se resuelve sola comparando la generación FV con el Bloque de Potencia Objetivo:\n\n'
                    '• Si generas MÁS que el bloque (típicamente al mediodía) → el excedente se vende al precio de mercado de esa hora.\n'
                    '• Si generas MENOS que el bloque (mañana, tarde y toda la noche) → la diferencia se compra al mercado para completar el compromiso.\n\n'
                    'El bloque en sí se cobra siempre al precio pactado (LCOE resuelto o tu PPA manual) las 8.760 horas del año, venga esa energía de tu FV o de la red.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: isDark ? Colors.grey : Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  Text('Día tipo (ilustrativo)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.blueGrey)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 240,
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: 23,
                        minY: 0,
                        maxY: maxY,
                        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: isDark ? Colors.white10 : Colors.black12, strokeWidth: 1)),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 3, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('${v.toInt()}:00', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54))))),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54)))),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) => spots.map((s) {
                              String tipo = s.barIndex == 0 ? 'Generación' : (s.barIndex == 1 ? 'Bloque' : (s.barIndex == 2 ? 'Vendido a Mercado' : 'Comprado a Mercado'));
                              return LineTooltipItem('$tipo\n${s.x.toInt()}:00 → ${s.y.toStringAsFixed(1)} MW', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
                            }).toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: List.generate(24, (i) => FlSpot(i.toDouble(), genDia[i])),
                            isCurved: true,
                            color: Colors.lightGreen,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: Colors.lightGreen.withValues(alpha: 0.25)),
                          ),
                          LineChartBarData(
                            spots: [FlSpot(0, bloqueEj), FlSpot(23, bloqueEj)],
                            isCurved: false,
                            color: Colors.orange,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            dashArray: [6, 4],
                          ),
                          LineChartBarData(
                            spots: List.generate(24, (i) => FlSpot(i.toDouble(), ventaMercado[i])),
                            isCurved: true,
                            color: Colors.blue,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: Colors.blue.withValues(alpha: 0.35)),
                          ),
                          LineChartBarData(
                            spots: List.generate(24, (i) => FlSpot(i.toDouble(), compraMercado[i])),
                            isCurved: true,
                            color: Colors.redAccent,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: Colors.redAccent.withValues(alpha: 0.35)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _legendaDot(Colors.lightGreen, 'Generación FV', isDark),
                      _legendaDot(Colors.orange, 'Bloque Objetivo', isDark),
                      _legendaDot(Colors.blue, 'Vendido a Mercado (sobra)', isDark),
                      _legendaDot(Colors.redAccent, 'Comprado a Mercado (falta)', isDark),
                    ],
                  ),
                ],
              ),
            ),
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
          // PANEL IZQUIERDO: INPUTS
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSeccionHeader('Modo de Diseño', Icons.rule, Colors.indigo, isDark),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'optimizar', label: Text('Optimizar', style: TextStyle(fontSize: 12)), icon: Icon(Icons.auto_fix_high, size: 16)),
                      ButtonSegment(value: 'solo_fv', label: Text('Solo FV', style: TextStyle(fontSize: 12)), icon: Icon(Icons.wb_sunny, size: 16)),
                      ButtonSegment(value: 'solo_bateria', label: Text('Solo Batería', style: TextStyle(fontSize: 12)), icon: Icon(Icons.battery_charging_full, size: 16)),
                    ],
                    selected: {_modo},
                    onSelectionChanged: (Set<String> nuevo) {
                      setState(() => _modo = nuevo.first);
                      _guardarYCalcular();
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildSeccionHeader('Bloque Objetivo y Costes', Icons.tune, Colors.indigo, isDark),
                  if (_modo == 'optimizar')
                    _buildInputCard([
                      _buildInputField('Bloque Potencia Objetivo', _bloqueObjetivoController, 'MW', isDark),
                      _buildInputField('Horas Equivalentes', _horasEqController, 'h/año', isDark),
                      _buildInputField('Coste Unitario FV', _costeFvController, '€/MW', isDark),
                      _buildInputField('Coste Unitario Batería', _costeBatController, '€/MWh', isDark),
                      _buildInputField('Vida Útil Proyecto', _vidaUtilController, 'Años', isDark),
                    ], isDark)
                  else if (_modo == 'solo_fv')
                    _buildInputCard([
                      _buildInputField('Bloque Potencia Objetivo', _bloqueObjetivoController, 'MW', isDark),
                      _buildInputField('Horas Equivalentes', _horasEqController, 'h/año', isDark),
                      _buildInputField('Potencia FV', _fvDirectaController, 'MW', isDark),
                      _buildInputField('CAPEX FV', _costeFvKwController, '€/kW', isDark),
                      _buildInputField('Vida Útil Proyecto', _vidaUtilController, 'Años', isDark),
                    ], isDark)
                  else
                    _buildInputCard([
                      _buildInputField('Bloque Potencia Objetivo', _bloqueObjetivoController, 'MW', isDark),
                      _buildInputField('Horas Equivalentes', _horasEqController, 'h/año', isDark),
                      _buildInputField('Potencia FV', _fvDirectaController, 'MW', isDark),
                      _buildInputField('Potencia Batería', _bateriaPotDirectaController, 'MW', isDark),
                      _buildInputField('Capacidad Batería', _bateriaMwhDirectaController, 'MWh', isDark),
                      _buildDropdownFieldStr('Unidad CAPEX Batería', _costeBatUnidad, const ['kW', 'MW'], (val) {
                        setState(() => _costeBatUnidad = val!);
                        _guardarYCalcular();
                      }, isDark),
                      _buildInputField('CAPEX Batería', _costeBatValorController, '€/$_costeBatUnidad', isDark),
                      _buildInputField('Vida Útil Proyecto', _vidaUtilController, 'Años', isDark),
                    ], isDark),
                  const SizedBox(height: 16),

                  _buildSeccionHeader('Degradación e Inyección', Icons.trending_down, Colors.teal, isDark),
                  _buildInputCard([
                    _buildInputField('Degradación Anual FV', _degradacionController, '%', isDark),
                    _buildInputField('Límite Inyección Red', _limiteInyController, 'MW', isDark),
                  ], isDark),
                  const SizedBox(height: 16),

                  if (_modo != 'solo_fv') ...[
                    _buildSeccionHeader('Horas Mercado (Red)', Icons.access_time, Colors.orange, isDark),
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
                                _guardarYCalcular();
                              },
                            ),
                            const Divider(),
                            _buildDropdownFieldStr('Mes a editar', _mesHorasSeleccionado, mesesNombres, (val) {
                              setState(() => _mesHorasSeleccionado = val!);
                            }, isDark),
                            _buildDropdownFieldHoras('Hora Inicio', hInicioMes[_mesHorasSeleccionado] ?? '1', (val) {
                              setState(() => hInicioMes[_mesHorasSeleccionado] = val!);
                              _guardarYCalcular();
                            }, isDark),
                            _buildDropdownFieldHoras('Hora Fin', hFinMes[_mesHorasSeleccionado] ?? '4', (val) {
                              setState(() => hFinMes[_mesHorasSeleccionado] = val!);
                              _guardarYCalcular();
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
                  ] else
                    Card(
                      color: Colors.blue.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.blue.withValues(alpha: 0.3))),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Sin batería no hay ventana de "entrada a mercado": cada hora se resuelve solo por generación vs bloque (ver explicación abajo).',
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_modo == 'solo_fv') const SizedBox(height: 16),

                  _buildSeccionHeader(_modo == 'optimizar' ? 'Costes Operativos y PPA' : 'Costes Operativos', Icons.attach_money, Colors.green, isDark),
                  _buildInputCard([
                    _buildInputField('OPEX Fijo', _opexFijoController, '€/año', isDark),
                    _buildInputField('OPEX Variable', _opexVariableController, '€/MWh', isDark),
                    if (_modo == 'optimizar') _buildInputField('Precio Acuerdo PPA', _precioPpaController, '€/MWh', isDark),
                    _buildInputField('Escalada Precio Mercado', _escaladaPrecioController, '%/año', isDark),
                    if (_modo != 'optimizar')
                      _buildDropdownFieldStr('Detalle a Mostrar', _tasaDetalle == '5' ? 'LCOE @ 5% TIR' : (_tasaDetalle == '10' ? 'LCOE @ 10% TIR' : 'Precio PPA Manual'),
                          const ['LCOE @ 5% TIR', 'LCOE @ 10% TIR', 'Precio PPA Manual'], (val) {
                        setState(() => _tasaDetalle = val == 'LCOE @ 5% TIR' ? '5' : (val == 'LCOE @ 10% TIR' ? '10' : 'manual'));
                        _guardarYCalcular();
                      }, isDark),
                    if (_modo != 'optimizar' && _tasaDetalle == 'manual') _buildInputField('Precio PPA Manual', _precioPpaController, '€/MWh', isDark),
                  ], isDark),
                  const SizedBox(height: 16),

                  if (_modo != 'solo_fv') ...[
                    _buildSeccionHeader('Reemplazo BESS', Icons.battery_charging_full, Colors.purple, isDark),
                    _buildInputCard([
                      _buildInputField('Año de Reemplazo', _anoReemplazoController, 'Años', isDark),
                      _buildInputField('Coste Reemplazo', _costeReemplazoController, '€/MWh', isDark),
                    ], isDark),
                    const SizedBox(height: 16),
                  ],

                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: isDark ? brandGradient : const LinearGradient(colors: [Colors.indigo, Colors.indigoAccent]),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _calculando ? null : _guardarYCalcular,
                      icon: _calculando
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.auto_fix_high, color: Colors.white),
                      label: Text(_calculando ? 'CALCULANDO...' : (_modo == 'optimizar' ? 'OPTIMIZAR DISEÑO' : 'CALCULAR LCOE'), style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.white)),
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
                  _buildSeccionHeader('Diseño Óptimo y Retorno', Icons.analytics, Colors.blueGrey, isDark),

                  if (_mensajeError != null)
                    Card(
                      color: Colors.red.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.red)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_mensajeError!, style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
                          ],
                        ),
                      ),
                    ),
                  if (_mensajeError != null) const SizedBox(height: 16),

                  // KPIs Row
                  if (_modo == 'optimizar')
                    Row(
                      children: [
                        Expanded(child: _buildKPICardSimple('BLOQUE CONSEGUIDO', bloqueFijoMaxMostrar, 'MW', Colors.deepPurple, isDark, onTapIcon: () => _mostrarExplicacion('bloque', isDark))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('FV ÓPTIMA', fvOptimaMostrar, 'MW', Colors.orange, isDark, onTapIcon: () => _mostrarExplicacion('fv', isDark))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('BATERÍA ÓPTIMA', bateriaOptimaMostrar, 'MWh', Colors.purple, isDark, onTapIcon: () => _mostrarExplicacion('bat', isDark))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('LCOE', lcoeMostrar, '€/MWh', Colors.indigo, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('INYECCIÓN RED Y1', inyeccionRedMostrar, 'GWh', Colors.blue, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('TIR', tirMostrar, '%', Colors.teal, isDark)),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(child: _buildKPICardSimple('BLOQUE OBJETIVO', bloqueFijoMaxMostrar, 'MW', Colors.deepPurple, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('LCOE @ 5% TIR', lcoe5Mostrar, '€/MWh', Colors.orange, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('LCOE @ 10% TIR', lcoe10Mostrar, '€/MWh', Colors.deepOrange, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('CAPEX TOTAL', capexTotalStr, '€', Colors.indigo, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('INYECCIÓN RED Y1', inyeccionRedMostrar, 'GWh', Colors.blue, isDark)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKPICardSimple('TIR ($_etiquetaDetalle)', tirMostrar, '%', Colors.teal, isDark)),
                      ],
                    ),
                  const SizedBox(height: 16),

                  if (_modo == 'solo_fv') ...[
                    _buildExplicacionSoloFv(isDark),
                    const SizedBox(height: 16),
                  ],

                  // Resumen Financiero
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
                                _buildFilaFinanzas(_modo == 'optimizar' ? 'Ingresos PPA' : 'Ingresos Bloque ($_etiquetaDetalle)', '$ingresosPpaY1 €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Ingresos Mercado', '$ingresosMktY1 €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Coste Red (Mercado)', '$costeRedY1 €', isDark, colorClaro: costeRedY1.startsWith('-') ? Colors.red : Colors.green),
                                _buildFilaFinanzas('OPEX Anual', '-$opexY1 €', isDark, colorClaro: Colors.red),
                                Divider(color: isDark ? Colors.white24 : Colors.black12, thickness: 1),
                                _buildFilaFinanzas('Flujo de Caja Neto', '$flujoCajaY1 €', isDark, colorClaro: Colors.blueGrey, isBold: true),
                                const SizedBox(height: 12),
                                _buildFilaFinanzas(_modo == 'optimizar' ? 'CAPEX Óptimo Total' : 'CAPEX Total', '-$capexTotalStr €', isDark, colorClaro: Colors.redAccent, isBold: true),
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
                                _buildFilaFinanzas(_modo == 'optimizar' ? 'Total Ingresos PPA' : 'Total Ingresos Bloque', '$ingresosPpaLife €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Total Mercado', '$ingresosMktLife €', isDark, colorClaro: Colors.green),
                                _buildFilaFinanzas('Total Coste Red', '$costeRedLife €', isDark, colorClaro: costeRedLife.startsWith('-') ? Colors.red : Colors.green),
                                _buildFilaFinanzas('Total OPEX', '-$opexLife €', isDark, colorClaro: Colors.red),
                                if (_modo != 'solo_fv') _buildFilaFinanzas('Coste Reemplazo BESS', '-$reemplazoLife €', isDark, colorClaro: Colors.red),
                                Divider(color: isDark ? Colors.white24 : Colors.black12),
                                _buildFilaFinanzas('Beneficio de Operación', '$beneficioNetoLife €', isDark, colorClaro: Colors.blueGrey, isBold: true),
                                _buildFilaFinanzas(_modo == 'optimizar' ? 'CAPEX Óptimo Total' : 'CAPEX Total', '-$capexTotalStr €', isDark, colorClaro: Colors.redAccent),
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
                                  extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: 0, color: isDark ? accentMagenta : Colors.red, strokeWidth: 2, dashArray: [5, 5])]),
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
                                        gradient: isDark ? LinearGradient(colors: [accentBlue.withValues(alpha: 0.5), accentMagenta.withValues(alpha: 0.1)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
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
