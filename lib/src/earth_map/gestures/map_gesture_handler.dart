import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for rootBundle
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:map_mvp_project/services/error_handler.dart';
import 'package:map_mvp_project/src/earth_map/annotations/map_annotations_manager.dart';
import 'package:map_mvp_project/src/earth_map/dialogs/show_annotation_details_dialog.dart';
import 'package:uuid/uuid.dart'; // for unique IDs
import 'package:map_mvp_project/models/annotation.dart'; // Your Annotation model
import 'package:map_mvp_project/repositories/local_annotations_repository.dart'; // Your local repo
import 'package:map_mvp_project/src/earth_map/annotations/annotation_id_linker.dart';
import 'package:map_mvp_project/src/earth_map/utils/trash_can_handler.dart';

/// Fires when user long-presses on an existing annotation.
typedef AnnotationLongPressCallback = void Function(
  PointAnnotation annotation,
  Point annotationPosition,
);

/// Fires when user drags an annotation.
typedef AnnotationDragUpdateCallback = void Function(PointAnnotation annotation);

/// Fires when user finishes dragging (mouse/finger up).
typedef DragEndCallback = void Function();

/// Fires when an annotation is removed (deleted).
typedef AnnotationRemovedCallback = void Function();

/// New callback: fires when user long-presses an *empty* spot on the map
/// and we want the page to handle "placement" dialogs.
typedef PlacementDialogRequestedCallback = void Function(Point pressPoint);

/// A helper class to handle annotation clicks.
class MyPointAnnotationClickListener extends OnPointAnnotationClickListener {
  final void Function(PointAnnotation) onClick;

  MyPointAnnotationClickListener(this.onClick);

  @override
  bool onPointAnnotationClick(PointAnnotation annotation) {
    onClick(annotation);
    return true; // event handled
  }
}

/// Handles gestures on the map: long-presses, dragging, connect mode, etc.
class MapGestureHandler {
  final MapboxMap mapboxMap;
  final MapAnnotationsManager annotationsManager;
  final BuildContext context;
  final LocalAnnotationsRepository localAnnotationsRepository;
  final AnnotationIdLinker annotationIdLinker;

  final AnnotationLongPressCallback? onAnnotationLongPress;
  final AnnotationDragUpdateCallback? onAnnotationDragUpdate;
  final DragEndCallback? onDragEnd;
  final AnnotationRemovedCallback? onAnnotationRemoved;
  final VoidCallback? onConnectModeDisabled;

  /// Callback for requesting a placement dialog from outside (e.g. new annotation).
  final PlacementDialogRequestedCallback? onPlacementDialogRequested;

  /// Fires when user cancels relocation or removal and we revert the annotation.
  final ValueChanged<PointAnnotation>? onAnnotationReverted;

  // Internal state
  Timer? _longPressTimer;
  Point? _longPressPoint;
  bool _isOnExistingAnnotation = false;

  /// The last annotation the user long-pressed on (to open the menu).
  PointAnnotation? _selectedAnnotation;

  /// The one annotation currently in "move" mode (if any).
  PointAnnotation? _movingAnnotation;

  bool _isDragging = false;
  bool _isProcessingDrag = false;
  ScreenCoordinate? _lastDragScreenPoint;
  Point? _originalPoint; // Original coords to revert to, if needed

  // Connect mode
  bool _isConnectMode = false;
  PointAnnotation? _firstConnectAnnotation;

  final TrashCanHandler _trashCanHandler;
  final uuid = Uuid();

  MapGestureHandler({
    required this.mapboxMap,
    required this.annotationsManager,
    required this.context,
    required this.localAnnotationsRepository,
    required this.annotationIdLinker,
    this.onAnnotationLongPress,
    this.onAnnotationDragUpdate,
    this.onDragEnd,
    this.onAnnotationRemoved,
    this.onConnectModeDisabled,
    this.onPlacementDialogRequested,
    this.onAnnotationReverted,
  }) : _trashCanHandler = TrashCanHandler(context: context) {
    // Listen for user taps on annotations
    annotationsManager.pointAnnotationManager.addOnPointAnnotationClickListener(
      MyPointAnnotationClickListener(_onAnnotationTapped),
    );
  }

