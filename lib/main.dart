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
    this.distanceMeters,
  });

  final String name;
  final LatLng latLng;
  final String type;
  final double? distanceMeters;
}

class SearchCategory {
  const SearchCategory({
    required this.label,
    required this.icon,
    required this.filters,
    required this.keywords,
  });

  final String label;
  final IconData icon;
  final List<String> filters;
  final List<String> keywords;
}

class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.shortInstruction,
    required this.location,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.type,
    required this.modifier,
    required this.roadName,
  });

  final String instruction;
  final String shortInstruction;
  final LatLng location;
  final double distanceMeters;
  final double durationSeconds;
  final String type;
  final String modifier;
  final String roadName;
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

  static const List<SearchCategory> _categories = [
    SearchCategory(
      label: 'محلات',
      icon: Icons.storefront,
      filters: ['["shop"]'],
      keywords: ['محل', 'محلات', 'متجر', 'متاجر', 'تجاري', 'تجارية', 'shop', 'store'],
    ),
    SearchCategory(
      label: 'بقالة',
      icon: Icons.local_grocery_store,
      filters: [
        '["shop"="supermarket"]',
        '["shop"="convenience"]',
        '["shop"="grocery"]',
      ],
      keywords: ['بقالة', 'سوبر', 'سوبرماركت', 'سوبر ماركت', 'تموين', 'مواد غذائية', 'grocery', 'supermarket'],
    ),
    SearchCategory(
      label: 'مطاعم',
      icon: Icons.restaurant,
      filters: [
        '["amenity"="restaurant"]',
        '["amenity"="fast_food"]',
        '["amenity"="food_court"]',
      ],
      keywords: ['مطعم', 'مطاعم', 'اكل', 'أكل', 'وجبات', 'restaurant', 'food'],
    ),
    SearchCategory(
      label: 'كافيه',
      icon: Icons.local_cafe,
      filters: [
        '["amenity"="cafe"]',
        '["shop"="coffee"]',
      ],
      keywords: ['كافيه', 'كوفي', 'قهوة', 'مقهى', 'مقاهي', 'cafe', 'coffee'],
    ),
    SearchCategory(
      label: 'صيدليات',
      icon: Icons.local_pharmacy,
      filters: [
        '["amenity"="pharmacy"]',
        '["shop"="chemist"]',
      ],
      keywords: ['صيدلية', 'صيدليات', 'دواء', 'pharmacy'],
    ),
    SearchCategory(
      label: 'وقود',
      icon: Icons.local_gas_station,
      filters: ['["amenity"="fuel"]'],
      keywords: ['بنزين', 'محطة', 'وقود', 'كازية', 'fuel', 'gas'],
    ),
    SearchCategory(
      label: 'بنوك',
      icon: Icons.account_balance,
      filters: [
        '["amenity"="bank"]',
        '["amenity"="atm"]',
      ],
      keywords: ['بنك', 'بنوك', 'صراف', 'atm', 'bank'],
    ),
    SearchCategory(
      label: 'مستشفيات',
      icon: Icons.local_hospital,
      filters: [
        '["amenity"="hospital"]',
        '["amenity"="clinic"]',
        '["healthcare"]',
      ],
      keywords: ['مستشفى', 'مستشفيات', 'عيادة', 'عيادات', 'طبيب', 'hospital', 'clinic'],
    ),
    SearchCategory(
      label: 'مدارس',
      icon: Icons.school,
      filters: [
        '["amenity"="school"]',
        '["amenity"="university"]',
        '["amenity"="college"]',
      ],
      keywords: ['مدرسة', 'مدارس', 'جامعة', 'كلية', 'school', 'university'],
    ),
  ];

  Position? _currentPosition;
  LatLng? _selectedDestination;
  String? _selectedDestinationName;
  List<PlaceResult> _results = [];
  List<LatLng> _routePoints = [];
  List<RouteStep> _routeSteps = [];
  String _status = 'جاهز للبحث داخل الأردن';
  String? _routeInfo;
  bool _isSearching = false;
  bool _isRouting = false;
  bool _isLocating = false;
  bool _isSearchCollapsed = false;
  bool _isNavigating = false;
  bool _isOffRoute = false;
  int _currentStepIndex = 0;
  StreamSubscription<Position>? _positionSubscription;

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  LatLng? get _myLatLng {
    final p = _currentPosition;
    if (p == null) return null;
    return LatLng(p.latitude, p.longitude);
  }

  RouteStep? get _nextStep {
    if (_routeSteps.isEmpty) return null;
    final index = _currentStepIndex.clamp(0, _routeSteps.length - 1) as int;
    return _routeSteps[index];
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
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
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
      _showMessage('اكتب اسم مكان أو اختر فئة مثل محلات أو مطاعم');
      return;
    }

    final category = _categoryForQuery(query);
    if (category != null) {
      await _searchBusinessCategory(category);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _isSearchCollapsed = false;
      _results = [];
      _routePoints = [];
      _routeSteps = [];
      _routeInfo = null;
      _status = 'جاري البحث عن: $query';
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '10',
        'countrycodes': 'jo',
        'accept-language': 'ar,en',
        'viewbox': '34.88,33.45,39.35,29.15',
        'bounded': '1',
      });

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'jordan_maps_online/1.2 contact:yaya15112016@gmail.com',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as List<dynamic>;
      final center = _searchCenter();
      final items = decoded.map((item) {
        final map = item as Map<String, dynamic>;
        final latLng = LatLng(
          double.parse(map['lat'].toString()),
          double.parse(map['lon'].toString()),
        );
        return PlaceResult(
          name: (map['display_name'] ?? 'مكان بدون اسم').toString(),
          latLng: latLng,
          type: (map['type'] ?? map['class'] ?? 'مكان').toString(),
          distanceMeters: _distance.as(LengthUnit.Meter, center, latLng),
        );
      }).where((p) => _jordanBounds.contains(p.latLng)).toList();

      items.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));

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

  Future<void> _searchBusinessCategory(SearchCategory category) async {
    FocusScope.of(context).unfocus();
    final center = _searchCenter();
    const radiusMeters = 18000;

    setState(() {
      _isSearching = true;
      _isSearchCollapsed = false;
      _results = [];
      _routePoints = [];
      _routeSteps = [];
      _routeInfo = null;
      _status = 'جاري البحث عن ${category.label} حول موقعك أو مركز الخريطة...';
    });

    try {
      final query = _buildOverpassQuery(category, center, radiusMeters);
      final response = await http
          .post(
            Uri.https('overpass-api.de', '/api/interpreter'),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'User-Agent': 'jordan_maps_online/1.2 contact:yaya15112016@gmail.com',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List<dynamic>? ?? const []);
      final seen = <String>{};
      final items = <PlaceResult>[];

      for (final raw in elements) {
        final map = raw as Map<String, dynamic>;
        final tags = (map['tags'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final lat = _readLat(map);
        final lon = _readLon(map);
        if (lat == null || lon == null) continue;

        final latLng = LatLng(lat, lon);
        if (!_jordanBounds.contains(latLng)) continue;

        final name = _placeName(tags, category.label);
        final key = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)},$name';
        if (!seen.add(key)) continue;

        final distanceMeters = _distance.as(LengthUnit.Meter, center, latLng);
        items.add(
          PlaceResult(
            name: name,
            latLng: latLng,
            type: _placeType(tags, category.label),
            distanceMeters: distanceMeters,
          ),
        );
      }

      items.sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
      final limited = items.take(30).toList();

      setState(() {
        _results = limited;
        _status = limited.isEmpty
            ? 'لم أجد ${category.label} قريبة. جرّب تحريك الخريطة أو تفعيل موقعي'
            : 'تم العثور على ${limited.length} نتيجة من ${category.label}';
      });

      if (limited.isNotEmpty) {
        _selectResult(limited.first, drawRoute: false);
      }
    } catch (e) {
      _showMessage('تعذر جلب الأماكن التجارية الآن. تأكد من الإنترنت ثم أعد المحاولة.');
      setState(() => _status = 'فشل بحث ${category.label}');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  String _buildOverpassQuery(SearchCategory category, LatLng center, int radiusMeters) {
    final filters = category.filters.map((filter) {
      return '''
        node$filter(around:$radiusMeters,${center.latitude},${center.longitude});
        way$filter(around:$radiusMeters,${center.latitude},${center.longitude});
        relation$filter(around:$radiusMeters,${center.latitude},${center.longitude});
      ''';
    }).join('\n');

    return '''
      [out:json][timeout:25];
      (
        $filters
      );
      out center tags 100;
    ''';
  }

  LatLng _searchCenter() {
    final myPoint = _myLatLng;
    if (myPoint != null && _jordanBounds.contains(myPoint)) return myPoint;
    try {
      final center = _mapController.camera.center;
      if (_jordanBounds.contains(center)) return center;
    } catch (_) {
      // Map camera may not be ready during the first frame.
    }
    return _amman;
  }

  SearchCategory? _categoryForQuery(String query) {
    final cleaned = _cleanArabic(query);
    for (final category in _categories) {
      for (final keyword in category.keywords) {
        if (cleaned.contains(_cleanArabic(keyword))) {
          return category;
        }
      }
    }
    return null;
  }

  String _cleanArabic(String value) {
    return value
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double? _readLat(Map<String, dynamic> map) {
    final center = map['center'];
    final value = map['lat'] ?? (center is Map ? center['lat'] : null);
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double? _readLon(Map<String, dynamic> map) {
    final center = map['center'];
    final value = map['lon'] ?? (center is Map ? center['lon'] : null);
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _placeName(Map<String, dynamic> tags, String fallback) {
    final name = tags['name:ar'] ?? tags['name'] ?? tags['brand:ar'] ?? tags['brand'];
    final text = name?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
    return fallback;
  }

  String _placeType(Map<String, dynamic> tags, String fallback) {
    final amenity = tags['amenity']?.toString();
    final shop = tags['shop']?.toString();
    final healthcare = tags['healthcare']?.toString();
    final value = amenity ?? shop ?? healthcare;
    if (value == null || value.isEmpty) return fallback;
    return _typeLabels[value] ?? value;
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} م';
    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  static const Map<String, String> _typeLabels = {
    'supermarket': 'سوبرماركت',
    'convenience': 'بقالة',
    'grocery': 'مواد غذائية',
    'restaurant': 'مطعم',
    'fast_food': 'وجبات سريعة',
    'food_court': 'مطاعم',
    'cafe': 'كافيه',
    'coffee': 'قهوة',
    'pharmacy': 'صيدلية',
    'chemist': 'صيدلية',
    'fuel': 'محطة وقود',
    'bank': 'بنك',
    'atm': 'صراف آلي',
    'hospital': 'مستشفى',
    'clinic': 'عيادة',
    'school': 'مدرسة',
    'university': 'جامعة',
    'college': 'كلية',
  };

  void _selectResult(PlaceResult place, {bool drawRoute = true}) {
    _stopNavigation(showMessage: false);
    setState(() {
      _selectedDestination = place.latLng;
      _selectedDestinationName = place.name;
      _status = place.name;
      _routePoints = [];
      _routeSteps = [];
      _routeInfo = null;
      _isSearchCollapsed = true;
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
      _isNavigating = false;
      _status = 'جاري حساب مسار القيادة...';
    });

    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${latestStart.longitude},${latestStart.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true&alternatives=false&language=ar',
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

      final distanceMeters = (route['distance'] as num).toDouble();
      final durationSeconds = (route['duration'] as num).toDouble();
      final steps = _parseRouteSteps(route);

      setState(() {
        _routePoints = points;
        _routeSteps = steps;
        _routeInfo = '${(distanceMeters / 1000).toStringAsFixed(1)} كم • ${(durationSeconds / 60).toStringAsFixed(0)} دقيقة تقريبًا';
        _currentStepIndex = 0;
        _isOffRoute = false;
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

  List<RouteStep> _parseRouteSteps(Map<String, dynamic> route) {
    final legs = route['legs'] as List<dynamic>? ?? const [];
    final parsed = <RouteStep>[];
    for (final legRaw in legs) {
      final leg = legRaw as Map<String, dynamic>;
      final steps = leg['steps'] as List<dynamic>? ?? const [];
      for (final stepRaw in steps) {
        final step = stepRaw as Map<String, dynamic>;
        final maneuver = step['maneuver'] as Map<String, dynamic>? ?? const {};
        final location = maneuver['location'] as List<dynamic>?;
        if (location == null || location.length < 2) continue;

        final type = maneuver['type']?.toString() ?? '';
        final modifier = maneuver['modifier']?.toString() ?? '';
        final roadName = step['name']?.toString().trim() ?? '';
        final distanceMeters = (step['distance'] as num?)?.toDouble() ?? 0;
        final durationSeconds = (step['duration'] as num?)?.toDouble() ?? 0;
        final instruction = _arabicInstruction(type, modifier, roadName, distanceMeters);

        parsed.add(
          RouteStep(
            instruction: instruction,
            shortInstruction: _shortTurnText(type, modifier),
            location: LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            type: type,
            modifier: modifier,
            roadName: roadName,
          ),
        );
      }
    }
    return parsed;
  }

  String _arabicInstruction(String type, String modifier, String roadName, double distanceMeters) {
    final road = roadName.isEmpty ? '' : ' على $roadName';
    final distanceText = _formatDistance(distanceMeters);

    if (type == 'depart') return 'ابدأ القيادة$road';
    if (type == 'arrive') return 'وصلت إلى الوجهة';
    if (type == 'roundabout' || type == 'rotary') return 'ادخل الدوار ثم تابع حسب المخرج المناسب$road';
    if (type == 'merge') return 'اندمج مع الطريق$road';
    if (type == 'fork') return 'عند التفرع ${_modifierArabic(modifier)}$road';
    if (type == 'new name') return 'تابع$road';
    if (type == 'continue') return 'تابع للأمام$road';
    if (type == 'turn' || type == 'end of road') {
      return 'بعد $distanceText ${_modifierArabic(modifier)}$road';
    }
    return 'بعد $distanceText ${_modifierArabic(modifier)}$road';
  }

  String _modifierArabic(String modifier) {
    switch (modifier) {
      case 'right':
        return 'انعطف يمينًا';
      case 'left':
        return 'انعطف يسارًا';
      case 'slight right':
        return 'اتجه قليلًا إلى اليمين';
      case 'slight left':
        return 'اتجه قليلًا إلى اليسار';
      case 'sharp right':
        return 'انعطف يمينًا بحدة';
      case 'sharp left':
        return 'انعطف يسارًا بحدة';
      case 'straight':
        return 'تابع للأمام';
      case 'uturn':
        return 'استدر للخلف';
      default:
        return 'تابع الطريق';
    }
  }

  String _shortTurnText(String type, String modifier) {
    if (type == 'arrive') return 'الوصول';
    if (type == 'roundabout' || type == 'rotary') return 'دوار';
    if (modifier.contains('right')) return 'يمين';
    if (modifier.contains('left')) return 'يسار';
    if (modifier == 'uturn') return 'رجوع';
    return 'أمام';
  }

  IconData _stepIcon(RouteStep? step) {
    if (step == null) return Icons.navigation;
    if (step.type == 'arrive') return Icons.flag;
    if (step.type == 'roundabout' || step.type == 'rotary') return Icons.roundabout_right;
    if (step.modifier.contains('right')) return Icons.turn_right;
    if (step.modifier.contains('left')) return Icons.turn_left;
    if (step.modifier == 'uturn') return Icons.u_turn_left;
    return Icons.straight;
  }

  Future<void> _startNavigation() async {
    if (_routePoints.isEmpty) {
      await _drawRouteToSelected();
    }
    if (_routePoints.isEmpty) return;

    await _locateMe(moveCamera: false);
    final myPoint = _myLatLng;
    if (myPoint == null) return;

    await _positionSubscription?.cancel();
    setState(() {
      _isNavigating = true;
      _isSearchCollapsed = true;
      _isOffRoute = false;
      _currentStepIndex = _nearestStepIndex(myPoint);
      _status = 'بدأ وضع القيادة';
    });

    _mapController.move(myPoint, 17);

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        if (!mounted) return;
        _handleDrivingPosition(position);
      },
      onError: (_) => _showMessage('تعذر متابعة الموقع أثناء القيادة'),
    );
  }

  void _handleDrivingPosition(Position position) {
    final point = LatLng(position.latitude, position.longitude);
    final nearestRouteDistance = _distanceToRoute(point, _routePoints);
    var nextIndex = _currentStepIndex;

    if (_routeSteps.isNotEmpty) {
      for (var i = _currentStepIndex; i < _routeSteps.length; i++) {
        final d = _distance.as(LengthUnit.Meter, point, _routeSteps[i].location);
        if (d < 35 && i < _routeSteps.length - 1) {
          nextIndex = i + 1;
        } else {
          break;
        }
      }
    }

    setState(() {
      _currentPosition = position;
      _currentStepIndex = nextIndex;
      _isOffRoute = nearestRouteDistance > 90;
      _status = _isOffRoute ? 'أنت بعيد عن المسار. أعد حساب الطريق' : 'وضع القيادة يعمل';
    });

    _mapController.move(point, 17);
  }

  int _nearestStepIndex(LatLng point) {
    if (_routeSteps.isEmpty) return 0;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _routeSteps.length; i++) {
      final d = _distance.as(LengthUnit.Meter, point, _routeSteps[i].location);
      if (d < bestDistance) {
        bestDistance = d;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double _distanceToRoute(LatLng point, List<LatLng> route) {
    if (route.isEmpty) return double.infinity;
    var best = double.infinity;
    for (var i = 0; i < route.length; i += 3) {
      final d = _distance.as(LengthUnit.Meter, point, route[i]);
      if (d < best) best = d;
    }
    return best;
  }

  void _stopNavigation({bool showMessage = true}) {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    setState(() {
      _isNavigating = false;
      _isOffRoute = false;
      _status = showMessage ? 'تم إيقاف القيادة' : _status;
    });
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
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(40, 130, 40, 190)),
    );
  }

  void _clearRoute() {
    _stopNavigation(showMessage: false);
    setState(() {
      _routePoints = [];
      _routeSteps = [];
      _routeInfo = null;
      _currentStepIndex = 0;
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
                        strokeWidth: _isNavigating ? 8 : 6,
                        color: _isOffRoute ? const Color(0xFFF97316) : const Color(0xFF22C55E),
                        borderStrokeWidth: 3,
                        borderColor: const Color(0xFF052E16),
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (myPoint != null)
                      Marker(
                        point: myPoint,
                        width: 56,
                        height: 56,
                        child: _MapPin(
                          icon: _isNavigating ? Icons.navigation : Icons.my_location,
                          color: const Color(0xFF38BDF8),
                        ),
                      ),
                    if (_selectedDestination != null)
                      Marker(
                        point: _selectedDestination!,
                        width: 56,
                        height: 56,
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
                  if (_isNavigating) _buildNavigationBanner() else _buildSearchPanel(),
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

  Widget _buildNavigationBanner() {
    final step = _nextStep;
    final myPoint = _myLatLng;
    final distanceToStep = step == null || myPoint == null
        ? null
        : _distance.as(LengthUnit.Meter, myPoint, step.location);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isOffRoute ? const Color(0xF27C2D12) : const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: const Color(0xFF14532D),
            child: Icon(_stepIcon(step), color: const Color(0xFF86EFAC), size: 34),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isOffRoute)
                  const Text(
                    'أنت خارج المسار',
                    style: TextStyle(color: Color(0xFFFDE68A), fontWeight: FontWeight.w900),
                  ),
                Text(
                  _isOffRoute ? 'اضغط إعادة حساب لتصحيح الطريق' : (step?.instruction ?? 'تابع القيادة'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  distanceToStep == null ? 'وضع القيادة نشط' : 'المناورة القادمة بعد ${_formatDistance(distanceToStep)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.74), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'إيقاف القيادة',
            onPressed: () => _stopNavigation(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
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
      child: _isSearchCollapsed ? _buildCollapsedSearchPanel() : _buildExpandedSearchPanel(),
    );
  }

  Widget _buildCollapsedSearchPanel() {
    return Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFF14532D),
          child: Icon(Icons.map, color: Color(0xFF86EFAC)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('خرائط الأردن', style: TextStyle(fontWeight: FontWeight.w900)),
              Text(
                _selectedDestinationName ?? 'اضغط للبحث',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'فتح البحث',
          onPressed: () => setState(() => _isSearchCollapsed = false),
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: 'نسخ الإحداثيات',
          onPressed: _copySelectedCoordinates,
          icon: const Icon(Icons.copy),
        ),
      ],
    );
  }

  Widget _buildExpandedSearchPanel() {
    return Column(
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
            TextButton.icon(
              onPressed: () => setState(() => _isSearchCollapsed = true),
              icon: const Icon(Icons.keyboard_arrow_up),
              label: const Text('تصغير'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchJordan(),
          decoration: InputDecoration(
            hintText: 'ابحث: صيدلية، مطعم، محل، اسم مكان...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'بحث',
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
        const SizedBox(height: 10),
        _buildCategoryChips(),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 165),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    item.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: item.distanceMeters == null
                      ? null
                      : Text(
                          _formatDistance(item.distanceMeters),
                          style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w900),
                        ),
                  onTap: () => _selectResult(item),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          return ActionChip(
            avatar: Icon(category.icon, size: 18, color: const Color(0xFF86EFAC)),
            label: Text(category.label),
            backgroundColor: const Color(0xFF172554),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            onPressed: _isSearching
                ? null
                : () {
                    _searchController.text = category.label;
                    _searchBusinessCategory(category);
                  },
          );
        },
      ),
    );
  }

  Widget _buildBottomPanel() {
    final destination = _selectedDestinationName;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_isOffRoute ? Icons.warning_amber : Icons.info_outline, color: const Color(0xFF86EFAC)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  destination == null ? _status : 'إلى: $destination',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (_routeInfo != null) ...[
            const SizedBox(height: 5),
            Text(
              _routeInfo!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF86EFAC)),
            ),
          ],
          if (_nextStep != null && !_isNavigating) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(_stepIcon(_nextStep), color: const Color(0xFF93C5FD)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'أول توجيه: ${_nextStep!.instruction}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isRouting
                      ? null
                      : _isNavigating
                          ? null
                          : _startNavigation,
                  icon: const Icon(Icons.navigation),
                  label: Text(_routePoints.isEmpty ? 'احسب وابدأ' : 'ابدأ القيادة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isRouting ? null : _drawRouteToSelected,
                  icon: const Icon(Icons.route),
                  label: const Text('مسار'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: _routePoints.isEmpty ? null : _clearRoute,
                icon: const Icon(Icons.close),
                tooltip: 'مسح',
              ),
            ],
          ),
          if (_isOffRoute) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _drawRouteToSelected,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة حساب المسار من موقعي الحالي'),
            ),
          ],
          if (_myLatLng != null && _selectedDestination != null) ...[
            const SizedBox(height: 6),
            Text(
              'المسافة الهوائية: ${(_distance.as(LengthUnit.Kilometer, _myLatLng!, _selectedDestination!)).toStringAsFixed(2)} كم',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
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
