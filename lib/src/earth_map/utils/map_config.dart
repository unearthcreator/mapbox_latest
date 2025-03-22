// map_config.dart
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Contains various style URIs and default configurations for Mapbox maps
/// used throughout the app.
class MapConfig {
  /// Style for your "Earth" page (existing style).
  static const String styleUriEarth = 
      "https://api.mapbox.com/styles/v1/unearthcreator/cm2jwm74e004j01ny7osa5ve8?access_token=pk.eyJ1IjoidW5lYXJ0aGNyZWF0b3IiLCJhIjoiY20yam4yODlrMDVwbzJrcjE5cW9vcDJmbiJ9.L2tmRAkt0jKLd8-fWaMWfA";

  /// Style for the "Default Globe" or the new globe style you want in EarthCreator.
  static const String styleUriGlobe = 
      "mapbox://styles/unearthcreator/cm59tvj11000t01sc8z2c3k0x";

  /// New style URI for a standard globe with manual "Day" preference.
  static const String styleUriGlobeStandardDay =
      "mapbox://styles/unearthcreator/cm8kk457f018c01se2j7mfnlf";

  /// New style URI for a standard globe with manual "Dawn" preference.
  static const String styleUriGlobeStandardDawn =
      "mapbox://styles/unearthcreator/cm8kr8n2200as01s5hxhv5t7h";

  /// New style URI for a standard globe with manual "Dusk" preference.
  static const String styleUriGlobeStandardDusk =
      "mapbox://styles/unearthcreator/cm8kr9yje019801sa4piodemu";

  /// New style URI for a standard globe with manual "Night" preference.
  static const String styleUriGlobeStandardNight =
      "mapbox://styles/unearthcreator/cm8kre34e004l01s77ze8dnp4";

  /// New style URI for a standard flat earth with manual "Day" preference.
  static const String styleUriFlatStandardDay =
      "mapbox://styles/unearthcreator/cm8kkp3s801ab01qzdi4c8x1y";

  /// New style URI for a standard flat earth with manual "Dawn" preference.
  static const String styleUriFlatStandardDawn =
      "mapbox://styles/unearthcreator/cm8koog2g019k01sbb30n80qi";

  /// New style URI for a standard flat earth with manual "Dusk" preference.
  static const String styleUriFlatStandardDusk =
      "mapbox://styles/unearthcreator/cm8kqrfkf00uy01qs5pz4a6li";

  /// New style URI for a standard flat earth with manual "Night" preference.
  static const String styleUriFlatStandardNight =
      "mapbox://styles/unearthcreator/cm8kqtky601ai01qzddxucqe0";

  /// Default camera options, focusing on a wide area (zoom 1, near center of US).
  static CameraOptions defaultCameraOptions = CameraOptions(
    center: Point(coordinates: Position(-98.0, 39.5)),
    zoom: 1.0,
    bearing: 0.0,
    pitch: 0.0,
  );

  /// A helper to provide default annotation options (e.g., an icon).
  static PointAnnotationOptions getDefaultAnnotationOptions(Point geometry) {
    return PointAnnotationOptions(
      geometry: geometry,
      iconSize: 1.0,
      iconImage: "mapbox-check",
    );
  }
}