import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for rootBundle
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

// ---------------------- External & Project Imports ----------------------
import 'package:map_mvp_project/repositories/local_annotations_repository.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show CameraChangedEventData;
import 'package:map_mvp_project/services/error_handler.dart';
import 'package:map_mvp_project/src/earth_map/annotations/map_annotations_manager.dart';
import 'package:map_mvp_project/src/earth_map/gestures/map_gesture_handler.dart';
import 'package:map_mvp_project/src/earth_map/utils/map_config.dart';
import 'package:uuid/uuid.dart'; // for unique IDs
import 'package:map_mvp_project/src/earth_map/timeline/timeline.dart';
import 'package:map_mvp_project/src/earth_map/annotations/annotation_id_linker.dart';
import 'package:map_mvp_project/models/world_config.dart';
import 'package:map_mvp_project/src/earth_map/search/search_widget.dart';
import 'package:map_mvp_project/src/earth_map/misc/test_utils.dart';
import 'package:map_mvp_project/src/earth_map/utils/connect_banner.dart';
import 'package:map_mvp_project/src/earth_map/annotations/annotation_menu.dart';
import 'package:map_mvp_project/src/earth_map/dialogs/annotation_dialog_flow.dart';
import 'package:map_mvp_project/src/earth_map/annotations/annotation_actions.dart';
import 'package:map_mvp_project/services/geocoding_service.dart'; // for fetchShortAddress

/// The main EarthMapPage, which sets up the map, annotations, and various UI widgets.
class EarthMapPage extends StatefulWidget {
  final WorldConfig worldConfig;

  const EarthMapPage({Key? key, required this.worldConfig}) : super(key: key);

  @override
  EarthMapPageState createState() => EarthMapPageState();
}

class EarthMapPageState extends State<EarthMapPage> {
  // ---------------------- Map-Related Variables ----------------------
  late MapboxMap _mapboxMap;
  late MapAnnotationsManager _annotationsManager;
  late MapGestureHandler _gestureHandler;
  late LocalAnnotationsRepository _localRepo;
  bool _isMapReady = false;

  // ---------------------- Timeline / Canvas UI ----------------------
  List<String> _hiveUuidsForTimeline = [];
  bool _showTimelineCanvas = false;

  // ---------------------- Annotation Menu Variables ----------------------
  bool _showAnnotationMenu = false;
  PointAnnotation? _annotationMenuAnnotation;
  Offset _annotationMenuOffset = Offset.zero;

  // ---------------------- Dragging & Connect Mode ----------------------
  bool _isDragging = false;   // True if user clicked "Move"
  bool _isConnectMode = false;
  String get _annotationButtonText => _isDragging ? 'Lock' : 'Move';

  // ---------------------- "Relocate by address" hint ---------------------
  bool _showRelocateHint = false;

  // ---------------------- UUID Generator ----------------------
  final uuid = Uuid();

  // For edit etc.
  late AnnotationActions _annotationActions;

