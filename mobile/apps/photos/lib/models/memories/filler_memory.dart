import "package:ente_strings/ente_strings.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

class FillerMemory extends SmartMemory {
  int yearsAgo;
  FillerMemory(
    List<Memory> memories,
    this.yearsAgo,
    int firstDateToShow,
    int lastDateToShow, {
    super.id,
    super.firstCreationTime,
    super.lastCreationTime,
  }) : super(
         memories,
         MemoryType.filler,
         'filler',
         firstDateToShow,
         lastDateToShow,
       );

  @override
  String createTitle(StringsLocalizations locals, String languageCode) {
    return locals.yearsAgo(count: yearsAgo);
  }
}
