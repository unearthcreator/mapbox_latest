class Annotation {
  final String id;
  final String? title;
  final String? iconName;
  final String? startDate;
  final String? endDate;
  final String? note;
  final double? latitude;
  final double? longitude;
  final String? imagePath;

  // NEW: Two optional fields for address
  final String? shortAddress;
  final String? fullAddress;

  Annotation({
    required this.id,
    this.title,
    this.iconName,
    this.startDate,
    this.endDate,
    this.note,
    this.latitude,
    this.longitude,
    this.imagePath,
    this.shortAddress,   // <-- new
    this.fullAddress,    // <-- new
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'iconName': iconName,
      'startDate': startDate,
      'endDate': endDate,
      'note': note,
      'latitude': latitude,
      'longitude': longitude,
      'imagePath': imagePath,
      'shortAddress': shortAddress, // new
      'fullAddress': fullAddress,   // new
    };
  }

  factory Annotation.fromJson(Map<String, dynamic> json) {
    return Annotation(
      id: json['id'] as String,
      title: json['title'] as String?,
      iconName: json['iconName'] as String?,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      note: json['note'] as String?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      imagePath: json['imagePath'] as String?,
      shortAddress: json['shortAddress'] as String?, // new
      fullAddress: json['fullAddress'] as String?,   // new
    );
  }

  @override
  String toString() {
    return 'Annotation('
           'id: $id, '
           'title: $title, '
           'iconName: $iconName, '
           'startDate: $startDate, '
           'endDate: $endDate, '
           'note: $note, '
           'latitude: $latitude, '
           'longitude: $longitude, '
           'imagePath: $imagePath, '
           'shortAddress: $shortAddress, '    // new
           'fullAddress: $fullAddress'        // new
           ')';
  }
}