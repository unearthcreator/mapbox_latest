import 'dart:typed_data';
import 'package:flutter/services.dart'; // for rootBundle
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:map_mvp_project/services/error_handler.dart';
import 'package:map_mvp_project/src/earth_map/annotations/annotation_id_linker.dart';
import 'package:map_mvp_project/repositories/local_annotations_repository.dart';

/// A simple holder for all sub-annotations that make up one "conceptual" annotation.
class MultiAnnotationGroup {
  final PointAnnotation iconAnnotation;
  final PointAnnotation? titleAnnotation;
  final PointAnnotation? addressAnnotation; // short address
  final PointAnnotation? dateAnnotation;

  MultiAnnotationGroup({
    required this.iconAnnotation,
    this.titleAnnotation,
    this.addressAnnotation,
    this.dateAnnotation,
  });

  /// Collect all sub-annotations in a single list (for removal/updating).
  List<PointAnnotation> get all => [
    iconAnnotation,
    if (titleAnnotation != null) titleAnnotation!,
    if (addressAnnotation != null) addressAnnotation!,
    if (dateAnnotation != null) dateAnnotation!,
  ];
}

class MapAnnotationsManager {
  final PointAnnotationManager _annotationManager;
  final AnnotationIdLinker annotationIdLinker;
  final LocalAnnotationsRepository localAnnotationsRepository;

  // We track single annotations plus multi-annotation groups.
  final List<PointAnnotation> _annotations = [];
  final List<MultiAnnotationGroup> _multiAnnotations = [];

  MapAnnotationsManager(
    this._annotationManager, {
    required this.annotationIdLinker,
    required this.localAnnotationsRepository,
  });

  /// Access to the underlying annotation manager
  PointAnnotationManager get pointAnnotationManager => _annotationManager;

  // --------------------------------------------------------------------------
  // SINGLE-ANNOTATION METHOD
  // --------------------------------------------------------------------------
  Future<PointAnnotation> addAnnotation(
    Point mapPoint, {
    Uint8List? image,
    String? title,
    String? date,
  }) async {
    logger.i('addAnnotation() called. lat=${mapPoint.coordinates.lat}, lng=${mapPoint.coordinates.lng}');
    logger.i('title=$title, date=$date');

    // Minimal logic: icon + optional single-line text.
    String? displayText;
    if (title != null && title.isNotEmpty) {
      displayText = (date != null && date.isNotEmpty) ? '$title\n$date' : title;
    } else if (date != null && date.isNotEmpty) {
      displayText = date;
    }

    final iconImageName = (image == null) ? 'marker-15' : null;

    final annotationOptions = PointAnnotationOptions(
      geometry: mapPoint,
      iconSize: 5.0,
      image: image,
      iconImage: iconImageName,
      textField: displayText,
      textSize: (displayText != null) ? 14.0 : null,
      textAnchor: (displayText != null) ? TextAnchor.BOTTOM : null,
      iconAnchor: IconAnchor.BOTTOM,
      textOffset: (displayText != null) ? [0, -2.1] : null,
    );

    final annotation = await _annotationManager.create(annotationOptions);
    _annotations.add(annotation);
    logger.i('SINGLE annotation created. Total single annots now: ${_annotations.length}');
    return annotation;
  }

