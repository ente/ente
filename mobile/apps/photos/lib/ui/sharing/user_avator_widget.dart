import "dart:async";
import "dart:typed_data";

import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/photos_contacts_service.dart";
import 'package:photos/theme/ente_theme.dart';
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/avatar_util.dart";
import 'package:tuple/tuple.dart';

enum AvatarType { xs, small, medium, regular, large, huge }

Color getUserAvatarColor(BuildContext context, User user) {
  return avatarBackgroundColor(context, getUserAvatarIdentity(user));
}

AvatarIdentity getUserAvatarIdentity(User user) {
  return AvatarIdentity.account(
    label: resolveDisplayName(user),
    email: resolveKnownEmail(user) ?? user.email,
    userID: user.id,
    currentUserEmail: Configuration.instance.getEmail(),
  );
}

class UserAvatarWidget extends StatefulWidget {
  final User user;
  final AvatarType type;
  final int currentUserID;
  final bool thumbnailView;
  final bool addStroke;
  final AvatarIdentity? fallbackIdentity;

  const UserAvatarWidget(
    this.user, {
    super.key,
    this.currentUserID = -1,
    this.type = AvatarType.medium,
    this.thumbnailView = false,
    this.addStroke = true,
    this.fallbackIdentity,
  });

  @override
  State<UserAvatarWidget> createState() => _UserAvatarWidgetState();
  static const strokeWidth = 1.0;
}

class _UserAvatarWidgetState extends State<UserAvatarWidget> {
  String? _personId;
  Uint8List? _contactPhotoBytes;
  bool _canUsePersonFaceWidget = false;
  int _photoLoadGeneration = 0;
  int lastSyncTimeForKey = 0;
  late final StreamSubscription<PeopleChangedEvent> _peopleChangedSubscription;
  StreamSubscription<ContactsChangedEvent>? _contactsChangedSubscription;
  final _debouncer = Debouncer(
    const Duration(milliseconds: 250),
    executionInterval: const Duration(seconds: 20),
    leading: true,
  );

  @override
  void initState() {
    super.initState();
    _reload();
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen((
      event,
    ) {
      if (event.type == PeopleEventType.saveOrEditPerson ||
          event.type == PeopleEventType.syncDone) {
        _reload();
      }
    });
    _contactsChangedSubscription = Bus.instance
        .on<ContactsChangedEvent>()
        .listen((event) {
          if (event.matchesContactUserId(widget.user.id)) {
            _reload();
          }
        });
  }

  @override
  void didUpdateWidget(covariant UserAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.email != widget.user.email ||
        oldWidget.user.id != widget.user.id) {
      _reload();
    }
  }

  @override
  void dispose() {
    _peopleChangedSubscription.cancel();
    _contactsChangedSubscription?.cancel();
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }

  Future<void> _reload() async {
    _debouncer.run(() async {
      if (!mounted) return;
      setState(() {
        final data = PersonService
            .instance
            .emailToPartialPersonDataMapCache[widget.user.email];
        if (data != null && data.containsKey(PersonService.kPersonIDKey)) {
          _canUsePersonFaceWidget = true;
          _personId = data[PersonService.kPersonIDKey] as String;
          lastSyncTimeForKey = PersonService.instance.lastRemoteSyncTime();
        } else {
          _canUsePersonFaceWidget = false;
          _personId = null;
        }
        _contactPhotoBytes = PhotosContactsService.instance
            .getCachedProfilePictureBytesByUserId(widget.user.id);
      });
      final userId = widget.user.id;
      if (userId == null ||
          PhotosContactsService.instance.hasResolvedProfilePictureByUserId(
            userId,
          )) {
        return;
      }
      final loadGeneration = ++_photoLoadGeneration;
      final photoBytes = await PhotosContactsService.instance
          .getProfilePictureBytesByUserId(userId);
      if (!mounted ||
          loadGeneration != _photoLoadGeneration ||
          widget.user.id != userId) {
        return;
      }
      setState(() {
        _contactPhotoBytes = photoBytes;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double size = getAvatarSize(widget.type);
    final int cachedPixelWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .toInt();
    if (_contactPhotoBytes != null) {
      return SizedBox(
        height: size,
        width: size,
        child: ClipOval(
          child: Image.memory(
            _contactPhotoBytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    return _personId != null
        ? SizedBox(
            height: size,
            width: size,
            child: ClipOval(
              child: _canUsePersonFaceWidget
                  ? PersonFaceWidget(
                      key: ValueKey('$_personId-$lastSyncTimeForKey'),
                      personId: _personId!,
                      cachedPixelWidth: cachedPixelWidth,
                      onErrorCallback: () {
                        if (mounted) {
                          setState(() {
                            _personId = null;
                            _canUsePersonFaceWidget = false;
                          });
                        }
                      },
                    )
                  : _FirstLetterCircularAvatar(
                      user: widget.user,
                      type: widget.type,
                      fallbackIdentity: widget.fallbackIdentity,
                    ),
            ),
          )
        : _FirstLetterCircularAvatar(
            user: widget.user,
            type: widget.type,
            fallbackIdentity: widget.fallbackIdentity,
          );
  }
}

class _FirstLetterCircularAvatar extends StatelessWidget {
  final User user;
  final AvatarType type;
  final AvatarIdentity? fallbackIdentity;
  const _FirstLetterCircularAvatar({
    required this.user,
    required this.type,
    required this.fallbackIdentity,
  });

  @override
  Widget build(BuildContext context) {
    final identity = fallbackIdentity ?? getUserAvatarIdentity(user);

    final avatarStyle = getAvatarStyle(context, type);
    final double size = avatarStyle.item1;
    final TextStyle textStyle = avatarStyle.item2;
    return SizedBox(
      height: size,
      width: size,
      child: CircleAvatar(
        backgroundColor: avatarBackgroundColor(context, identity),
        child: Text(
          identity.initial,
          // fixed color
          style: textStyle.copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Tuple2<double, TextStyle> getAvatarStyle(
    BuildContext context,
    AvatarType type,
  ) {
    final enteTextTheme = getEnteTextTheme(context);
    switch (type) {
      case AvatarType.huge:
        return Tuple2(56.0, enteTextTheme.largeBold);
      case AvatarType.large:
        return Tuple2(32.0, enteTextTheme.mini);
      case AvatarType.regular:
        return Tuple2(28.0, enteTextTheme.mini);
      case AvatarType.medium:
        return Tuple2(24.0, enteTextTheme.mini);
      case AvatarType.small:
        return Tuple2(20.0, enteTextTheme.tiny);
      case AvatarType.xs:
        return Tuple2(16.0, enteTextTheme.tiny);
    }
  }
}

double getAvatarSize(AvatarType type) {
  switch (type) {
    case AvatarType.huge:
      return 56.0;
    case AvatarType.large:
      return 32.0;
    case AvatarType.regular:
      return 28.0;
    case AvatarType.medium:
      return 24.0;
    case AvatarType.small:
      return 20.0;
    case AvatarType.xs:
      return 16.0;
  }
}

class FirstLetterUserAvatar extends StatelessWidget {
  final User user;
  const FirstLetterUserAvatar(this.user, {super.key});

  @override
  Widget build(BuildContext context) {
    final identity = getUserAvatarIdentity(user);
    return Container(
      color: avatarBackgroundColor(context, identity),
      child: Center(
        child: Text(
          identity.initial,
          style: getEnteTextTheme(context).small.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
