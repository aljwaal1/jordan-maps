import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JordanMapsApp());
}

class JordanMapsApp extends StatelessWidget {
  const JordanMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'خرائط الأردن',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E),
          brightness: Brightness.dark,
        ),
      ),
      home: const JordanMapPage(),
    );
  }
}

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.latLng,
    required this.type,
  });

  final String name;
  final LatLng latLng;
  final String type;
}

class JordanMapPage extends StatefulWidget {
  const JordanMapPage({super.key});

  @override
  State<JordanMapPage> createState() => _JordanMapPageState();
}

class _JordanMapPageState extends State<JordanMapPage> {
  static final LatLng _amman = LatLng(31.9539, 35.9106);
  static final LatLngBounds _jordanBounds = LatLngBounds(
    LatLng(29.15, 34.88),
    LatLng(33.45, 39.35),
  );

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final Distance _distance = const Distance();

  Position? _currentPosition;
  LatLng? _selectedDestination;
  List<PlaceResult> _results = [];
  List<LatLng> _routePoints = [];
  String _status = 'جاهز للبحث داخل الأردن';
  String? _routeInfo;
  bool _isSearching = false;
  bool _isRouting = false;
  bool _isLocating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  LatLng? get _myLatLng {
    final p = _currentPosition;
    if (p == null) return null;
    return LatLng(p.latitude, p.longitude);
  }

  Future<void> _locateMe({bool moveCamera = true}) async {
    setState(() {
      _isLocating = true;
      _status = 'جاري تحديد موقعك...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('خدمة الموقع مغلقة. فعّل GPS من إعدادات الهاتف.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('لم يتم منح صلاحية الموقع.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      setState(() {
        _currentPosition = position;
        _status = 'تم تحديد موقعك';
      });

      if (moveCamera) {
        _mapController.move(LatLng(position.latitude, position.longitude), 15);
      }
    } catch (e) {
      _showMessage('تعذر تحديد الموقع: $e');
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _searchJordan() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showMessage('اكتب اسم مدينة أو مكان داخل الأردن');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _results = [];
      _routePoints = [];
      _routeInfo = null;
      _status = 'جاري البحث عن: $query';
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '8',
        'countrycodes': 'jo',
        'accept-language': 'ar,en',
        'viewbox': '34.88,33.45,39.35,29.15',
        'bounded': '1',
      });

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'jordan_maps_online/1.0 contact:yaya15112016@gmail.com',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as List<dynamic>;
      final items = decoded.map((item) {
        final map = item as Map<String, dynamic>;
        return PlaceResult(
          name: (map['display_name'] ?? 'مكان بدون اسم').toString(),
          latLng: LatLng(
            double.parse(map['lat'].toString()),
            double.parse(map['lon'].toString()),
          ),
          type: (map['type'] ?? map['class'] ?? 'مكان').toString(),
        );
      }).where((p) => _jordanBounds.contains(p.latLng)).toList();

      setState(() {
        _results = items;
        _status = items.isEmpty ? 'لا توجد نتائج داخل الأردن' : 'تم العثور على ${items.length} نتيجة';
      });

