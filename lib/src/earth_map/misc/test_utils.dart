// File: testing_utils.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:map_mvp_project/services/error_handler.dart'; // For logger
import 'package:map_mvp_project/src/earth_map/annotations/map_annotations_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Returns a Positioned button that clears annotations (from Hive and the map)
/// for the given worldId. If worldId is not provided, it clears all annotations.
Widget buildClearAnnotationsButton({
  required MapAnnotationsManager annotationsManager,
  String? worldId,
}) {
  return Positioned(
    top: 40,
    right: 10,
    child: ElevatedButton(
      onPressed: () async {
        logger.i('Clear button pressed - clearing annotations for worldId: $worldId');

        // 1) Remove annotations from Hive:
        final box = await Hive.openBox<Map>('annotationsBox');
        if (worldId != null) {
          final keysToDelete = <dynamic>[];
          for (var key in box.keys) {
            final annotationMap = box.get(key);
            if (annotationMap != null && annotationMap['worldId'] == worldId) {
              keysToDelete.add(key);
            }
          }
          for (var key in keysToDelete) {
            await box.delete(key);
          }
          logger.i('Annotations with worldId $worldId cleared from Hive. Remaining items: ${box.length}');
        } else {
          await box.clear();
          logger.i('All annotations cleared from Hive.');
        }
        await box.close();

        // 2) Remove annotations from the map visually.
        // (Assuming the annotationsManager currently holds only annotations for the active world.)
        await annotationsManager.removeAllAnnotations();
        logger.i('All annotations removed from the map.');
        logger.i('Done clearing. You can now add new annotations.');
      },
      child: const Text('Clear Annotations'),
    ),
  );
}

/// Returns a Positioned button that clears all image files in the app's images folder.
Widget buildClearImagesButton() {
  return Positioned(
    top: 90,
    right: 10,
    child: ElevatedButton(
      onPressed: () async {
        logger.i('Clear images button pressed - clearing images folder files.');
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(p.join(appDir.path, 'images'));

        if (await imagesDir.exists()) {
          final files = imagesDir.listSync();
          for (var file in files) {
            if (file is File) {
              await file.delete();
            }
          }
          logger.i('All image files cleared from ${imagesDir.path}');
        } else {
          logger.i('Images directory does not exist, nothing to clear.');
        }
      },
      child: const Text('Clear Images'),
    ),
  );
}

/// Returns a Positioned button that deletes the entire images folder in the app directory.
Widget buildDeleteImagesFolderButton() {
  return Positioned(
    top: 140,
    right: 10,
    child: ElevatedButton(
      onPressed: () async {
        logger.i('Delete images folder button pressed - deleting entire images folder.');
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(p.join(appDir.path, 'images'));

        if (await imagesDir.exists()) {
          await imagesDir.delete(recursive: true);
          logger.i('Images directory deleted.');
        } else {
          logger.i('Images directory does not exist, nothing to delete.');
        }
      },
      child: const Text('Delete Images Folder'),
    ),
  );
}