  // --------------------------------------------------------------------------
  // MULTI-ANNOTATION METHOD (Icon + Title + ShortAddress + Start/End Date)
  // --------------------------------------------------------------------------
  Future<MultiAnnotationGroup> addMultiPartAnnotation({
    required Point mapPoint,
    Uint8List? iconBytes,
    String? title,
    String? shortAddress,
    String? startDate,
    String? endDate,
    String? date,    // <-- a single combined date string and 
  }) async {
    logger.i('Adding MULTI annotation at: ${mapPoint.coordinates.lat}, ${mapPoint.coordinates.lng}');

    // 1) Combine startDate + endDate into one date string if both exist
    String? finalDateText;
    if (startDate != null && startDate.isNotEmpty && endDate != null && endDate.isNotEmpty) {
      finalDateText = '$startDate - $endDate';
    } else if (startDate != null && startDate.isNotEmpty) {
      finalDateText = startDate;
    } else if (endDate != null && endDate.isNotEmpty) {
      finalDateText = endDate;
    } else {
      finalDateText = null;
    }

    // 2) Icon annotation (anchor at bottom)
    final iconImageName = (iconBytes == null) ? 'marker-15' : null;
    final iconOptions = PointAnnotationOptions(
      geometry: mapPoint,
      iconSize: 5.0,
      image: iconBytes, // if not null, overrides iconImage
      iconImage: iconImageName,
      iconAnchor: IconAnchor.BOTTOM,
    );
    final iconAnn = await _annotationManager.create(iconOptions);

    // 3) Title annotation (largest text, slightly lower offset)
    PointAnnotation? titleAnn;
    if (title != null && title.isNotEmpty) {
      final titleOptions = PointAnnotationOptions(
        geometry: mapPoint,
        textField: title,
        textSize: 20.0,   // Title is largest
        textAnchor: TextAnchor.BOTTOM,
        textOffset: [0, -4.0], // adjust to place near address
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.0,
        textHaloBlur: 0.5,
      );
      titleAnn = await _annotationManager.create(titleOptions);
    }

    // 4) Address annotation (medium text size)
    PointAnnotation? addressAnn;
    if (shortAddress != null && shortAddress.isNotEmpty) {
      final addrOptions = PointAnnotationOptions(
        geometry: mapPoint,
        textField: shortAddress,
        textSize: 16.0,  // Address & date share same size
        textAnchor: TextAnchor.BOTTOM,
        textOffset: [0, -2.8],
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.0,
        textHaloBlur: 0.5,
        // Keep text on a single line
        textMaxWidth: 1000.0,
      );
      addressAnn = await _annotationManager.create(addrOptions);
    }

    // 5) Date annotation (medium text size) => finalDateText
    PointAnnotation? dateAnn;
    if (finalDateText != null && finalDateText.isNotEmpty) {
      final dateOptions = PointAnnotationOptions(
        geometry: mapPoint,
        textField: finalDateText,
        textSize: 16.0,
        textAnchor: TextAnchor.TOP,
        textOffset: [0, 0.8], // closer to icon
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.0,
        textHaloBlur: 0.5,
      );
      dateAnn = await _annotationManager.create(dateOptions);
    }

    // Combine them into a group object
    final group = MultiAnnotationGroup(
      iconAnnotation: iconAnn,
      titleAnnotation: titleAnn,
      addressAnnotation: addressAnn,
      dateAnnotation: dateAnn,
    );

    // Track them in the manager
    _multiAnnotations.add(group);
    _annotations.addAll(group.all);

    logger.i(
      'MultiAnnotationGroup created with icon=${iconAnn.id}, '
      'title=${titleAnn?.id}, address=${addressAnn?.id}, date=${dateAnn?.id}.'
    );
    return group;
  }

  // --------------------------------------------------------------------------
  // REMOVAL METHODS
  // --------------------------------------------------------------------------
  Future<void> removeAnnotation(PointAnnotation annotation) async {
    logger.i('removeAnnotation() => single');
    try {
      await _annotationManager.delete(annotation);
      final removed = _annotations.remove(annotation);
      if (removed) {
        logger.i('Removed annotation. Remaining single annots: ${_annotations.length}');
      } else {
        logger.w('Annotation not found in list');
      }
    } catch (e) {
      logger.e('Error removing annotation: $e');
      throw e;
    }
  }

  Future<void> removeMultiAnnotationGroup(MultiAnnotationGroup group) async {
    logger.i('removeMultiAnnotationGroup() => sub-annotations=${group.all.length}');
    for (final ann in group.all) {
      await _annotationManager.delete(ann);
      _annotations.remove(ann);
    }
    _multiAnnotations.remove(group);
    logger.i('MultiAnnotationGroup removed. Single annots left: ${_annotations.length}');
  }

  Future<void> removeAllAnnotations() async {
    if (_annotations.isNotEmpty) {
      await _annotationManager.deleteAll();
      _annotations.clear();
      _multiAnnotations.clear();
      logger.i('All annotations removed from the map.');
    } else {
      logger.i('No annotations to remove.');
    }
  }

