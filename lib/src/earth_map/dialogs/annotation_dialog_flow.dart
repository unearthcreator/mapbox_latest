import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart'; // for BuildContext, etc.
import 'package:flutter/services.dart'; // for rootBundle
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:map_mvp_project/models/annotation.dart';
import 'package:map_mvp_project/repositories/local_annotations_repository.dart';
import 'package:map_mvp_project/services/error_handler.dart';
import 'package:map_mvp_project/src/earth_map/annotations/map_annotations_manager.dart';
import 'package:map_mvp_project/src/earth_map/dialogs/annotation_initialization_dialog.dart';
import 'package:map_mvp_project/src/earth_map/dialogs/annotation_form_dialog.dart';
import 'package:map_mvp_project/src/earth_map/annotations/annotation_id_linker.dart';

/// Handles the "placement dialog" flow (initial + final forms).
class PlacementDialogFlow {
  // We keep a reference to any active timer, so we can cancel or manage it.
  Timer? _placementDialogTimer;

  // ---------------------- State Variables ----------------------
  String? _chosenTitle;
  String? _chosenStartDate;
  String? _chosenEndDate;
  String _chosenIconName = "mapbox-check";

  // Short address (for display in the dialog + on the map)
  String? _chosenShortAddress;
  // (Optional) Full address stored in Hive if you want
  String? _chosenFullAddress;

  final uuid = Uuid();