      if (items.isNotEmpty) {
        _selectResult(items.first, drawRoute: false);
      }
    } catch (e) {
      _showMessage('تعذر البحث الآن. تأكد من الإنترنت ثم أعد المحاولة.');
      setState(() => _status = 'فشل البحث');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectResult(PlaceResult place, {bool drawRoute = true}) {
    setState(() {
      _selectedDestination = place.latLng;
      _status = place.name;
      _routePoints = [];
      _routeInfo = null;
    });
    _mapController.move(place.latLng, 16);
    if (drawRoute) {
      _drawRouteToSelected();
    }
  }

  Future<void> _drawRouteToSelected() async {
    final start = _myLatLng;
    final end = _selectedDestination;

    if (end == null) {
      _showMessage('اختر وجهة من البحث أولًا');
      return;
    }

    if (start == null) {
      await _locateMe(moveCamera: false);
    }

    final latestStart = _myLatLng;
    if (latestStart == null) {
      _showMessage('لم نستطع تحديد موقعك لرسم المسار');
      return;
    }

    setState(() {
      _isRouting = true;
      _status = 'جاري حساب مسار القيادة...';
    });

    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${latestStart.longitude},${latestStart.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true&alternatives=false',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        _showMessage('لم يتم العثور على مسار قيادة لهذه الوجهة');
        return;
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final points = coordinates.map((c) {
        final pair = c as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();

      final distanceKm = ((route['distance'] as num).toDouble() / 1000);
      final durationMin = ((route['duration'] as num).toDouble() / 60);

      setState(() {
        _routePoints = points;
        _routeInfo = '${distanceKm.toStringAsFixed(1)} كم • ${durationMin.toStringAsFixed(0)} دقيقة تقريبًا';
        _status = 'تم رسم مسار القيادة';
      });

      _fitRoute(points);
    } catch (e) {
      _showMessage('تعذر حساب المسار الآن. حاول مرة أخرى.');
      setState(() => _status = 'فشل حساب المسار');
    } finally {
      if (mounted) {
        setState(() => _isRouting = false);
      }
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(54)),
    );
  }

  void _clearRoute() {
    setState(() {
      _routePoints = [];
      _routeInfo = null;
      _status = 'تم مسح المسار';
    });
  }

  void _copySelectedCoordinates() {
    final dest = _selectedDestination;
    if (dest == null) {
      _showMessage('اختر مكانًا أولًا');
      return;
    }
    final text = '${dest.latitude}, ${dest.longitude}';
    Clipboard.setData(ClipboardData(text: text));
    _showMessage('تم نسخ الإحداثيات');
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myPoint = _myLatLng;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _amman,
                initialZoom: 8.2,
                minZoom: 6,
                maxZoom: 19,
                cameraConstraint: CameraConstraint.contain(bounds: _jordanBounds),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.explapp.jordanmaps',
                ),
                PolylineLayer(
                  polylines: [
                    if (_routePoints.length > 1)
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: const Color(0xFF22C55E),
                        borderStrokeWidth: 2,
                        borderColor: const Color(0xFF052E16),
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (myPoint != null)
                      Marker(
                        point: myPoint,
                        width: 48,
                        height: 48,
                        child: const _MapPin(
                          icon: Icons.my_location,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    if (_selectedDestination != null)
                      Marker(
                        point: _selectedDestination!,
                        width: 54,
                        height: 54,
                        child: const _MapPin(
                          icon: Icons.location_on,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildSearchPanel(),
                  const Spacer(),
                  _buildBottomPanel(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 118),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'locate',
                onPressed: _isLocating ? null : () => _locateMe(),
                child: _isLocating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.gps_fixed),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.small(
                heroTag: 'route',
                onPressed: _isRouting ? null : _drawRouteToSelected,
                child: _isRouting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.route),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF14532D),
                child: Icon(Icons.map, color: Color(0xFF86EFAC)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'خرائط الأردن',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              IconButton(
                tooltip: 'نسخ إحداثيات الوجهة',
                onPressed: _copySelectedCoordinates,
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchJordan(),
            decoration: InputDecoration(
              hintText: 'ابحث: عمان، الزرقاء، الجامعة الأردنية...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: _searchJordan,
                      icon: const Icon(Icons.arrow_back),
                    ),
              filled: true,
              fillColor: const Color(0xFF111827),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                itemBuilder: (context, index) {
                  final item = _results[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined, color: Color(0xFF86EFAC)),
                    title: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(item.type),
                    onTap: () => _selectResult(item),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF86EFAC)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_routeInfo != null) ...[
            const SizedBox(height: 8),
            Text(
              _routeInfo!,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF86EFAC),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isRouting ? null : _drawRouteToSelected,
                  icon: const Icon(Icons.directions_car),
                  label: const Text('مسار قيادة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _routePoints.isEmpty ? null : _clearRoute,
                  icon: const Icon(Icons.close),
                  label: const Text('مسح'),
                ),
              ),
            ],
          ),
          if (_myLatLng != null && _selectedDestination != null) ...[
            const SizedBox(height: 6),
            Text(
              'المسافة الهوائية: ${(_distance.as(LengthUnit.Kilometer, _myLatLng!, _selectedDestination!)).toStringAsFixed(2)} كم',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }
}
