import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:map_mvp_project/models/annotation.dart';
import 'package:map_mvp_project/repositories/local_annotations_repository.dart';
import 'package:map_mvp_project/services/error_handler.dart';
import 'package:map_mvp_project/src/earth_map/annotations/map_annotations_manager.dart';
import 'package:map_mvp_project/src/earth_map/annotations/annotation_id_linker.dart';
import 'package:map_mvp_project/src/earth_map/dialogs/annotation_initialization_dialog.dart';
import 'package:map_mvp_project/src/earth_map/dialogs/annotation_form_dialog.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;
import 'package:uuid/uuid.dart'; // if you need unique IDs
// ... any other imports ...

class AnnotationActions {
  final LocalAnnotationsRepository localRepo;
  final MapAnnotationsManager annotationsManager;
  final AnnotationIdLinker annotationIdLinker;

  AnnotationActions({
    required this.localRepo,
    required this.annotationsManager,
    required this.annotationIdLinker,
  });

  /// Edits the given map annotation by retrieving its data from Hive,
  /// then showing the second dialog (form dialog). If user presses "Change"
  /// on that form, we re-open the first dialog (initialization) with
  /// existing data so user can modify it, exactly like in creation mode.
  Future<void> editAnnotation({
    required BuildContext context,
    required PointAnnotation? mapAnnotation,
  }) async {
    if (mapAnnotation == null) {
      logger.w('No annotation given, cannot edit.');
      return;
    }

    logger.i('Attempting to edit annotation with map ID: ${mapAnnotation.id}');

    // 1. Get the Hive ID from the linker
    final hiveId = annotationIdLinker.getHiveIdForMapId(mapAnnotation.id);
    logger.i('Hive ID from annotationIdLinker: $hiveId');

    if (hiveId == null) {
      logger.w('No hive ID found for this annotation.');
      return;
    }

    // 2. Load from Hive
    final allHiveAnnotations = await localRepo.getAnnotations();
    logger.i('Total annotations retrieved from Hive: ${allHiveAnnotations.length}');

    final ann = allHiveAnnotations.firstWhere(
      (a) => a.id == hiveId,
      orElse: () {
        logger.w('Annotation with hiveId: $hiveId not found in the list.');
        return Annotation(id: 'notFound');
      },
    );

    if (ann.id == 'notFound') {
      logger.w('Annotation not found in Hive.');
      return;
    } else {
      logger.i('Found annotation in Hive: $ann');
    }

    // 3. Show the "second" dialog (form dialog) with existing data
    final title = ann.title ?? '';
    final iconName = ann.iconName ?? 'cross'; // fallback icon name
    final startDate = ann.startDate ?? '';
    final endDate = ann.endDate ?? '';
    final note = ann.note ?? '';

    // For your chosenIcon, you can map iconName → IconData if desired.
    // Here, we just pass Icons.star arbitrarily:
    final IconData chosenIcon = Icons.star; 

    final result = await showAnnotationFormDialog(
      context,
      title: title,
      chosenIcon: chosenIcon,
      chosenIconName: iconName,
      date: startDate,
      endDate: endDate,
      note: note,
    );

    if (result != null) {
      // ----------------------------------------------------------------
      // Handle "CHANGE" action (i.e., user wants to go back to the first dialog)
      // ----------------------------------------------------------------
      if (result['action'] == 'change') {
        logger.i('User pressed "Change" in the form dialog.');
        
        // The second dialog is returning the data it just showed
        final oldTitle = result['title'] ?? '';
        final oldIcon = result['icon'] ?? 'cross';
        final oldDate = result['date'] ?? '';
        final oldEndDate = result['endDate'] ?? '';

        // Re-open the FIRST dialog (annotation_initialization_dialog)
        final secondInitResult = await showAnnotationInitializationDialog(
          context,
          initialTitle: oldTitle,
          initialIconName: oldIcon,
          initialDate: oldDate,
          initialEndDate: oldEndDate,
        );

        if (secondInitResult != null) {
          // If user doesn't cancel, we get new data from the first dialog
          final newTitle     = secondInitResult['title']     as String?;
          final newIconName  = secondInitResult['icon']      as String? ?? 'cross';
          final newStartDate = secondInitResult['date']      as String?;
          final newEndDate   = secondInitResult['endDate']   as String?;
          final bool quickSave = (secondInitResult['quickSave'] == true);

          if (quickSave) {
            // Quick-save path → Just update your annotation with these new fields
            logger.i('User chose QuickSave after pressing "Change" during edit.');

            final updatedAnnotation = Annotation(
              id: ann.id,
              title: (newTitle?.isNotEmpty == true) ? newTitle : null,
              iconName: newIconName.isNotEmpty ? newIconName : null,
              startDate: (newStartDate?.isNotEmpty == true) ? newStartDate : null,
              endDate:   (newEndDate?.isNotEmpty == true)   ? newEndDate   : null,
              note: ann.note, // keep old note
              latitude: ann.latitude ?? 0.0,
              longitude: ann.longitude ?? 0.0,
              imagePath: ann.imagePath,
            );

            // Update in Hive
            await _updateAnnotationVisuallyAndInHive(
              updatedAnnotation,
              mapAnnotation,
            );
          } else {
            // If user pressed "Continue" in the first dialog (the newTitle, newIcon, etc. are updated),
            // then we re-show the "second" dialog (form) *again* with those updated fields.
            logger.i('User pressed "Continue" from the first dialog after "Change." Re-showing the form dialog.');

            final secondFormResult = await showAnnotationFormDialog(
              context,
              title: newTitle ?? '',
              chosenIcon: Icons.star,
              chosenIconName: newIconName,
              date: newStartDate ?? '',
              endDate: newEndDate ?? '',
              note: ann.note ?? '', // carry forward the old note, or use empty
            );

            if (secondFormResult != null) {
              if (secondFormResult['action'] == 'change') {
                // The user could theoretically press "Change" again.
                // You could handle it recursively or just ignore to keep it simpler.
                logger.i('User pressed CHANGE again — you could handle a nested loop here if desired.');
              } else {
                // They clicked SAVE:
                final updatedNote = secondFormResult['note'] ?? '';
                final updatedImagePath = secondFormResult['imagePath'] ?? '';

                final updatedAnnotation = Annotation(
                  id: ann.id,
                  title: (newTitle?.isNotEmpty == true) ? newTitle : null,
                  iconName: newIconName.isNotEmpty ? newIconName : null,
                  startDate: (newStartDate?.isNotEmpty == true) ? newStartDate : null,
                  endDate:   (newEndDate?.isNotEmpty == true)   ? newEndDate   : null,
                  note: updatedNote.isNotEmpty ? updatedNote : null,
                  latitude: ann.latitude ?? 0.0,
                  longitude: ann.longitude ?? 0.0,
                  imagePath: updatedImagePath.isNotEmpty
                      ? updatedImagePath
                      : ann.imagePath,
                );

                // Update in Hive + visually
                await _updateAnnotationVisuallyAndInHive(
                  updatedAnnotation,
                  mapAnnotation,
                );
              }
            } else {
              logger.i('User cancelled the second form after "Continue."');
            }
          }
        } else {
          logger.i('User cancelled after pressing "Change" — no updates.');
        }

      } 
      // ----------------------------------------------------------------
      // Handle normal "SAVE" action (i.e., user didn’t press "Change")
      // ----------------------------------------------------------------
      else {
        logger.i('User pressed SAVE in the form dialog (edit mode).');
        final updatedNote       = result['note'] ?? '';
        final updatedImagePath  = result['imagePath'] ?? '';
        // filePath if you use it, etc.

        // Create an updated annotation with the new fields
        final updatedAnnotation = Annotation(
          id: ann.id,
          title: title.isNotEmpty ? title : null,
          iconName: iconName.isNotEmpty ? iconName : null,
          startDate: startDate.isNotEmpty ? startDate : null,
          endDate: endDate.isNotEmpty ? endDate : null,
          note: updatedNote.isNotEmpty ? updatedNote : null,
          latitude: ann.latitude ?? 0.0,
          longitude: ann.longitude ?? 0.0,
          imagePath: updatedImagePath.isNotEmpty
              ? updatedImagePath
              : ann.imagePath,
        );

        // Actually update in Hive & re-draw on map
        await _updateAnnotationVisuallyAndInHive(updatedAnnotation, mapAnnotation);
      }
    } else {
      // The user pressed Cancel on the second dialog
      logger.i('User cancelled edit.');
    }
  }