  // ------------------------------------------------------------------
  //   CONNECT MODE
  // ------------------------------------------------------------------
  void enableConnectMode(PointAnnotation firstAnnotation) {
    logger.i('Connect mode enabled with first annotation: ${firstAnnotation.id}');
    _isConnectMode = true;
    _firstConnectAnnotation = firstAnnotation;
  }

  void disableConnectMode() {
    logger.i('Connect mode disabled.');
    _isConnectMode = false;
    _firstConnectAnnotation = null;
    onConnectModeDisabled?.call();
  }

  Future<void> _handleConnectModeClick(PointAnnotation clickedAnnotation) async {
    if (_firstConnectAnnotation == null) {
      logger.w('First connect annotation was null, but connect mode was enabled!');
      _firstConnectAnnotation = clickedAnnotation;
      logger.i('First annotation chosen for connection (fallback): ${clickedAnnotation.id}');
    } else {
      // We have a first annotation; now this is the second
      logger.i('Second annotation chosen for connection: ${clickedAnnotation.id}');
      // (Implement line drawing or other logic if needed)
      disableConnectMode();
    }
  }

  // ------------------------------------------------------------------
  //   ANNOTATION TAPS
  // ------------------------------------------------------------------
  void _onAnnotationTapped(PointAnnotation clickedAnnotation) {
    logger.i('Annotation tapped: ${clickedAnnotation.id}');

    // If we are in connect mode, handle that
    if (_isConnectMode) {
      _handleConnectModeClick(clickedAnnotation);
      return;
    }

    // If we are moving a different annotation, ignore all other annotation taps
    if (_movingAnnotation != null && _movingAnnotation != clickedAnnotation) {
      logger.i('Ignoring tap on another annotation while moving $_movingAnnotation');
      return;
    }

    // Normal mode: show annotation details
    final hiveId = annotationIdLinker.getHiveIdForMapId(clickedAnnotation.id);
    if (hiveId != null) {
      _showAnnotationDetailsById(hiveId);
    } else {
      logger.w('No recorded Hive id for tapped annotation ${clickedAnnotation.id}');
    }
  }

  // ------------------------------------------------------------------
  //   LONG-PRESS GESTURE
  // ------------------------------------------------------------------
  Future<void> handleLongPressGesture(ScreenCoordinate screenPoint) async {
    // If we are already moving an annotation, do not allow selecting or creating others
    if (_movingAnnotation != null) {
      logger.i('Currently moving $_movingAnnotation; ignoring new long-press');
      return;
    }

    try {
      final features = await mapboxMap.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenPoint),
        RenderedQueryOptions(layerIds: [annotationsManager.annotationLayerId]),
      );

      logger.i('Features found: ${features.length}');
      final pressPoint = await mapboxMap.coordinateForPixel(screenPoint);
      if (pressPoint == null) {
        logger.w('Could not convert screen coordinate to map coordinate');
        return;
      }

      _longPressPoint = pressPoint;
      _isOnExistingAnnotation = features.isNotEmpty;

