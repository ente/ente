import 'dart:async';
import 'dart:typed_data';

import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_contacts/contacts.dart';
import 'package:ente_sharing/extensions/user_extension.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';

enum AvatarType { small, mini, tiny, extra }

class UserAvatarWidget extends StatefulWidget {
  final User user;
  final AvatarType type;
  final int currentUserID;
  final bool thumbnailView;
  final BaseConfiguration config;

  const UserAvatarWidget(
    this.user, {
    super.key,
    this.currentUserID = -1,
    this.type = AvatarType.mini,
    this.thumbnailView = false,
    required this.config,
  });

  @override
  State<UserAvatarWidget> createState() => _UserAvatarWidgetState();

  static const strokeWidth = 1.0;
}

class _UserAvatarWidgetState extends State<UserAvatarWidget> {
  @override
  void initState() {
    super.initState();
    _preloadProfilePictureIfPossible();
  }

  @override
  void didUpdateWidget(covariant UserAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.email != widget.user.email) {
      _preloadProfilePictureIfPossible();
    }
  }

  void _preloadProfilePictureIfPossible() {
    final displayService = ContactsDisplayService.instance;
    if (displayService.hasResolvedProfilePicture(
      contactUserId: widget.user.id,
      email: widget.user.email,
    )) {
      return;
    }
    if (displayService.getCachedContact(
          contactUserId: widget.user.id,
          email: widget.user.email,
        ) ==
        null) {
      return;
    }
    unawaited(
      displayService.getProfilePictureBytes(
        contactUserId: widget.user.id,
        email: widget.user.email,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double size = getAvatarSize(widget.type);
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changes,
      builder: (context, _, _) {
        _preloadProfilePictureIfPossible();
        return SizedBox(
          height: size,
          width: size,
          child: _CircularAvatar(
            user: widget.user,
            type: widget.type,
            config: widget.config,
          ),
        );
      },
    );
  }
}

class _CircularAvatar extends StatelessWidget {
  final User user;
  final AvatarType type;
  final BaseConfiguration config;

  const _CircularAvatar({
    required this.user,
    required this.type,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final profilePictureBytes = ContactsDisplayService.instance
        .getCachedProfilePictureBytes(
          contactUserId: user.id,
          email: user.email,
        );
    final avatarStyle = _getAvatarStyle(context, type);
    final double size = avatarStyle.item1;
    if (profilePictureBytes != null) {
      return _CirclePhotoAvatar(bytes: profilePictureBytes, size: size);
    }

    final colorScheme = getEnteColorScheme(context);
    final displayLabel = user.resolvedDisplayName;
    final displayChar = displayLabel.isEmpty
        ? " "
        : displayLabel.substring(0, 1);
    final avatarSeed = user.resolvedEmail;
    Color decorationColor;
    if ((user.id != null && user.id! < 0) || user.email == config.getEmail()) {
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
  late String? currentUserEmail;
  late User user;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    currentUserEmail = widget.config.getEmail();
    _preloadProfilePictureIfPossible();
  }

  @override
  void didUpdateWidget(covariant FirstLetterUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      user = widget.user;
      _preloadProfilePictureIfPossible();
    }
  }

  void _preloadProfilePictureIfPossible() {
    final displayService = ContactsDisplayService.instance;
    if (displayService.hasResolvedProfilePicture(
      contactUserId: user.id,
      email: user.email,
    )) {
      return;
    }
    if (displayService.getCachedContact(
          contactUserId: user.id,
          email: user.email,
        ) ==
        null) {
      return;
    }
    unawaited(
      displayService.getProfilePictureBytes(
        contactUserId: user.id,
        email: user.email,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changes,
      builder: (context, _, _) {
        _preloadProfilePictureIfPossible();
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
        final displayLabel = user.resolvedDisplayName;
        final displayChar = displayLabel.isEmpty
            ? " "
            : displayLabel.substring(0, 1);
        final avatarSeed = user.resolvedEmail;
        Color decorationColor;
        if ((user.id != null && user.id! < 0) ||
            user.email == currentUserEmail) {
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

  const _CirclePhotoAvatar({required this.bytes, required this.size});

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
