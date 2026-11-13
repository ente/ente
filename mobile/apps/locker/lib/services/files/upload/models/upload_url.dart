import 'dart:convert';

class UploadURL {
  final String url;
  final String objectKey;

  UploadURL(this.url, this.objectKey);
  Map<String, dynamic> toMap() {
    return {'url': url, 'objectKey': objectKey};
  }

  factory UploadURL.fromMap(Map<String, dynamic> map) {
    return UploadURL(map['url'], map['objectKey']);
  }

  String toJson() => json.encode(toMap());

  factory UploadURL.fromJson(String source) =>
      UploadURL.fromMap(json.decode(source));
}
