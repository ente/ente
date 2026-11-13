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
  return getUserSuggestionAvatarIdentity(UserSuggestion.fromUser(user));
}

AvatarIdentity getUserSuggestionAvatarIdentity(UserSuggestion suggestion) {
  final resolved = resolveSuggestionIdentity(suggestion);
  return AvatarIdentity.account(
    label: resolved.displayName,
    email: resolved.knownEmail ?? suggestion.email,
    userID: suggestion.userID,
    currentUserID: Configuration.instance.getUserID(),
    currentUserEmail: Configuration.instance.getEmail(),
  );
}

class UserAvatarWidget extends StatefulWidget {
  final UserSuggestion suggestion;
  final AvatarType type;

  UserAvatarWidget(User user, {super.key, this.type = AvatarType.medium})
    : suggestion = UserSuggestion.fromUser(user);

  const UserAvatarWidget.suggestion(
    this.suggestion, {
    super.key,
    this.type = AvatarType.medium,
  });

  int? get userID => suggestion.userID;
  String get email => suggestion.email;
  AvatarIdentity get identity => getUserSuggestionAvatarIdentity(suggestion);

  @override
  State<UserAvatarWidget> createState() => _UserAvatarWidgetState();
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
          if (event.matchesContactUserId(widget.userID)) {
            _reload();
          }
        });
  }

  @override
  void didUpdateWidget(covariant UserAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email || oldWidget.userID != widget.userID) {
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
        final person = PersonService.instance.getCachedPersonForUser(
          widget.userID,
          widget.email,
        );
        if (person != null) {
          _canUsePersonFaceWidget = true;
          _personId = person.remoteID;
          lastSyncTimeForKey = PersonService.instance.lastRemoteSyncTime();
        } else {
          _canUsePersonFaceWidget = false;
          _personId = null;
        }
        _contactPhotoBytes = PhotosContactsService.instance
            .getCachedProfilePictureBytesByUserId(widget.userID);
      });
      final userId = widget.userID;
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
          widget.userID != userId) {
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
            cacheWidth: cachedPixelWidth,
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
                  : AvatarIdentityWidget(widget.identity, widget.type),
            ),
          )
        : AvatarIdentityWidget(widget.identity, widget.type);
  }
}

class AvatarIdentityWidget extends StatelessWidget {
  final AvatarIdentity identity;
  final AvatarType type;
  const AvatarIdentityWidget(this.identity, this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final avatarStyle = getAvatarStyle(context, type);
    final double size = avatarStyle.item1;
    final TextStyle textStyle = avatarStyle.item2;
    return SizedBox(
      height: size,
      width: size,
      child: CircleAvatar(
        backgroundColor: avatarBackgroundColor(context, identity),
        child: Text(
          identity.initials,
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

class UserInitialsAvatar extends StatelessWidget {
  final UserSuggestion suggestion;
  const UserInitialsAvatar(this.suggestion, {super.key});

  @override
  Widget build(BuildContext context) {
    final identity = getUserSuggestionAvatarIdentity(suggestion);
    return Container(
      color: avatarBackgroundColor(context, identity),
      child: Center(
        child: Text(
          identity.initials,
          style: getEnteTextTheme(context).small.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
