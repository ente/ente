import 'dart:typed_data';

import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_contacts/contacts.dart';
import 'package:ente_sharing/extensions/user_extension.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';

enum AvatarType { small, mini, tiny, extra }

bool _usesBlackAvatar(int? userID, String email, BaseConfiguration config) {
  return (userID != null &&
          (userID < 0 || (userID > 0 && userID == config.getUserID()))) ||
      email == config.getEmail();
}

void _preloadProfilePicture(int? userID, String email) {
  ContactsDisplayService.instance.preloadProfilePicture(
    contactUserId: userID,
    email: email,
  );
}

class UserAvatarWidget extends StatefulWidget {
  final int? userID;
  final String email;
  final AvatarType type;
  final BaseConfiguration config;

  UserAvatarWidget(
    User user, {
    super.key,
    this.type = AvatarType.mini,
    required this.config,
  }) : userID = user.id,
       email = user.email;

  UserAvatarWidget.suggestion(
    UserSuggestion suggestion, {
    super.key,
    this.type = AvatarType.mini,
    required this.config,
  }) : userID = suggestion.userID,
       email = suggestion.email;

  @override
  State<UserAvatarWidget> createState() => _UserAvatarWidgetState();
}

class _UserAvatarWidgetState extends State<UserAvatarWidget> {
  @override
  void initState() {
    super.initState();
    _preloadProfilePicture(widget.userID, widget.email);
  }

  @override
  void didUpdateWidget(covariant UserAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userID != widget.userID || oldWidget.email != widget.email) {
      _preloadProfilePicture(widget.userID, widget.email);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double size = getAvatarSize(widget.type);
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changesFor(
        contactUserId: widget.userID,
        email: widget.email,
      ),
      builder: (context, _, _) {
        _preloadProfilePicture(widget.userID, widget.email);
        return SizedBox(
          height: size,
          width: size,
          child: _CircularAvatar(
            widget.userID,
            widget.email,
            widget.type,
            widget.config,
          ),
        );
      },
    );
  }
}

class _CircularAvatar extends StatelessWidget {
  final int? userID;
  final String email;
  final AvatarType type;
  final BaseConfiguration config;

  const _CircularAvatar(this.userID, this.email, this.type, this.config);

  @override
  Widget build(BuildContext context) {
    final profilePictureBytes = ContactsDisplayService.instance
        .getCachedProfilePictureBytes(contactUserId: userID, email: email);
    final avatarStyle = _getAvatarStyle(context, type);
    final double size = avatarStyle.item1;
    if (profilePictureBytes != null) {
      return _CirclePhotoAvatar(profilePictureBytes, size);
    }

    final colorScheme = getEnteColorScheme(context);
    final identity = resolveUserIdentity(userID, email);
    final displayLabel = identity.displayName;
    final displayChar = displayLabel.isEmpty
        ? " "
        : displayLabel.substring(0, 1);
    final avatarSeed = identity.email;
    Color decorationColor;
    if (_usesBlackAvatar(userID, email, config)) {
      decorationColor = Colors.black;
    } else {
      decorationColor =
          colorScheme.avatarColors[avatarSeed.length.remainder(
            colorScheme.avatarColors.length,
          )];
    }

    return CircleAvatar(
      backgroundColor: decorationColor,
      child: Text(
        displayChar.toUpperCase(),
        style: avatarStyle.item2.copyWith(color: Colors.white),
      ),
    );
  }

  Tuple2<double, TextStyle> _getAvatarStyle(
    BuildContext context,
    AvatarType type,
  ) {
    final enteTextTheme = getEnteTextTheme(context);
    switch (type) {
      case AvatarType.small:
        return Tuple2(32.0, enteTextTheme.small);
      case AvatarType.mini:
        return Tuple2(24.0, enteTextTheme.mini);
      case AvatarType.tiny:
        return Tuple2(18.0, enteTextTheme.tiny);
      case AvatarType.extra:
        return Tuple2(18.0, enteTextTheme.tiny);
    }
  }
}

double getAvatarSize(AvatarType type) {
  switch (type) {
    case AvatarType.small:
      return 32.0;
    case AvatarType.mini:
      return 24.0;
    case AvatarType.tiny:
      return 18.0;
    case AvatarType.extra:
      return 18.0;
  }
}

class FirstLetterUserAvatar extends StatefulWidget {
  final User user;
  final BaseConfiguration config;

  const FirstLetterUserAvatar(this.user, {super.key, required this.config});

  @override
  State<FirstLetterUserAvatar> createState() => _FirstLetterUserAvatarState();
}

class _FirstLetterUserAvatarState extends State<FirstLetterUserAvatar> {
  @override
  void initState() {
    super.initState();
    _preloadProfilePicture(widget.user.id, widget.user.email);
  }

  @override
  void didUpdateWidget(covariant FirstLetterUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      _preloadProfilePicture(widget.user.id, widget.user.email);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changesFor(
        contactUserId: user.id,
        email: user.email,
      ),
      builder: (context, _, _) {
        _preloadProfilePicture(user.id, user.email);
        final profilePictureBytes = ContactsDisplayService.instance
            .getCachedProfilePictureBytes(
              contactUserId: user.id,
              email: user.email,
            );
        if (profilePictureBytes != null) {
          return Image.memory(
            profilePictureBytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }

        final colorScheme = getEnteColorScheme(context);
        final identity = resolveUserIdentity(user.id, user.email);
        final displayLabel = identity.displayName;
        final displayChar = displayLabel.isEmpty
            ? " "
            : displayLabel.substring(0, 1);
        final avatarSeed = identity.email;
        Color decorationColor;
        if (_usesBlackAvatar(user.id, user.email, widget.config)) {
          decorationColor = Colors.black;
        } else {
          decorationColor =
              colorScheme.avatarColors[avatarSeed.length.remainder(
                colorScheme.avatarColors.length,
              )];
        }

        return Container(
          color: decorationColor,
          child: Center(
            child: Text(
              displayChar.toUpperCase(),
              style: getEnteTextTheme(
                context,
              ).small.copyWith(color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

class _CirclePhotoAvatar extends StatelessWidget {
  final Uint8List bytes;
  final double size;

  const _CirclePhotoAvatar(this.bytes, this.size);

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}