      if (!_isOnExistingAnnotation) {
        // No existing annotation -> request new annotation creation
        logger.i('No annotation at long-press => show placement dialog');
        onPlacementDialogRequested?.call(pressPoint);
      } else {
        logger.i('Long press on existing annotation => show annotation menu');
        _selectedAnnotation = await annotationsManager.findNearestAnnotation(pressPoint);
        if (_selectedAnnotation != null) {
          // Store original point in case we want to revert
          _storeOriginalPoint(_selectedAnnotation!);
          onAnnotationLongPress?.call(_selectedAnnotation!, _originalPoint!);
        } else {
          logger.w('No annotation found on long-press.');
        }
      }
    } catch (e) {
      logger.e('Error during feature query: $e');
    }
  }

  void _storeOriginalPoint(PointAnnotation annotation) {
    try {
      _originalPoint = Point.fromJson({
        'type': 'Point',
        'coordinates': [
          annotation.geometry.coordinates[0],
          annotation.geometry.coordinates[1],
        ],
      });
      logger.i('Original point stored: ${_originalPoint?.coordinates} '
          'for annotation ${annotation.id}');
    } catch (e) {
      logger.e('Error storing original point: $e');
    }
  }

  // ------------------------------------------------------------------
  //   DRAG HANDLING
  // ------------------------------------------------------------------
  Future<void> handleDrag(ScreenCoordinate screenPoint) async {
    // Only allow dragging if we are in move mode, we have a selected annotation, and not busy
    if (!_isDragging || _movingAnnotation == null || _isProcessingDrag) return;

    try {
      _isProcessingDrag = true;
      _lastDragScreenPoint = screenPoint;

      final newPoint = await mapboxMap.coordinateForPixel(screenPoint);
      if (!_isDragging || _movingAnnotation == null) return;
      if (newPoint != null) {
        logger.i('Updating annotation ${_movingAnnotation!.id} position to $newPoint');
        await annotationsManager.updateVisualPosition(_movingAnnotation!, newPoint);
        onAnnotationDragUpdate?.call(_movingAnnotation!);
      }
    } catch (e) {
      logger.e('Error during drag: $e');
    } finally {
      _isProcessingDrag = false;
    }
  }

  /// Called when user lifts finger after dragging
  Future<void> endDrag() async {
    logger.i('Ending drag.');
    logger.i('Original point at end drag: ${_originalPoint?.coordinates}');
    final annotationToRemove = _movingAnnotation;

    if (annotationToRemove == null) {
      logger.i('No annotation in move mode. Doing nothing.');
      onDragEnd?.call();
      return;
    }

    // If user drops the annotation over trash can => confirm removal or revert
    if (_lastDragScreenPoint != null &&
        _trashCanHandler.isOverTrashCan(_lastDragScreenPoint!)) {
      logger.i('Annotation ${annotationToRemove.id} dropped over trash can => confirm removal');
      final shouldRemove = await _showRemoveConfirmationDialog();
      if (shouldRemove == true) {
        logger.i('User confirmed removal – removing annotation ${annotationToRemove.id}.');
        await annotationsManager.removeAnnotation(annotationToRemove);
        onAnnotationRemoved?.call();
      } else {
        logger.i('User cancelled removal => revert annotation to original position');
        if (_originalPoint != null) {
          logger.i('Reverting annotation ${annotationToRemove.id} to ${_originalPoint?.coordinates}');
          await annotationsManager.updateVisualPosition(annotationToRemove, _originalPoint!);
        }
        onAnnotationReverted?.call(annotationToRemove);
      }
    }

    onDragEnd?.call();
  }

  // ------------------------------------------------------------------
  //   REMOVE / MOVE CONFIRMATION
  // ------------------------------------------------------------------
  Future<bool?> _showRemoveConfirmationDialog() async {
    logger.i('Showing remove confirmation dialog.');
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Remove Annotation'),
          content: const Text('Do you want to remove this annotation?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () {
                logger.i('User selected NO in remove dialog.');
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () {
                logger.i('User selected YES in remove dialog.');
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showConfirmMoveDialog() async {
    logger.i('Showing move confirmation dialog.');
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Move Annotation?'),
          content: const Text('Do you want to move this annotation to the new location?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------
  //   SHOW ANNOTATION DETAILS
  // ------------------------------------------------------------------
  Future<void> _showAnnotationDetailsById(String hiveId) async {
    final allAnnotations = await localAnnotationsRepository.getAnnotations();
    final ann = allAnnotations.firstWhere((a) => a.id == hiveId, orElse: () => Annotation(id: 'notFound'));
    if (ann.id != 'notFound') {
      showAnnotationDetailsDialog(context, ann);
    } else {
      logger.w('No matching Hive annotation found for id: $hiveId');
    }
  }

  // ------------------------------------------------------------------
  //   SAVE COORDS TO HIVE
  // ------------------------------------------------------------------
  Future<void> _saveNewCoordinatesToHive(PointAnnotation annotation) async {
    final hiveId = annotationIdLinker.getHiveIdForMapId(annotation.id);
    if (hiveId == null) {
      logger.w('No Hive ID found for annotation ${annotation.id}');
      return;
    }

    final double newLng = (annotation.geometry.coordinates[0] ?? 0.0).toDouble();
    final double newLat = (annotation.geometry.coordinates[1] ?? 0.0).toDouble();

    await _logHiveDataForAnnotation(hiveId, 'Before update');

    final all = await localAnnotationsRepository.getAnnotations();
    final idx = all.indexWhere((a) => a.id == hiveId);
    if (idx < 0) {
      logger.w('Hive annotation not found for id=$hiveId');
      return;
    }

    final oldAnn = all[idx];
    final updatedAnn = Annotation(
      id: oldAnn.id,
      title: oldAnn.title,
      iconName: oldAnn.iconName,
      startDate: oldAnn.startDate,
      endDate: oldAnn.endDate,
      note: oldAnn.note,
      latitude: newLat,
      longitude: newLng,
      imagePath: oldAnn.imagePath,
    );

    await localAnnotationsRepository.updateAnnotation(updatedAnn);
    logger.i('Annotation $hiveId updated in Hive => lat=$newLat, lng=$newLng');

    await _logHiveDataForAnnotation(hiveId, 'After update');
  }

  Future<void> _logHiveDataForAnnotation(String hiveId, String label) async {
    final all = await localAnnotationsRepository.getAnnotations();
    final found = all.firstWhere((a) => a.id == hiveId, orElse: () => Annotation(id: 'notFound'));
    if (found.id == 'notFound') {
      logger.i('$label => No matching annotation for $hiveId');
    } else {
      logger.i('$label => Annotation ID=$hiveId '
          'lat=${found.latitude}, lng=${found.longitude}, '
          'title=${found.title}');
    }
  }

  // ------------------------------------------------------------------
  //   CANCEL TIMERS / RESET
  // ------------------------------------------------------------------
  void cancelTimer() {
    logger.i('Cancelling timers and resetting state.');
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressPoint = null;
    _selectedAnnotation = null;
    _isOnExistingAnnotation = false;
    _isDragging = false;
    _isProcessingDrag = false;
    _originalPoint = null;
    _firstConnectAnnotation = null;
    _movingAnnotation = null;
  }

  // ------------------------------------------------------------------
  //   DRAG MODE: MOVE / LOCK
  // ------------------------------------------------------------------
  /// Called when user presses "Move" in the annotation menu.
  /// We mark the currently selected annotation as the one to move.
  Future<void> startDraggingSelectedAnnotation() async {
    if (_selectedAnnotation == null) {
      logger.i('startDraggingSelectedAnnotation called, but no _selectedAnnotation');
      return;
    }
    logger.i('User chose to move annotation ${_selectedAnnotation!.id}.');
    _movingAnnotation = _selectedAnnotation; 
    _isDragging = true;
    _isProcessingDrag = false;
    _trashCanHandler.showTrashCan();

    // Print out data from Hive for debugging
    final hiveId = annotationIdLinker.getHiveIdForMapId(_selectedAnnotation!.id);
    if (hiveId != null) {
      await _logHiveDataForAnnotation(hiveId, 'startDragging => Hive data');
    }
  }

  /// Called when user presses "Lock" in the annotation menu.
  /// We hide the trash can, confirm if the user wants to keep the new coords,
  /// or revert them. Then we reset `_movingAnnotation` to allow normal interaction.
  Future<void> hideTrashCanAndStopDragging() async {
    logger.i('Locking annotation in place and hiding trash can.');
    _isDragging = false;
    _isProcessingDrag = false;
    _trashCanHandler.hideTrashCan();

    // If we have an annotation & original coords => check if moved
    if (_movingAnnotation != null && _originalPoint != null) {
      final double oldLng = (_originalPoint!.coordinates[0] ?? 0.0).toDouble();
      final double oldLat = (_originalPoint!.coordinates[1] ?? 0.0).toDouble();

      final double newLng = (_movingAnnotation!.geometry.coordinates[0] ?? 0.0).toDouble();
      final double newLat = (_movingAnnotation!.geometry.coordinates[1] ?? 0.0).toDouble();

      const epsilon = 0.000001;
      final hasMoved =
          (newLng - oldLng).abs() > epsilon ||
          (newLat - oldLat).abs() > epsilon;

      if (hasMoved) {
        logger.i('Annotation has moved => ask user to confirm move');
        final userConfirmed = await _showConfirmMoveDialog();
        if (userConfirmed == true) {
          logger.i('User confirmed => saving new coords to Hive');
          await _saveNewCoordinatesToHive(_movingAnnotation!);
        } else {
          logger.i('User cancelled => revert annotation');
          await annotationsManager.updateVisualPosition(_movingAnnotation!, _originalPoint!);
          onAnnotationReverted?.call(_movingAnnotation!);
        }
      } else {
        logger.i('Annotation not moved => no confirm needed');
      }
    }

    // End move mode so user can interact with other annotations again
    _movingAnnotation = null;
  }
}