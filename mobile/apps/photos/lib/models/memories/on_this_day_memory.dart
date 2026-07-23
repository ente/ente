import "package:photos/generated/l10n.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

class OnThisDayMemory extends SmartMemory {
  OnThisDayMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow, {
    String? id,
    super.firstCreationTime,
    super.lastCreationTime,
  }) : super(
         memories,
         MemoryType.onThisDay,
         '',
         firstDateToShow,
         lastDateToShow,
         id: id,
       );

  @override
  String createTitle(AppLocalizations locals, String languageCode) {
    return locals.onThisDay;
  }
}