  /// Start the placement dialog flow by waiting 400ms, then showing the initial form.
  Timer startPlacementDialogTimer({
    required Point pressPoint,
    required BuildContext context,
    required MapAnnotationsManager annotationsManager,
    required LocalAnnotationsRepository localAnnotationsRepository,
    required AnnotationIdLinker annotationIdLinker,
    String? initialShortAddress,  // short address
    String? initialFullAddress,   // full address
  }) {
    _placementDialogTimer?.cancel();
    logger.i('PlacementDialogFlow: Timer started for annotation at $pressPoint');

    _placementDialogTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        logger.i('PlacementDialogFlow: showing initial form dialog now.');

        // Possibly pass the short & full addresses to initialization dialog
        final initialData = await showAnnotationInitializationDialog(
          context,
          initialAddress: initialShortAddress,
          // initialFullAddress: initialFullAddress, // if your dialog supports it
        );

        logger.i('PlacementDialogFlow: initial form returned => $initialData');

        if (initialData != null) {
          // If your dialog returns 'address' rather than 'shortAddress',
          // switch to: _chosenShortAddress = initialData['address'] as String?;
          _chosenTitle        = initialData['title'] as String?;
          _chosenShortAddress = initialData['shortAddress'] as String?;
          _chosenIconName     = initialData['icon'] as String;
          _chosenStartDate    = initialData['date'] as String?;
          _chosenEndDate      = initialData['endDate'] as String?;
          final bool quickSave = (initialData['quickSave'] == true);

          // If your dialog also returns "fullAddress", store it
          // _chosenFullAddress = initialData['fullAddress'] as String?;

          logger.i(
            'PlacementDialogFlow: form => '
            'title=$_chosenTitle, shortAddress=$_chosenShortAddress, '
            'icon=$_chosenIconName, startDate=$_chosenStartDate, '
            'endDate=$_chosenEndDate, quickSave=$quickSave.'
          );

          if (quickSave) {
            await _quickSaveAnnotation(
              context: context,
              pressPoint: pressPoint,
              annotationsManager: annotationsManager,
              localAnnotationsRepository: localAnnotationsRepository,
              annotationIdLinker: annotationIdLinker,
            );
          } else {
            await _startFormDialogFlow(
              context: context,
              pressPoint: pressPoint,
              annotationsManager: annotationsManager,
              localAnnotationsRepository: localAnnotationsRepository,
              annotationIdLinker: annotationIdLinker,
            );
          }
        } else {
          logger.i('PlacementDialogFlow: user closed initial form => no annotation added.');
        }
      } catch (e, stackTrace) {
        logger.e('PlacementDialogFlow: error in timer: $e', error: e, stackTrace: stackTrace);
      }
    });

    return _placementDialogTimer!;
  }

  // ----------------------------------------------------------------------
  // QUICK-SAVE
  // ----------------------------------------------------------------------
  Future<void> _quickSaveAnnotation({
    required BuildContext context,
    required Point pressPoint,
    required MapAnnotationsManager annotationsManager,
    required LocalAnnotationsRepository localAnnotationsRepository,
    required AnnotationIdLinker annotationIdLinker,
  }) async {
    logger.i('PlacementDialogFlow: _quickSaveAnnotation => pressPoint=${pressPoint.coordinates}');
    logger.i('PlacementDialogFlow: _quickSaveAnnotation => shortAddress=$_chosenShortAddress');

    // Load chosen icon
    final bytes = await rootBundle.load('assets/icons/$_chosenIconName.png');
    final imageData = bytes.buffer.asUint8List();

    // Create multi-part annotation (title, shortAddress, date)
    logger.i('PlacementDialogFlow: calling addMultiPartAnnotation with: '
      'title=$_chosenTitle, shortAddress=$_chosenShortAddress, date=$_chosenStartDate');
    final multiGroup = await annotationsManager.addMultiPartAnnotation(
      mapPoint: pressPoint,
      iconBytes: imageData,
      title: _chosenTitle,
      shortAddress: _chosenShortAddress,
      date: _chosenStartDate,
    );
    logger.i('PlacementDialogFlow: multi-part annotation => iconID=${multiGroup.iconAnnotation.id}');

    // Save to Hive
    final id = uuid.v4();
    final latitude = pressPoint.coordinates.lat.toDouble();
    final longitude = pressPoint.coordinates.lng.toDouble();

    final annotation = Annotation(
      id: id,
      title: _chosenTitle?.isNotEmpty == true ? _chosenTitle : null,
      iconName: _chosenIconName.isNotEmpty ? _chosenIconName : null,
      startDate: _chosenStartDate?.isNotEmpty == true ? _chosenStartDate : null,
      endDate: _chosenEndDate?.isNotEmpty == true ? _chosenEndDate : null,
      latitude: latitude,
      longitude: longitude,
      note: null,
      imagePath: null,

      // If your model has shortAddress & fullAddress fields
      shortAddress: _chosenShortAddress,
      fullAddress: _chosenFullAddress,
    );

    await localAnnotationsRepository.addAnnotation(annotation);
    logger.i('PlacementDialogFlow: Annotation saved to Hive => ID=$id');

    // Link icon annotation → Hive ID
    annotationIdLinker.registerAnnotationId(multiGroup.iconAnnotation.id, id);
    logger.i('PlacementDialogFlow: Linked iconID=${multiGroup.iconAnnotation.id} to hiveUUID=$id');
  }

  // ----------------------------------------------------------------------
  // FULL FORM FLOW
  // ----------------------------------------------------------------------
  Future<void> _startFormDialogFlow({
    required BuildContext context,
    required Point pressPoint,
    required MapAnnotationsManager annotationsManager,
    required LocalAnnotationsRepository localAnnotationsRepository,
    required AnnotationIdLinker annotationIdLinker,
  }) async {
    logger.i('PlacementDialogFlow: showing annotation form dialog...');
    final result = await showAnnotationFormDialog(
      context,
      title: _chosenTitle ?? '',
      chosenIcon: Icons.star,
      chosenIconName: _chosenIconName,
      date: _chosenStartDate ?? '',
      endDate: _chosenEndDate ?? '',
    );
    logger.i('PlacementDialogFlow: annotation form returned => $result');

    if (result != null) {
      if (result['action'] == 'change') {
        logger.i('PlacementDialogFlow: user pressed "Change" => re-edit initial fields');
        final changedTitle     = result['title'] ?? '';
        final changedIcon      = result['icon'] ?? 'cross';
        final changedStartDate = result['date'] ?? '';
        final changedEndDate   = result['endDate'] ?? '';

        final secondInitResult = await showAnnotationInitializationDialog(
          context,
          initialTitle: changedTitle,
          initialIconName: changedIcon,
          initialDate: changedStartDate,
          initialEndDate: changedEndDate,
          initialAddress: _chosenShortAddress,
        );

        logger.i('PlacementDialogFlow: second init => $secondInitResult');
        if (secondInitResult != null) {
          _chosenTitle        = secondInitResult['title'] as String?;
          _chosenIconName     = secondInitResult['icon'] as String;
          _chosenStartDate    = secondInitResult['date'] as String?;
          _chosenEndDate      = secondInitResult['endDate'] as String?;
          _chosenShortAddress = secondInitResult['shortAddress'] as String?;
          // _chosenFullAddress = secondInitResult['fullAddress'] as String?;

          final bool newQuickSave = (secondInitResult['quickSave'] == true);
          if (newQuickSave) {
            logger.i('PlacementDialogFlow: user requested quickSave after second init');
            await _quickSaveAnnotation(
              context: context,
              pressPoint: pressPoint,
              annotationsManager: annotationsManager,
              localAnnotationsRepository: localAnnotationsRepository,
              annotationIdLinker: annotationIdLinker,
            );
          } else {
            logger.i('PlacementDialogFlow: showing final form again (no quicksave).');
            await _startFormDialogFlow(
              context: context,
              pressPoint: pressPoint,
              annotationsManager: annotationsManager,
              localAnnotationsRepository: localAnnotationsRepository,
              annotationIdLinker: annotationIdLinker,
            );
          }
        } else {
          logger.i('PlacementDialogFlow: user canceled after "change" => no annotation added');
        }

      } else {
        // =========== FINAL SAVE ===========
        logger.i('PlacementDialogFlow: user pressed "Save" or final action');

        final note     = result['note'] ?? '';
        final imagePath = result['imagePath'];
        final endDate  = result['endDate'] ?? '';

        logger.i('PlacementDialogFlow: final form => note=$note, imagePath=$imagePath');

        final bytes = await rootBundle.load('assets/icons/$_chosenIconName.png');
        final imageData = bytes.buffer.asUint8List();

        // Log short address before we call the manager
        logger.i('PlacementDialogFlow: final save => shortAddress=$_chosenShortAddress');

        final multiGroup = await annotationsManager.addMultiPartAnnotation(
          mapPoint: pressPoint,
          iconBytes: imageData,
          title: _chosenTitle,
          shortAddress: _chosenShortAddress,
          date: _chosenStartDate,
        );
        logger.i('PlacementDialogFlow: multi-part annotation => iconID=${multiGroup.iconAnnotation.id}');

        final id = uuid.v4();
        final latitude = pressPoint.coordinates.lat.toDouble();
        final longitude = pressPoint.coordinates.lng.toDouble();

        // Build the model
        final annotation = Annotation(
          id: id,
          title: _chosenTitle?.isNotEmpty == true ? _chosenTitle : null,
          iconName: _chosenIconName.isNotEmpty ? _chosenIconName : null,
          startDate: _chosenStartDate?.isNotEmpty == true ? _chosenStartDate : null,
          endDate: endDate.isNotEmpty ? endDate : null,
          note: note.isNotEmpty ? note : null,
          latitude: latitude,
          longitude: longitude,
          imagePath: (imagePath != null && imagePath.isNotEmpty) ? imagePath : null,

          shortAddress: _chosenShortAddress,
          fullAddress: _chosenFullAddress,
        );

        await localAnnotationsRepository.addAnnotation(annotation);
        logger.i('PlacementDialogFlow: annotation saved => ID=$id');

        // Link icon ID → Hive ID
        annotationIdLinker.registerAnnotationId(multiGroup.iconAnnotation.id, id);
        logger.i('PlacementDialogFlow: Linked iconID=${multiGroup.iconAnnotation.id} with hiveUUID=$id');
      }
    } else {
      logger.i('PlacementDialogFlow: user cancelled final form => no annotation added.');
    }
  }

  /// Cancel timers if needed
  void cancelTimer() {
    logger.i('PlacementDialogFlow: cancelTimer() => cleaning up timers');
    _placementDialogTimer?.cancel();
    _placementDialogTimer = null;
  }
}