  @override
  void initState() {
    super.initState();
    logger.i('Initializing EarthMapPage');
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Helper function to determine the style URI based on user preferences.
  // For now, it logs the preferences and returns a default style URI.
  // Later, you can update it to choose a style based on mapType, timeMode, etc.
  String _determineGlobeStyleUri() {
    final config = widget.worldConfig;
    logger.i("User preferences - isFlatMap: ${config.isFlatMap}, mapType: ${config.mapType}, timeMode: ${config.timeMode}, manualTheme: ${config.manualTheme}");
    // For now, just return the default style URI for Earth (globe).
    return MapConfig.styleUriEarth;
  }

  // ---------------------------------------------------------------------
  //                       MAP CREATION / INIT
  // ---------------------------------------------------------------------
  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    try {
      logger.i('Starting map initialization');
      _mapboxMap = mapboxMap;

      // 1) Create the underlying Mapbox annotation manager
      final annotationManager = await mapboxMap.annotations
          .createPointAnnotationManager()
          .onError((error, stackTrace) {
        logger.e('Failed to create annotation manager', error: error, stackTrace: stackTrace);
        throw Exception('Failed to initialize map annotations');
      });

      // 2) Create LocalAnnotationsRepository
      _localRepo = LocalAnnotationsRepository();

      // 3) Create a single shared AnnotationIdLinker instance
      final annotationIdLinker = AnnotationIdLinker();

      // 4) Create our MapAnnotationsManager
      _annotationsManager = MapAnnotationsManager(
        annotationManager,
        annotationIdLinker: annotationIdLinker,
        localAnnotationsRepository: _localRepo,
      );

      // 5) Create the gesture handler
      _gestureHandler = MapGestureHandler(
        mapboxMap: _mapboxMap,
        annotationsManager: _annotationsManager,
        context: context,
        localAnnotationsRepository: _localRepo,
        annotationIdLinker: annotationIdLinker,
        onAnnotationLongPress: _handleAnnotationLongPress,
        onAnnotationDragUpdate: _handleAnnotationDragUpdate,
        onDragEnd: _handleDragEnd,
        onAnnotationRemoved: _handleAnnotationRemoved,
        onConnectModeDisabled: () => setState(() => _isConnectMode = false),

        // Called if user long-presses an empty spot
        onPlacementDialogRequested: _handlePlacementDialogRequest,

        // Called if user reverts the annotation
        onAnnotationReverted: _handleAnnotationReverted,
      );

      // 6) Initialize your AnnotationActions
      _annotationActions = AnnotationActions(
        localRepo: _localRepo,
        annotationsManager: _annotationsManager,
        annotationIdLinker: annotationIdLinker,
      );

      logger.i('Map initialization completed successfully');

      // Once map is ready, load saved Hive annotations
      if (mounted) {
        setState(() => _isMapReady = true);
        await _annotationsManager.loadAnnotationsFromHive();
      }
    } catch (e, stackTrace) {
      logger.e('Error during map initialization', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {});
      }
    }
  }

  // ---------------------------------------------------------------------
  //               CAMERA CHANGES -> MENU "STICKS"
  // ---------------------------------------------------------------------
  void _onCameraChangeListener(CameraChangedEventData data) {
    _updateMenuPositionIfNeeded();
  }

  Future<void> _updateMenuPositionIfNeeded() async {
    if (_annotationMenuAnnotation != null && _showAnnotationMenu) {
      final geo = _annotationMenuAnnotation!.geometry;
      final screenPos = await _mapboxMap.pixelForCoordinate(geo);
      setState(() {
        _annotationMenuOffset = Offset(screenPos.x + 30, screenPos.y - 40);
      });
    }
  }

  // ---------------------------------------------------------------------
  //            ANNOTATION / MENU REVERT HANDLING
  // ---------------------------------------------------------------------
  Future<void> _handleAnnotationReverted(PointAnnotation annotation) async {
    final screenPos = await _mapboxMap.pixelForCoordinate(annotation.geometry);
    setState(() {
      _annotationMenuAnnotation = annotation;
      _annotationMenuOffset = Offset(screenPos.x + 20, screenPos.y - 40);
      _showAnnotationMenu = true;
      _isDragging = false;
      _showRelocateHint = false;
    });
  }

  // ---------------------------------------------------------------------
  //               ANNOTATION UI & CALLBACKS
  // ---------------------------------------------------------------------
  void _handleAnnotationLongPress(PointAnnotation annotation, Point annotationPosition) async {
    final screenPos = await _mapboxMap.pixelForCoordinate(annotationPosition);
    setState(() {
      _annotationMenuAnnotation = annotation;
      _showAnnotationMenu = true;
      _annotationMenuOffset = Offset(screenPos.x + 20, screenPos.y - 40);
    });
  }

  void _handleAnnotationDragUpdate(PointAnnotation annotation) async {
    final screenPos = await _mapboxMap.pixelForCoordinate(annotation.geometry);
    setState(() {
      _annotationMenuAnnotation = annotation;
      _annotationMenuOffset = Offset(screenPos.x + 20, screenPos.y - 40);
    });
  }

  void _handleDragEnd() => logger.i('Drag ended');

  void _handleAnnotationRemoved() {
    setState(() {
      _showAnnotationMenu = false;
      _annotationMenuAnnotation = null;
      _isDragging = false;
    });
  }

  // ---------------------------------------------------------------------
  //                        GESTURE DETECTOR
  // ---------------------------------------------------------------------
  void _handleLongPress(LongPressStartDetails details) {
    try {
      logger.i('Long press started at: ${details.localPosition}');
      final screenPoint = ScreenCoordinate(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
      );
      _gestureHandler.handleLongPressGesture(screenPoint);
    } catch (e, stackTrace) {
      logger.e('Error handling long press', error: e, stackTrace: stackTrace);
    }
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    try {
      if (_isDragging) {
        final screenPoint = ScreenCoordinate(
          x: details.localPosition.dx,
          y: details.localPosition.dy,
        );
        _gestureHandler.handleDrag(screenPoint);
      }
    } catch (e, stackTrace) {
      logger.e('Error handling drag update', error: e, stackTrace: stackTrace);
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    try {
      logger.i('Long press ended');
      if (_isDragging) {
        _gestureHandler.endDrag();
      }
    } catch (e, stackTrace) {
      logger.e('Error handling long press end', error: e, stackTrace: stackTrace);
    }
  }

  // ---------------------------------------------------------------------
  //          NEW: PLACEMENT DIALOG REQUEST -> REVERSE GEOCODE
  // ---------------------------------------------------------------------
  Future<void> _handlePlacementDialogRequest(Point pressPoint) async {
    logger.i('EarthMapPage received a placement dialog request at $pressPoint');

    // 1) Retrieve lat/lng from the pressPoint
    final lat = pressPoint.coordinates.lat.toDouble();
    final lng = pressPoint.coordinates.lng.toDouble();

    // 2) Reverse geocode the short address
    final shortAddr = await GeocodingService.fetchShortAddress(lat, lng);
    logger.i('Short address for lat=$lat, lng=$lng => $shortAddr');

    // 3) Create a new instance of PlacementDialogFlow
    final placementFlow = PlacementDialogFlow();

    // 4) Start the 400ms timer & show dialogs, passing the short address
    placementFlow.startPlacementDialogTimer(
      pressPoint: pressPoint,
      context: context,
      annotationsManager: _annotationsManager,
      localAnnotationsRepository: _localRepo,
      annotationIdLinker: _annotationsManager.annotationIdLinker,
      initialShortAddress: shortAddr, // pre-fill the short address in the dialog
    );
  }

  // ---------------------------------------------------------------------
  //                     MENU BUTTON CALLBACKS
  // ---------------------------------------------------------------------
  void _handleMoveOrLockButton() {
    setState(() {
      if (_isDragging) {
        // Lock
        _gestureHandler.hideTrashCanAndStopDragging();
        _isDragging = false;
        _showRelocateHint = false;
      } else {
        // Move
        _gestureHandler.startDraggingSelectedAnnotation();
        _isDragging = true;
        _showRelocateHint = true;
      }
    });
  }

  Future<void> _handleEditButton() async {
    if (_annotationMenuAnnotation == null) {
      logger.w('No annotation selected to edit.');
      return;
    }

    await _annotationActions.editAnnotation(
      context: context,
      mapAnnotation: _annotationMenuAnnotation!,
    );

    setState(() {});
  }

  void _handleConnectButton() {
    logger.i('Connect button clicked');
    setState(() {
      _showAnnotationMenu = false;
      if (_isDragging) {
        _gestureHandler.hideTrashCanAndStopDragging();
        _isDragging = false;
        _showRelocateHint = false;
      }
      _isConnectMode = true;
    });
    if (_annotationMenuAnnotation != null) {
      _gestureHandler.enableConnectMode(_annotationMenuAnnotation!);
    } else {
      logger.w('No annotation available when Connect pressed');
    }
  }

  void _handleCancelButton() {
    setState(() {
      _showAnnotationMenu = false;
      _annotationMenuAnnotation = null;
      if (_isDragging) {
        _gestureHandler.hideTrashCanAndStopDragging();
        _isDragging = false;
      }
      _showRelocateHint = false;
    });
  }

  // ---------------------------------------------------------------------
  //                            UI BUILDERS
  // ---------------------------------------------------------------------
  Widget _buildMapWidget() {
    final styleUri = _determineGlobeStyleUri();
    logger.i("Using style URI: $styleUri");
    return GestureDetector(
      onLongPressStart: _handleLongPress,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: _handleLongPressEnd,
      onLongPressCancel: () {
        logger.i('Long press cancelled');
        if (_isDragging) {
          _gestureHandler.endDrag();
        }
      },
      child: MapWidget(
        cameraOptions: MapConfig.defaultCameraOptions,
        styleUri: styleUri,
        onMapCreated: _onMapCreated,
        onCameraChangeListener: _onCameraChangeListener,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The main map widget
          _buildMapWidget(),

          if (_isMapReady) ...[
            // Timeline
            buildTimelineButton(
              isMapReady: _isMapReady,
              context: context,
              mapboxMap: _mapboxMap,
              annotationsManager: _annotationsManager,
              onToggleTimeline: () => setState(() => _showTimelineCanvas = !_showTimelineCanvas),
              onHiveIdsFetched: (List<String> hiveIds) => setState(() => _hiveUuidsForTimeline = hiveIds),
            ),
            buildClearAnnotationsButton(annotationsManager: _annotationsManager),
            buildClearImagesButton(),
            buildDeleteImagesFolderButton(),

            // The search widget
            EarthMapSearchWidget(
              mapboxMap: _mapboxMap,
              annotationsManager: _annotationsManager,
              gestureHandler: _gestureHandler,
              localRepo: _localRepo,
              uuid: uuid,
              onSearchOpened: () => setState(() => _showRelocateHint = false),
              onSearchClosed: () => {},
            ),

            // "Relocate by address" hint if in move mode
            if (_isDragging && _showRelocateHint)
              Positioned(
                top: 45,
                left: 70,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Relocate by address',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),

            // The annotation menu
            AnnotationMenu(
              show: _showAnnotationMenu,
              annotation: _annotationMenuAnnotation,
              offset: _annotationMenuOffset,
              isDragging: _isDragging,
              annotationButtonText: _annotationButtonText,
              onMoveOrLock: _handleMoveOrLockButton,
              onEdit: _handleEditButton,
              onConnect: _handleConnectButton,
              onCancel: _handleCancelButton,
            ),

            // Connect mode banner
            buildConnectModeBanner(
              isConnectMode: _isConnectMode,
              gestureHandler: _gestureHandler,
              onCancel: () => setState(() => _isConnectMode = false),
            ),

            // Timeline Canvas
            buildTimelineCanvas(
              showTimelineCanvas: _showTimelineCanvas,
              hiveUuids: _hiveUuidsForTimeline,
            ),
          ],
        ],
      ),
    );
  }
}
