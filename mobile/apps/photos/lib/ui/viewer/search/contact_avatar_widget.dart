import "dart:async";
import "dart:typed_data";

import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";

class ContactAvatarWidget extends StatefulWidget {
  final int? contactUserId;
  final String email;
  final String? personId;
  final double size;

  const ContactAvatarWidget({
    required this.contactUserId,
    required this.email,
    required this.size,
    this.personId,
    super.key,
  });

  @override
  State<ContactAvatarWidget> createState() => _ContactAvatarWidgetState();
}

class _ContactAvatarWidgetState extends State<ContactAvatarWidget> {
  late Future<Uint8List?> _photoFuture;
  StreamSubscription<ContactsChangedEvent>? _contactsChangedSubscription;
  bool _canUsePersonFaceWidget = true;

  @override
  void initState() {
    super.initState();
    _photoFuture = _loadPhoto();
    _contactsChangedSubscription = Bus.instance
        .on<ContactsChangedEvent>()
        .listen((event) {
          if (event.matchesContactUserId(widget.contactUserId)) {
            setState(() {
              _photoFuture = _loadPhoto();
            });
          }
        });
  }

  @override
  void didUpdateWidget(covariant ContactAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contactUserId != widget.contactUserId ||
        oldWidget.email != widget.email ||
        oldWidget.personId != widget.personId) {
      _photoFuture = _loadPhoto();
      _canUsePersonFaceWidget = true;
    }
  }

  @override
  void dispose() {
    _contactsChangedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FaceThumbnailSquircleClip(
        borderRadius: faceThumbnailSquircleBorderRadius(widget.size),
        child: FutureBuilder<Uint8List?>(
          future: _photoFuture,
          builder: (context, snapshot) {
            final photoBytes = snapshot.data;
            if (photoBytes != null) {
              return Image.memory(photoBytes, fit: BoxFit.cover);
            }
            final personId = widget.personId;
            if (_canUsePersonFaceWidget &&
                personId != null &&
                personId.isNotEmpty) {
              return PersonFaceWidget(
                key: ValueKey(personId),
                personId: personId,
                onErrorCallback: () {
                  if (mounted) {
                    setState(() {
                      _canUsePersonFaceWidget = false;
                    });
                  }
                },
              );
            }
            return UserInitialsAvatar(_fallbackUser());
          },
        ),
      ),
    );
  }

  Future<Uint8List?> _loadPhoto() {
    return PhotosContactsService.instance.getProfilePictureBytesByUserId(
      widget.contactUserId,
    );
  }

  User _fallbackUser() {
    final baseUser = User(id: widget.contactUserId, email: widget.email);
    return User(
      id: widget.contactUserId,
      email: resolveKnownEmail(baseUser) ?? widget.email,
      // ignore: deprecated_member_use_from_same_package
      name: resolveDisplayName(baseUser),
    );
  }
}
