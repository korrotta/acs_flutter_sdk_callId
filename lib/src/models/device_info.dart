/// Describes an audio or video device exposed by the native SDKs.
class DeviceInfo {
  final String id;
  final String name;
  final String type; // camera | microphone | speaker | unknown
  final String? facing; // front/back for cameras when available

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    this.facing,
  });

  factory DeviceInfo.fromMap(Map<String, dynamic> map) {
    return DeviceInfo(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? 'unknown',
      facing: map['facing']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        if (facing != null) 'facing': facing,
      };
}