  // --------------------------------------------------------------------------
  // UPDATING POSITIONS
  // --------------------------------------------------------------------------
  Future<void> updateVisualPosition(PointAnnotation annotation, Point newPoint) async {
    logger.i('updateVisualPosition() => annotationID=${annotation.id}, newLat=${newPoint.coordinates.lat}, newLng=${newPoint.coordinates.lng}');
    try {
      annotation.geometry = newPoint;
      await _annotationManager.update(annotation);
      logger.i('Updated annotation to lat=${newPoint.coordinates.lat}, lng=${newPoint.coordinates.lng}');
    } catch (e) {
      logger.e('Error updating position: $e');
      throw e;
    }
  }

  Future<void> updateMultiAnnotationGroupPosition(MultiAnnotationGroup group, Point newPoint) async {
    logger.i('updateMultiAnnotationGroupPosition() => newLat=${newPoint.coordinates.lat}, newLng=${newPoint.coordinates.lng}');
    for (final ann in group.all) {
      ann.geometry = newPoint;
      await _annotationManager.update(ann);
    }
    logger.i('MultiAnnotationGroup updated to new position');
  }

  // --------------------------------------------------------------------------
  // FIND NEAREST ANNOTATION
  // --------------------------------------------------------------------------
  Future<PointAnnotation?> findNearestAnnotation(Point tapPoint) async {
    if (_annotations.isEmpty) {
      logger.i('No annotations to search => returning null');
      return null;
    }

    double minDistance = double.infinity;
    PointAnnotation? nearest;

    for (final annotation in _annotations) {
      final distance = _calculateDistance(annotation.geometry, tapPoint);
      if (distance < minDistance) {
        minDistance = distance;
        nearest = annotation;
      }
    }
    if (nearest != null) {
      logger.i('Nearest annotation: ${nearest.id}, distance: $minDistance');
    }
    return (minDistance < 2.0) ? nearest : null;
  }

  // --------------------------------------------------------------------------
  // LOADING FROM HIVE (EXAMPLE)
  // --------------------------------------------------------------------------
  Future<void> loadAnnotationsFromHive() async {
    logger.i('loadAnnotationsFromHive() => loading...');
    final hiveAnnotations = await localAnnotationsRepository.getAnnotations();

    for (final ann in hiveAnnotations) {
      final lat = ann.latitude;
      final lng = ann.longitude;
      if (lat == null || lng == null) {
        logger.w('Annotation ${ann.id} missing lat/lng => skip');
        continue;
      }

      final point = Point(coordinates: Position(lng, lat));
      Uint8List? iconBytes;

      if (ann.iconName != null && ann.iconName!.isNotEmpty) {
        try {
          final iconData = await rootBundle.load('assets/icons/${ann.iconName}.png');
          iconBytes = iconData.buffer.asUint8List();
        } catch (e) {
          logger.w('Could not load icon ${ann.iconName}, using default');
          iconBytes = null;
        }
      }

      // If you store shortAddress in ann.note or a dedicated field,
      // adjust accordingly (this is just an example).
      final shortAddr = ann.note ?? '';

      final group = await addMultiPartAnnotation(
        mapPoint: point,
        iconBytes: iconBytes,
        title: ann.title,
        shortAddress: shortAddr,
        // now pass start & end dates if you store them:
        startDate: ann.startDate,
        endDate: ann.endDate,
      );
      annotationIdLinker.registerAnnotationId(group.iconAnnotation.id, ann.id);
      logger.i('Linked Hive ID=${ann.id} to iconID=${group.iconAnnotation.id}');
    }
    logger.i('Completed load from Hive');
  }

  // --------------------------------------------------------------------------
  // UTILS
  // --------------------------------------------------------------------------
  double _calculateDistance(Point p1, Point p2) {
    final latDiff = (p1.coordinates.lat.toDouble() - p2.coordinates.lat.toDouble()).abs();
    final lngDiff = (p1.coordinates.lng.toDouble() - p2.coordinates.lng.toDouble()).abs();
    return latDiff + lngDiff;
  }

  String get annotationLayerId => _annotationManager.id;
  bool get hasAnnotations => _annotations.isNotEmpty;
  List<PointAnnotation> get annotations => List.unmodifiable(_annotations);
  List<MultiAnnotationGroup> get multiAnnotations => List.unmodifiable(_multiAnnotations);
}