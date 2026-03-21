import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/places_service.dart';
import '../../../../core/theme/app_colors.dart';

class DestinationSearchSheet extends StatefulWidget {
  final Function(String address, LatLng latLng) onDestinationSelected;

  const DestinationSearchSheet({super.key, required this.onDestinationSelected});

  @override
  State<DestinationSearchSheet> createState() => _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends State<DestinationSearchSheet> {
  final _searchController = TextEditingController();
  final _placesService = PlacesService();

  List<PlacePrediction> _predictions = [];
  bool _isLoading = false;
  bool _apiError = false;
  Timer? _debounce;

  // Popular places shown when there is no active search
  final List<Map<String, dynamic>> _popularPlaces = [
    {'name': 'Gare Centrale',            'lat': -4.3167, 'lng': 15.3136},
    {'name': 'Aéroport de N\'djili',     'lat': -4.3857, 'lng': 15.4446},
    {'name': 'Marché Central',           'lat': -4.3230, 'lng': 15.3125},
    {'name': 'Université de Kinshasa',   'lat': -4.4059, 'lng': 15.2967},
    {'name': 'Matonge',                  'lat': -4.3340, 'lng': 15.3100},
    {'name': 'Gombe (Centre-ville)',     'lat': -4.3100, 'lng': 15.2900},
    {'name': 'Limete Échangeur',         'lat': -4.3470, 'lng': 15.3420},
    {'name': 'Kintambo Magasin',         'lat': -4.3040, 'lng': 15.2700},
    {'name': 'Ngaliema (Binza)',         'lat': -4.3410, 'lng': 15.2470},
    {'name': 'Masina Petro-Congo',       'lat': -4.3830, 'lng': 15.3920},
    {'name': 'Victoire',                 'lat': -4.3275, 'lng': 15.3005},
    {'name': 'Bandal',                   'lat': -4.3310, 'lng': 15.2980},
    {'name': 'Kinshasa Kalamu',          'lat': -4.3433, 'lng': 15.3094},
    {'name': 'Ndjili Commune',           'lat': -4.3850, 'lng': 15.4350},
    {'name': 'Lemba Université',         'lat': -4.3790, 'lng': 15.3580},
    {'name': 'Bumbu Marché',             'lat': -4.3700, 'lng': 15.2870},
    {'name': 'Selembao Marché',          'lat': -4.3950, 'lng': 15.2620},
    {'name': 'Makala Prison',            'lat': -4.3540, 'lng': 15.2780},
    {'name': 'Kingabwa Port',            'lat': -4.2990, 'lng': 15.3780},
    {'name': 'Barumbu Rond-Point',       'lat': -4.3030, 'lng': 15.2970},
    {'name': 'Kinshasa La Gombe',        'lat': -4.3100, 'lng': 15.2900},
    {'name': 'Place du 24 Novembre',     'lat': -4.3220, 'lng': 15.3080},
    {'name': 'Hôpital Général Kinshasa', 'lat': -4.3340, 'lng': 15.3290},
    {'name': 'Centre Ville (Boulevard)', 'lat': -4.3200, 'lng': 15.3050},
    {'name': 'Marché de la Liberté',     'lat': -4.3410, 'lng': 15.3130},
  ];

  void _onSearch(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _isLoading = false;
        _apiError = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await _placesService.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (results.isEmpty && query.isNotEmpty) {
          // API returned nothing – flag so we show local fallback
          _apiError = true;
          _predictions = [];
        } else {
          _apiError = false;
          _predictions = results;
        }
      });
    });
  }

  Future<void> _selectPrediction(PlacePrediction pred) async {
    setState(() => _isLoading = true);
    final latLng = await _placesService.getPlaceLatLng(pred.placeId);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (latLng != null) {
      widget.onDestinationSelected(pred.description, latLng);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool searching = _searchController.text.trim().isNotEmpty;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: Column(
        children: [
          // ── Handle ──
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 16.h),

          // ── Header ──
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Où allez-vous à Kinshasa ?',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Commune, quartier, lieu populaire...',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),

          // ── Search field ──
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (v) {
                _onSearch(v);
                setState(() {}); // refresh suffix icon
              },
              decoration: InputDecoration(
                hintText: 'Rechercher à Kinshasa...',
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding:
                    EdgeInsets.symmetric(vertical: 0, horizontal: 14.w),
                prefixIcon: _isLoading
                    ? Padding(
                        padding: EdgeInsets.all(12.w),
                        child: SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      )
                    : Icon(Icons.search_rounded,
                        size: 22.sp, color: AppColors.textHint),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        color: AppColors.textHint,
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(height: 10.h),

          // ── Quick chips (visible when not searching) ──
          if (!searching) ...[
            SizedBox(
              height: 38.h,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                scrollDirection: Axis.horizontal,
                itemCount:
                    _popularPlaces.length > 8 ? 8 : _popularPlaces.length,
                separatorBuilder: (_, __) => SizedBox(width: 8.w),
                itemBuilder: (context, index) {
                  final place = _popularPlaces[index];
                  return GestureDetector(
                    onTap: () => widget.onDestinationSelected(
                      place['name'] as String,
                      LatLng(place['lat'] as double, place['lng'] as double),
                    ),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primaryDark, AppColors.primary],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.place_rounded,
                              size: 14.sp,
                              color: AppColors.textOnSecondary),
                          SizedBox(width: 5.w),
                          Text(
                            place['name'] as String,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textOnSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 14.h),
          ],

          // ── Results / popular list ──
          Expanded(
            child: searching
                ? _buildPredictions()
                : _buildPopularPlaces(),
          ),
        ],
      ),
    );
  }

  // ── Google Places predictions ──
  Widget _buildPredictions() {
    if (_isLoading && _predictions.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryDark),
      );
    }
    if (_predictions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48.sp, color: AppColors.textHint),
            SizedBox(height: 12.h),
            Text(
              'Aucun lieu trouvé à Kinshasa',
              style: TextStyle(
                  fontSize: 14.sp, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _predictions.length,
      itemBuilder: (context, i) {
        final pred = _predictions[i];
        return ListTile(
          contentPadding:
              EdgeInsets.symmetric(horizontal: 20.w, vertical: 2.h),
          leading: Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(Icons.location_on_rounded,
                color: Colors.white, size: 22.sp),
          ),
          title: Text(
            pred.mainText,
            style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          subtitle: pred.secondaryText.isNotEmpty
              ? Text(
                  pred.secondaryText,
                  style: TextStyle(
                      fontSize: 12.sp, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () => _selectPrediction(pred),
        );
      },
    );
  }

  // ── Static popular places ──
  Widget _buildPopularPlaces() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Text(
            'Lieux populaires',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(height: 6.h),
        Expanded(
          child: ListView.builder(
            itemCount: _popularPlaces.length,
            itemBuilder: (context, index) {
              final place = _popularPlaces[index];
              return ListTile(
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 20.w, vertical: 2.h),
                leading: Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(Icons.location_on_rounded,
                      color: AppColors.primaryDark, size: 22.sp),
                ),
                title: Text(
                  place['name'] as String,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                onTap: () => widget.onDestinationSelected(
                  place['name'] as String,
                  LatLng(
                      place['lat'] as double, place['lng'] as double),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
