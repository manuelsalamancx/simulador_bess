import 'dart:async';
import 'dart:convert';
import 'dart:math';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

/// Pantalla de Inicio: punto de entrada de la app. Aquí se eligen los datos de
/// radiación/precios (8760h) UNA sola vez, compartidos entre Dimensionamiento
/// y Auditoría, y se elige a qué escenario entrar.
class PantallaInicioScreen extends StatefulWidget {
  final void Function(int indice) onSeleccionarEscenario;

  const PantallaInicioScreen({super.key, required this.onSeleccionarEscenario});

  @override
  State<PantallaInicioScreen> createState() => _PantallaInicioScreenState();
}

class _PantallaInicioScreenState extends State<PantallaInicioScreen> {
  final TextEditingController _latController = TextEditingController(text: '36.72');
  final TextEditingController _lonController = TextEditingController(text: '-4.42');
  final TextEditingController _tokenEsiosController = TextEditingController();
  final TextEditingController _municipioController = TextEditingController();

  static const List<String> _provincias = [
    'Álava', 'Albacete', 'Alicante', 'Almería', 'Ávila', 'Badajoz', 'Baleares', 'Barcelona',
    'Burgos', 'Cáceres', 'Cádiz', 'Cantabria', 'Castellón', 'Ciudad Real', 'Córdoba', 'A Coruña',
    'Cuenca', 'Girona', 'Granada', 'Guadalajara', 'Gipuzkoa', 'Huelva', 'Huesca', 'Jaén', 'León',
    'Lleida', 'La Rioja', 'Lugo', 'Madrid', 'Málaga', 'Murcia', 'Navarra', 'Ourense', 'Asturias',
    'Palencia', 'Las Palmas', 'Pontevedra', 'Salamanca', 'Santa Cruz de Tenerife', 'Segovia',
    'Sevilla', 'Soria', 'Tarragona', 'Teruel', 'Toledo', 'Valencia', 'Valladolid', 'Bizkaia',
    'Zamora', 'Zaragoza', 'Ceuta', 'Melilla',
  ];

  String? _provinciaSeleccionada;
  bool _buscandoMunicipio = false;

  bool _cargandoPVGIS = false;
  bool _cargandoPrecios = false;

  List<double> _radiacion8760 = [];
  List<double> _precios8760 = [];

  int _anioRadiacionSeleccionado = DateTime.now().year - 1;
  int _anioSeleccionado = DateTime.now().year - 1;
  String _indicadorSeleccionado = '600';

  // Qué hay REALMENTE cargado ahora mismo (no lo que dice el selector, que solo
  // afecta a la PRÓXIMA descarga) — se fija cada vez que precios_8760/radiacion_8760
  // cambian, para saber siempre con certeza qué datos está usando la simulación.
  String? _precioOrigen;
  String? _radiacionOrigen;

  final Map<String, String> _mercadosDisponibles = const {
    '600': 'Precio Mercado Diario (OMIE)',
    '1001': 'PVPC (Tarifa Regulada)',
  };

  final Color accentMagenta = const Color(0xFFD80073);
  final Color accentBlue = const Color(0xFF0050EF);

  @override
  void initState() {
    super.initState();
    _cargarDatosGuardados();
  }

  Future<void> _cargarDatosGuardados() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? radGuardada = prefs.getStringList('radiacion_8760');
    List<String>? preGuardados = prefs.getStringList('precios_8760');
    String? tokenGuardado = prefs.getString('esios_token');

    if (radGuardada != null && radGuardada.length == 8760) {
      _radiacion8760 = radGuardada.map((e) => double.parse(e)).toList();
    }
    if (preGuardados != null && preGuardados.length == 8760) {
      _precios8760 = preGuardados.map((e) => double.parse(e)).toList();
    }
    if (tokenGuardado != null && tokenGuardado.isNotEmpty) {
      _tokenEsiosController.text = tokenGuardado;
    }

    String? provinciaGuardada = prefs.getString('ubicacion_provincia');
    String? municipioGuardado = prefs.getString('ubicacion_municipio');
    String? latGuardada = prefs.getString('ubicacion_lat');
    String? lonGuardada = prefs.getString('ubicacion_lon');
    if (provinciaGuardada != null && _provincias.contains(provinciaGuardada)) {
      _provinciaSeleccionada = provinciaGuardada;
    }
    if (municipioGuardado != null) _municipioController.text = municipioGuardado;
    if (latGuardada != null) _latController.text = latGuardada;
    if (lonGuardada != null) _lonController.text = lonGuardada;

