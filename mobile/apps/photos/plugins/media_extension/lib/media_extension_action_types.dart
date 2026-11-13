enum IntentAction { main, pick, edit, view, unknown }

extension ParseToString on IntentAction {
  String toShortString() => toString().split('.').last;
}

IntentAction actionParser(String actionString) {
  IntentAction? action;

  switch (actionString) {
    case 'PICK':
      action = IntentAction.pick;
      break;
    case 'EDIT':
      action = IntentAction.edit;
      break;
    case 'VIEW':
      action = IntentAction.view;
      break;
    default:
      action = IntentAction.main;
  }

  return action;
}

class MediaExtentionAction {
  final IntentAction? action;
  final String? data;
  final MediaType? type;
  final String? extension;
  final String? name;
  final bool allowMultiple;

  MediaExtentionAction({
    this.name,
    this.type,
    this.extension,
    this.action,
    this.data,
    this.allowMultiple = false,
  });
}

enum MediaType { video, image }

MediaType? mediaParser(String? mediaString) {
  MediaType? type;

  switch (mediaString) {
    case 'video':
      type = MediaType.video;
      break;
    case 'image':
      type = MediaType.image;
      break;
  }
  return type;
}
