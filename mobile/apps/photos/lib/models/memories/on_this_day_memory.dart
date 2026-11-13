import "package:ente_strings/ente_strings.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

class OnThisDayMemory extends SmartMemory {
  OnThisDayMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow, {
    super.id,
    super.firstCreationTime,
    super.lastCreationTime,
  }) : super(
         memories,
         MemoryType.onThisDay,
         '',
         firstDateToShow,
         lastDateToShow,
       );

  @override
  String createTitle(StringsLocalizations locals, String languageCode) {
    return locals.onThisDay;
  }
}
