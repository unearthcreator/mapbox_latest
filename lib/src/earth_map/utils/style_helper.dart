// style_helper.dart
import 'package:map_mvp_project/src/earth_map/utils/map_config.dart';
import 'package:map_mvp_project/models/world_config.dart';
import 'package:map_mvp_project/services/error_handler.dart'; // For logger

String determineMapStyleUri(WorldConfig config) {
  logger.i("User preferences - isFlatMap: ${config.isFlatMap}, mapType: ${config.mapType}, timeMode: ${config.timeMode}, manualTheme: ${config.manualTheme}");

  // For Flat Maps (Mercator)
  if (config.isFlatMap) {
    logger.i("Flat map branch reached.");
    if (config.timeMode.toLowerCase() == 'manual' && config.manualTheme != null) {
      final theme = config.manualTheme!.toLowerCase();
      logger.i("Flat map manual mode: theme = $theme");
      if (config.mapType.toLowerCase() == 'standard') {
        if (theme == 'day') {
          logger.i("Returning flat style URI for standard day: ${MapConfig.styleUriFlatStandardDay}");
          return MapConfig.styleUriFlatStandardDay;
        } else if (theme == 'dawn') {
          logger.i("Returning flat style URI for standard dawn: ${MapConfig.styleUriFlatStandardDawn}");
          return MapConfig.styleUriFlatStandardDawn;
        } else if (theme == 'dusk') {
          logger.i("Returning flat style URI for standard dusk: ${MapConfig.styleUriFlatStandardDusk}");
          return MapConfig.styleUriFlatStandardDusk;
        } else if (theme == 'night') {
          logger.i("Returning flat style URI for standard night: ${MapConfig.styleUriFlatStandardNight}");
          return MapConfig.styleUriFlatStandardNight;
        } else {
          logger.i("Flat map manual mode but theme not recognized: $theme");
        }
      } else if (config.mapType.toLowerCase() == 'satellite') {
        if (theme == 'day') {
          logger.i("Returning flat satellite style URI for day: ${MapConfig.styleUriFlatSatelliteDay}");
          return MapConfig.styleUriFlatSatelliteDay;
        } else if (theme == 'dawn') {
          logger.i("Returning flat satellite style URI for dawn: ${MapConfig.styleUriFlatSatelliteDawn}");
          return MapConfig.styleUriFlatSatelliteDawn;
        } else if (theme == 'dusk') {
          logger.i("Returning flat satellite style URI for dusk: ${MapConfig.styleUriFlatSatelliteDusk}");
          return MapConfig.styleUriFlatSatelliteDusk;
        } else if (theme == 'night') {
          logger.i("Returning flat satellite style URI for night: ${MapConfig.styleUriFlatSatelliteNight}");
          return MapConfig.styleUriFlatSatelliteNight;
        } else {
          logger.i("Flat satellite manual mode but theme not recognized: $theme");
        }
      }
    }
    logger.i("Returning fallback flat style (using default Earth style) for flat map.");
    return MapConfig.styleUriEarth; // Fallback for flat maps.
  } else {
    // For Globe Maps
    logger.i("Globe map branch reached.");
    if (config.timeMode.toLowerCase() == 'manual' && config.manualTheme != null) {
      final theme = config.manualTheme!.toLowerCase();
      logger.i("Globe manual mode: theme = $theme");
      if (config.mapType.toLowerCase() == 'standard') {
        if (theme == 'day') {
          logger.i("Returning globe style URI for standard day: ${MapConfig.styleUriGlobeStandardDay}");
          return MapConfig.styleUriGlobeStandardDay;
        } else if (theme == 'dawn') {
          logger.i("Returning globe style URI for standard dawn: ${MapConfig.styleUriGlobeStandardDawn}");
          return MapConfig.styleUriGlobeStandardDawn;
        } else if (theme == 'dusk') {
          logger.i("Returning globe style URI for standard dusk: ${MapConfig.styleUriGlobeStandardDusk}");
          return MapConfig.styleUriGlobeStandardDusk;
        } else if (theme == 'night') {
          logger.i("Returning globe style URI for standard night: ${MapConfig.styleUriGlobeStandardNight}");
          return MapConfig.styleUriGlobeStandardNight;
        } else {
          logger.i("Globe manual mode but theme not recognized: $theme");
        }
      } else if (config.mapType.toLowerCase() == 'satellite') {
        if (theme == 'day') {
          logger.i("Returning globe satellite style URI for day: ${MapConfig.styleUriGlobeSatelliteDay}");
          return MapConfig.styleUriGlobeSatelliteDay;
        } else if (theme == 'dawn') {
          logger.i("Returning globe satellite style URI for dawn: ${MapConfig.styleUriGlobeSatelliteDawn}");
          return MapConfig.styleUriGlobeSatelliteDawn;
        } else if (theme == 'dusk') {
          logger.i("Returning globe satellite style URI for dusk: ${MapConfig.styleUriGlobeSatelliteDusk}");
          return MapConfig.styleUriGlobeSatelliteDusk;
        } else if (theme == 'night') {
          logger.i("Returning globe satellite style URI for night: ${MapConfig.styleUriGlobeSatelliteNight}");
          return MapConfig.styleUriGlobeSatelliteNight;
        } else {
          logger.i("Globe satellite manual mode but theme not recognized: $theme");
        }
      }
    }
    logger.i("Returning fallback globe style: ${MapConfig.styleUriEarth}");
    return MapConfig.styleUriEarth;
  }
}