  /// Helper method to remove the old map annotation, update in Hive, and
  /// then add + link the new annotation visually.
  Future<void> _updateAnnotationVisuallyAndInHive(
    Annotation updatedAnnotation,
    PointAnnotation oldMapAnnotation,
  ) async {
    // Update in Hive
    await localRepo.updateAnnotation(updatedAnnotation);
    logger.i('Annotation updated in Hive with id: ${updatedAnnotation.id}');

    // Remove old annotation visually
    await annotationsManager.removeAnnotation(oldMapAnnotation);

    // Load icon bytes
    final iconNameSafe = updatedAnnotation.iconName ?? 'cross';
    final iconBytes = await rootBundle.load('assets/icons/$iconNameSafe.png');
    final imageData = iconBytes.buffer.asUint8List();

    // Create a new map annotation
    final newMapAnnotation = await annotationsManager.addAnnotation(
      Point(coordinates: Position(
        updatedAnnotation.longitude ?? 0.0,
        updatedAnnotation.latitude ?? 0.0,
      )),
      image: imageData,
      title: updatedAnnotation.title ?? '',
      date: updatedAnnotation.startDate ?? '',
    );

    // Re-link the updated annotation
    annotationIdLinker.registerAnnotationId(
      newMapAnnotation.id,
      updatedAnnotation.id,
    );

    logger.i('Annotation visually updated on map with new data.');
  }
}