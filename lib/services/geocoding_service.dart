import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:map_mvp_project/services/error_handler.dart';

class GeocodingService {
  static const String accessToken = "pk.eyJ1IjoidW5lYXJ0aGNyZWF0b3IiLCJhIjoiY20yam4yODlrMDVwbzJrcjE5cW9vcDJmbiJ9.L2tmRAkt0jKLd8-fWaMWfA";

  // ---------------------------------------------------------------------------
  // 1) Forward Geocoding: address => { lat, lng, shortAddress, fullAddress }
  //    Now returns a map that also includes shortAddress & fullAddress.
  // ---------------------------------------------------------------------------
  static Future<Map<String, dynamic>?> fetchCoordinatesFromAddress(String address) async {
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(address)}.json'
      '?access_token=$accessToken'
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      logger.i('Geocoding (forward) response: $data');

      if (data['features'] != null && data['features'].isNotEmpty) {
        final feature = data['features'][0];
        final center = feature['center']; // [lng, lat]
        final lng = center[0];
        final lat = center[1];

        logger.i('Coordinates found: lat=$lat, lng=$lng');

        // Extract the "full" address (place_name) from the feature
        final placeName = feature['place_name'] as String?;

        // Also try to construct a short address:
        final text = feature['text'] as String?;     // e.g. street name
        final addressNum = feature['address'] as String?; // e.g. house number
        String? shortAddr;
        if (text != null && addressNum != null) {
          shortAddr = '$addressNum $text'; 
        } else if (text != null) {
          shortAddr = text;
        } else {
          shortAddr = placeName; // fallback
        }

        logger.i('shortAddress="$shortAddr", fullAddress="$placeName"');

        return {
          'lat': lat,
          'lng': lng,
          'shortAddress': shortAddr,
          'fullAddress': placeName,
        };
      } else {
        logger.w('No features found for given address.');
        return null;
      }
    } else {
      logger.e('Failed to fetch geocoding data: ${response.statusCode}');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 2) Fetch Suggestions (Autocomplete) for partial address input
  //    (Still returns a list of place_name strings; you could refine to short addresses if desired.)
  // ---------------------------------------------------------------------------
  static Future<List<String>> fetchAddressSuggestions(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
      '?access_token=$accessToken&autocomplete=true&limit=5'
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['features'] != null && data['features'].isNotEmpty) {
        final List<String> suggestions = [];
        for (var feature in data['features']) {
          final placeName = feature['place_name'] as String?;
          if (placeName != null) {
            suggestions.add(placeName);
          }
        }
        return suggestions;
      }
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // 3) Reverse Geocoding (Full): lat/lng => place_name
  // ---------------------------------------------------------------------------
  /// Returns the **full** comma-separated place_name 
  /// (e.g. "221B Baker Street, Marylebone, London...").
  static Future<String?> fetchSingleAddress(double lat, double lng) async {
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
      '?access_token=$accessToken&limit=1'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        logger.i('Reverse geocoding response: $data');

        if (data['features'] != null && data['features'].isNotEmpty) {
          final placeName = data['features'][0]['place_name'] as String?;
          if (placeName != null && placeName.isNotEmpty) {
            logger.i('Address found: $placeName');
            return placeName;
          }
        }
        logger.w('No place_name found for lat=$lat, lng=$lng');
        return null;
      } else {
        logger.e('Reverse geocoding failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      logger.e('Exception during reverse geocoding', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 4) Reverse Geocoding (Short): lat/lng => "221B Baker Street" etc.
  // ---------------------------------------------------------------------------
  /// Returns a **shorter** address by parsing `address` + `text` fields if available.
  /// Example: "221B Baker Street". Fallback to `text` alone, then `place_name`.
  static Future<String?> fetchShortAddress(double lat, double lng) async {
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
      '?access_token=$accessToken&limit=1'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        logger.i('Reverse geocoding (short) response: $data');

        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final text = feature['text'] as String?;
          final addressNum = feature['address'] as String?;
          final placeName = feature['place_name'] as String?;

          if (text != null && addressNum != null) {
            final shortAddr = '$addressNum $text';
            logger.i('Short address: $shortAddr');
            return shortAddr;
          } else if (text != null) {
            logger.i('Short address: $text');
            return text;
          } else if (placeName != null) {
            logger.i('Fallback place_name: $placeName');
            return placeName;
          }
        }
        logger.w('No features found for lat=$lat, lng=$lng');
        return null;
      } else {
        logger.e('Reverse geocoding (short) failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      logger.e('Exception during short reverse geocoding', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}