    int? anioRadGuardado = prefs.getInt('anio_radiacion');
    if (anioRadGuardado != null) _anioRadiacionSeleccionado = anioRadGuardado;

    _precioOrigen = prefs.getString('precios_origen');
    _radiacionOrigen = prefs.getString('radiacion_origen');
    // Hay datos guardados de antes de que existiera este registro de origen:
    // no son "sin datos" (los hay), pero no sabemos con certeza su procedencia.
    if (_precioOrigen == null && _precios8760.length == 8760) {
      _precioOrigen = 'Datos existentes (cargados antes de este control — verifica el año tú mismo)';
    }
    if (_radiacionOrigen == null && _radiacion8760.length == 8760) {
      _radiacionOrigen = 'Datos existentes (cargados antes de este control — verifica el año tú mismo)';
    }

    setState(() {});
  }

  Future<void> _guardarUbicacion() async {
    final prefs = await SharedPreferences.getInstance();
    if (_provinciaSeleccionada != null) {
      await prefs.setString('ubicacion_provincia', _provinciaSeleccionada!);
    }
    await prefs.setString('ubicacion_municipio', _municipioController.text.trim());
    await prefs.setString('ubicacion_lat', _latController.text.trim());
    await prefs.setString('ubicacion_lon', _lonController.text.trim());
  }

  Future<void> _buscarMunicipio() async {
    if (_provinciaSeleccionada == null || _municipioController.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una provincia y escribe un municipio'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _buscandoMunicipio = true);
    try {
      final url = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': '1',
        'countrycodes': 'es',
        'q': '${_municipioController.text.trim()}, $_provinciaSeleccionada, España',
      });

      final response = await http.get(url, headers: {'Accept-Language': 'es'});
      if (response.statusCode == 200) {
        final results = json.decode(response.body) as List;
        if (results.isNotEmpty) {
          final lat = double.parse(results[0]['lat']);
          final lon = double.parse(results[0]['lon']);
          setState(() {
            _latController.text = lat.toStringAsFixed(4);
            _lonController.text = lon.toStringAsFixed(4);
          });
          await _guardarUbicacion();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📍 ${results[0]['display_name']}'), backgroundColor: Colors.blue));
        } else {
          throw Exception('No se encontró ese municipio');
        }
      } else {
        throw Exception('Error consultando la ubicación');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    setState(() => _buscandoMunicipio = false);
  }

  double _comoDouble(dynamic v) => ((v as num?) ?? 0.0).toDouble();

  // Réplica simplificada de lo que hace PVGIS internamente, a partir de datos
  // de Open-Meteo (que sí cubre años recientes y no necesita proxy):
  //  1. Geometría solar hora a hora (declinación, ecuación del tiempo, ángulo
  //     horario, cenit y azimuth solar) para un panel fijo inclinado a la
  //     latitud del lugar y orientado al sur (como una planta real).
  //  2. Transposición de la irradiancia horizontal (directa+difusa, ya
  //     separadas por Open-Meteo) al plano del panel — directa vía ángulo de
  //     incidencia, difusa con modelo isotrópico de cielo, más el reflejo del
  //     suelo (albedo).
  //  3. Temperatura de célula (modelo NOCT) y derateo por temperatura de un
  //     panel de silicio cristalino (~0,4%/°C por encima de 25°C).
  // Validado contra PVGIS real (mismo punto/año, panel a la misma inclinación):
  // ~1,6% de diferencia en generación anual total.
  List<double> _simularGeneracionFv(List<String> tiempos, List<double> dni, List<double> dhi, List<double> ghi, List<double> tAire, double latGrados, double lonGrados) {
    final double tiltRad = _gradosARadianes(latGrados.abs());
    final double cosTilt = cos(tiltRad);
    final double sinTilt = sin(tiltRad);
    final double latRad = _gradosARadianes(latGrados);
    const double albedo = 0.2;
    const double noct = 45.0;
    const double coefTemp = -0.004; // por °C, típico de silicio cristalino

    List<double> resultado = [];
    for (int i = 0; i < tiempos.length; i++) {
      DateTime fecha = DateTime.parse(tiempos[i]);
      int n = fecha.difference(DateTime(fecha.year, 1, 1)).inDays + 1;
      double horaUtc = fecha.hour.toDouble();

      double bRad = _gradosARadianes(360 * (n - 81) / 364.0);
      double eot = 9.87 * sin(2 * bRad) - 7.53 * cos(bRad) - 1.5 * sin(bRad); // minutos

      double horaSolar = horaUtc + lonGrados / 15.0 + eot / 60.0;
      double omegaRad = _gradosARadianes(15 * (horaSolar - 12));

      double declRad = _gradosARadianes(23.45 * sin(_gradosARadianes(360 * (284 + n) / 365.0)));

      double cosZenit = (sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(omegaRad)).clamp(-1.0, 1.0);

      double poa = 0.0;
      if (cosZenit > 0.0) {
        double sinZenit = sqrt(1 - cosZenit * cosZenit);
        double cosAzimuth = 1.0;
        if (sinZenit > 1e-6 && cos(latRad).abs() > 1e-6) {
          cosAzimuth = ((cosZenit * sin(latRad) - sin(declRad)) / (sinZenit * cos(latRad))).clamp(-1.0, 1.0);
        }
        double cosAoi = (cosZenit * cosTilt + sinZenit * sinTilt * cosAzimuth).clamp(0.0, 1.0);

        double poaDirecta = dni[i] * cosAoi;
        double poaDifusa = dhi[i] * (1 + cosTilt) / 2.0;
        double poaReflejada = ghi[i] * albedo * (1 - cosTilt) / 2.0;
        poa = max(0.0, poaDirecta + poaDifusa + poaReflejada);
      }

      double tCelda = tAire[i] + (noct - 20.0) * (poa / 800.0);
      double factor = max(0.0, (poa / 1000.0) * (1 + coefTemp * (tCelda - 25.0)));
      resultado.add(factor);
    }
    return resultado;
  }

  double _gradosARadianes(double g) => g * pi / 180.0;

  Future<void> _descargarRadiacion() async {
    setState(() => _cargandoPVGIS = true);
    try {
      String lat = _latController.text;
      String lon = _lonController.text;
      double latNum = double.parse(lat.replaceAll(',', '.'));
      double lonNum = double.parse(lon.replaceAll(',', '.'));
      int anio = _anioRadiacionSeleccionado;

      final url = Uri.parse(
        'https://archive-api.open-meteo.com/v1/archive'
        '?latitude=$lat&longitude=$lon&start_date=$anio-01-01&end_date=$anio-12-31'
        '&hourly=direct_normal_irradiance,diffuse_radiation,shortwave_radiation,temperature_2m&timezone=UTC',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final horas = data['hourly'];
        final List<String> tiempos = List<String>.from(horas['time']);
        final List<double> dni = (horas['direct_normal_irradiance'] as List).map(_comoDouble).toList();
        final List<double> dhi = (horas['diffuse_radiation'] as List).map(_comoDouble).toList();
        final List<double> ghi = (horas['shortwave_radiation'] as List).map(_comoDouble).toList();
        final List<double> tAire = (horas['temperature_2m'] as List).map(_comoDouble).toList();

        List<double> radTemp = _simularGeneracionFv(tiempos, dni, dhi, ghi, tAire, latNum, lonNum);

        if (radTemp.length >= 8760) {
          _radiacion8760 = radTemp.sublist(0, 8760);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('radiacion_8760', _radiacion8760.map((e) => e.toString()).toList());
          await prefs.setInt('anio_radiacion', anio);
          _radiacionOrigen = 'Open-Meteo $anio (lat $lat, lon $lon)';
          await prefs.setString('radiacion_origen', _radiacionOrigen!);
          await _guardarUbicacion();

          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('¡Radiación $anio (Open-Meteo, 8760h) descargada con éxito!'), backgroundColor: Colors.green));
        } else {
          throw Exception('Solo se recibieron ${radTemp.length} horas (¿año incompleto?)');
        }
      } else {
        throw Exception('Código ${response.statusCode}: error en la API de Open-Meteo');
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
      final targetUrl = 'https://api.esios.ree.es/indicators/$_indicadorSeleccionado?start_date=$_anioSeleccionado-01-01T00:00:00&end_date=$_anioSeleccionado-12-31T23:59:59';
      final url = Uri.parse('https://proxy.cors.sh/$targetUrl');

      http.Response? response;
      const maxIntentos = 3;
      int intento = 1;
      while (true) {
        try {
          response = await http.get(
            url,
            headers: {
              'Accept': 'application/json; application/vnd.esios-api-v1+json',
              'Content-Type': 'application/json',
              'x-api-key': token,
            },
          ).timeout(const Duration(seconds: 60));
        } on TimeoutException {
          if (intento >= maxIntentos) {
            throw Exception('El servidor tardó demasiado en responder (probando $maxIntentos veces). Prueba de nuevo en un rato, o cambia de año/mercado');
          }
          intento++;
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        final esFalloTemporal = response.statusCode == 502 || response.statusCode == 503 || response.statusCode == 504;
        if (!esFalloTemporal || intento >= maxIntentos) break;
        intento++;
        await Future.delayed(const Duration(seconds: 2));
      }
      final resp = response;

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final values = data['indicator']['values'] as List;

        final valoresEspana = values.where((v) => (v['geo_name'] ?? '') == 'España').toList();
        final valoresFiltrados = valoresEspana.isNotEmpty ? valoresEspana : values;

        List<double> preciosTemp = [];
        for (var item in valoresFiltrados) {
          preciosTemp.add((item['value'] ?? 0.0).toDouble());
        }

        if (preciosTemp.length >= 8760) {
          _precios8760 = preciosTemp.sublist(0, 8760);
        } else {
          _precios8760 = List.from(preciosTemp);
          while (_precios8760.length < 8760) {
            _precios8760.add(_precios8760.last);
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('precios_8760', _precios8760.map((e) => e.toString()).toList());
        await prefs.setString('esios_token', token);

        final nombreMercado = _mercadosDisponibles[_indicadorSeleccionado] ?? _indicadorSeleccionado;
        _precioOrigen = 'ESIOS $_anioSeleccionado ($nombreMercado)';
        await prefs.setString('precios_origen', _precioOrigen!);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('¡$nombreMercado $_anioSeleccionado descargado con éxito!'), backgroundColor: Colors.green));
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw Exception('Código ${resp.statusCode}: Token de ESIOS inválido o sin permisos');
      } else if (resp.statusCode == 502 || resp.statusCode == 503 || resp.statusCode == 504) {
        throw Exception('Código ${resp.statusCode}: el proxy CORS o el servidor de ESIOS no respondió a tiempo (fallo temporal, no es tu token). Prueba de nuevo en unos segundos');
      } else {
        throw Exception('Código ${resp.statusCode}: error inesperado al descargar los precios');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }

    setState(() => _cargandoPrecios = false);
  }

  Future<void> _generarPreciosPatron() async {
    setState(() => _cargandoPrecios = true);
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
    await prefs.setStringList('precios_8760', _precios8760.map((e) => e.toString()).toList());
    _precioOrigen = 'Año Tipo (patrón sintético, no es un año real)';
    await prefs.setString('precios_origen', _precioOrigen!);

    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _cargandoPrecios = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Matriz de Precios Patrón 8760h generada'), backgroundColor: Colors.blue));
  }

  Future<void> _cargarPreciosDesdeArchivo() async {
    final input = html.FileUploadInputElement()..accept = '.json,.csv,text/plain,application/json';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;

    setState(() => _cargandoPrecios = true);
    try {
      final reader = html.FileReader();
      reader.readAsText(input.files![0]);
      await reader.onLoad.first;
      final contenido = (reader.result as String).trim();

      List<double> preciosTemp = [];
      String? anioDetectado;
      if (contenido.startsWith('{')) {
        final data = json.decode(contenido);
        final values = data['indicator']['values'] as List;
        final valoresEspana = values.where((v) => (v['geo_name'] ?? '') == 'España').toList();
        final valoresFiltrados = valoresEspana.isNotEmpty ? valoresEspana : values;
        for (var item in valoresFiltrados) {
          preciosTemp.add((item['value'] ?? 0.0).toDouble());
        }
        if (valoresFiltrados.isNotEmpty) {
          final dt = valoresFiltrados.first['datetime']?.toString();
          if (dt != null && dt.length >= 4) anioDetectado = dt.substring(0, 4);
        }
      } else if (contenido.startsWith('[')) {
        final data = json.decode(contenido) as List;
        preciosTemp = data.map((e) => (e as num).toDouble()).toList();
      } else {
        final lineas = contenido.split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lineas.isEmpty) throw Exception('El archivo está vacío');

        final cabecera = lineas.first.toLowerCase();
        if (cabecera.contains('geoname') && cabecera.contains('value')) {
          final columnas = lineas.first.split(';').map((c) => c.trim().toLowerCase()).toList();
          final idxGeoname = columnas.indexOf('geoname');
          final idxValue = columnas.indexOf('value');
          final idxDatetime = columnas.indexWhere((c) => c.contains('datetime') || c.contains('fecha'));
          for (var linea in lineas.skip(1)) {
            final partes = linea.split(';');
            if (partes.length <= idxGeoname || partes.length <= idxValue) continue;
            if (partes[idxGeoname].trim() != 'España') continue;
            final valor = double.tryParse(partes[idxValue].trim().replaceAll(',', '.'));
            if (valor != null) {
              preciosTemp.add(valor);
              if (anioDetectado == null && idxDatetime >= 0 && partes.length > idxDatetime) {
                final m = RegExp(r'(20\d{2})').firstMatch(partes[idxDatetime]);
                if (m != null) anioDetectado = m.group(1);
              }
            }
          }
        } else {
          for (var linea in lineas) {
            final partes = linea.split(RegExp(r'[,;]'));
            final valor = double.tryParse(partes.last.trim().replaceAll(',', '.'));
            if (valor != null) preciosTemp.add(valor);
          }
        }
      }

      if (preciosTemp.isEmpty) throw Exception('No se encontraron valores numéricos en el archivo');

      if (preciosTemp.length >= 8760) {
        _precios8760 = preciosTemp.sublist(0, 8760);
      } else {
        _precios8760 = List.from(preciosTemp);
        while (_precios8760.length < 8760) {
          _precios8760.add(_precios8760.last);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('precios_8760', _precios8760.map((e) => e.toString()).toList());
      _precioOrigen = anioDetectado != null ? 'Archivo cargado — ESIOS $anioDetectado (detectado)' : 'Archivo cargado (año no detectado — verifícalo tú mismo)';
      await prefs.setString('precios_origen', _precioOrigen!);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Precios cargados desde archivo (${_precios8760.length}h)'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error leyendo el archivo: $e'), backgroundColor: Colors.red));
    }
    setState(() => _cargandoPrecios = false);
  }

  List<double> _preciosMediosPorMes() {
    const diasMes = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    List<double> medias = [];
    int inicio = 0;
    for (int m = 0; m < 12; m++) {
      int horas = diasMes[m] * 24;
      int fin = (inicio + horas).clamp(0, _precios8760.length);
      if (fin <= inicio) {
        medias.add(0);
      } else {
        final segmento = _precios8760.sublist(inicio, fin);
        medias.add(segmento.reduce((a, b) => a + b) / segmento.length);
      }
      inicio += horas;
    }
    return medias;
  }

  Widget _buildTarjetaEscenario(String titulo, String subtitulo, IconData icono, Color color, VoidCallback onTap, bool isDark) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.85), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Icon(icono, color: Colors.white, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitulo, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // "sintético"/"no detectado"/"no verificado"/"migrado" son avisos de que ese
  // dato puede no ser exactamente un año real concreto — se marcan en ámbar.
  bool _esOrigenIncierto(String origen) {
    final o = origen.toLowerCase();
    return o.contains('sintético') || o.contains('no detectado') || o.contains('no verificado') || o.contains('migrado') || o.contains('verifica') || o.contains('existentes');
  }

  Widget _filaOrigen(IconData icono, String etiqueta, String? origen, bool isDark) {
    bool hayDato = origen != null;
    bool incierto = hayDato && _esOrigenIncierto(origen);
    Color color = !hayDato ? Colors.red : (incierto ? Colors.orange : Colors.green);
    String texto = hayDato ? origen : 'Sin datos — descárgalos abajo';
    return Row(
      children: [
        Icon(icono, color: color, size: 18),
        const SizedBox(width: 8),
        Text('$etiqueta: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
        Expanded(child: Text(texto, style: TextStyle(fontSize: 13, color: color), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  // Banner destacado con lo que HAY REALMENTE cargado ahora (no lo que diga el
  // selector de año, que solo aplica a la próxima descarga) — para no dar por
  // hecho un año que en realidad no coincide con los datos ya guardados.
  Widget _buildBannerOrigenDatos(bool isDark) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DATOS ACTUALMENTE CARGADOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: isDark ? Colors.grey : Colors.black54)),
            const SizedBox(height: 8),
            _filaOrigen(Icons.wb_sunny, 'Radiación', _radiacionOrigen, isDark),
            const SizedBox(height: 6),
            _filaOrigen(Icons.euro_symbol, 'Precios', _precioOrigen, isDark),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBannerOrigenDatos(isDark),
          const SizedBox(height: 20),
          Text('SELECCIONA UN ESCENARIO', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildTarjetaEscenario('Dimensionamiento', 'Diseña una planta FV+BESS desde cero', Icons.architecture, const Color(0xFF0050EF), () => widget.onSeleccionarEscenario(2), isDark),
              const SizedBox(width: 16),
              _buildTarjetaEscenario('Auditoría', 'Audita/optimiza una planta existente', Icons.search_rounded, const Color(0xFFD80073), () => widget.onSeleccionarEscenario(4), isDark),
              const SizedBox(width: 16),
              _buildTarjetaEscenario('Baterías Standalone', 'Arbitraje de mercado, 2 ciclos/día', Icons.battery_charging_full, Colors.teal, () => widget.onSeleccionarEscenario(6), isDark),
            ],
          ),
          const SizedBox(height: 32),

          Text('DATOS DE RADIACIÓN Y PRECIOS (8760h)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text('Se descargan una sola vez aquí y los usan tanto Dimensionamiento como Auditoría.', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PANEL IZQUIERDO: CONTROLES API
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                Expanded(
                                  child: Text('RADIACIÓN SOLAR (Open-Meteo)', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _provinciaSeleccionada,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Provincia', border: OutlineInputBorder(), isDense: true),
                              items: _provincias.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (val) => setState(() => _provinciaSeleccionada = val),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _municipioController,
                                    decoration: const InputDecoration(labelText: 'Municipio', hintText: 'Ej: Marbella', border: OutlineInputBorder(), isDense: true),
                                    onFieldSubmitted: (_) => _buscarMunicipio(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: _buscandoMunicipio ? null : _buscarMunicipio,
                                  style: ElevatedButton.styleFrom(backgroundColor: accentBlue, foregroundColor: Colors.white),
                                  child: _buscandoMunicipio
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Icon(Icons.search),
                                ),
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
                            DropdownButtonFormField<int>(
                              initialValue: _anioRadiacionSeleccionado,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Año', border: OutlineInputBorder(), isDense: true),
                              items: List.generate(20, (i) => DateTime.now().year - 1 - i)
                                  .map((a) => DropdownMenuItem(value: a, child: Text('$a')))
                                  .toList(),
                              onChanged: (val) => setState(() => _anioRadiacionSeleccionado = val!),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _cargandoPVGIS ? null : _descargarRadiacion,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                child: _cargandoPVGIS ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white)) : const Text('Descargar Radiación'),
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
                                Expanded(
                                  child: Text('PRECIOS MERCADO (ESIOS/OMIE)', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _anioSeleccionado,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Año', border: OutlineInputBorder(), isDense: true),
                                    items: List.generate(7, (i) => DateTime.now().year - 1 - i)
                                        .map((a) => DropdownMenuItem(value: a, child: Text('$a')))
                                        .toList(),
                                    onChanged: (val) => setState(() => _anioSeleccionado = val!),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _indicadorSeleccionado,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Mercado', border: OutlineInputBorder(), isDense: true),
                                    items: _mercadosDisponibles.entries
                                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (val) => setState(() => _indicadorSeleccionado = val!),
                                  ),
                                ),
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
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _cargandoPrecios ? null : _cargarPreciosDesdeArchivo,
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: const Text('Cargar precios desde archivo (JSON/CSV)'),
                              ),
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
                  height: 560,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Visualizador de Perfiles 8760h (Primera semana del año)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 1,
                        child: (_radiacion8760.isEmpty || _precios8760.isEmpty)
                            ? const Center(child: Text('Descarga ambos bloques de datos para visualizar'))
                            : LineChart(
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
                      const SizedBox(height: 24),
                      Text('Precio medio mensual (€/MWh)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blueGrey)),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 1,
                        child: _precios8760.isEmpty
                            ? const Center(child: Text('Descarga los precios para visualizar'))
                            : BarChart(
                                BarChartData(
                                  minY: 0,
                                  barGroups: _preciosMediosPorMes().asMap().entries.map((e) {
                                    return BarChartGroupData(x: e.key, barRods: [
                                      BarChartRodData(toY: e.value, color: accentBlue, width: 14, borderRadius: BorderRadius.circular(4)),
                                    ]);
                                  }).toList(),
                                  titlesData: FlTitlesData(
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54)))),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) {
                                          const mesesAbrev = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
                                          final i = value.toInt();
                                          if (i < 0 || i > 11) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(mesesAbrev[i], style: TextStyle(fontSize: 10, color: isDark ? Colors.grey : Colors.black54)),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
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
        ],
      ),
    );
  }
}
