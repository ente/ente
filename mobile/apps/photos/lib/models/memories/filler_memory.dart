import "package:photos/generated/l10n.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

class FillerMemory extends SmartMemory {
  // For creating the title
  int yearsAgo;
  FillerMemory(
    List<Memory> memories,
    this.yearsAgo,
    int firstDateToShow,
    int lastDateToShow, {
    String? id,
    super.firstCreationTime,
    super.lastCreationTime,
  }) : super(
         memories,
         MemoryType.filler,
         'filler',
         firstDateToShow,
         lastDateToShow,
         id: id,
       );

  @override
  String createTitle(AppLocalizations locals, String languageCode) {
    return locals.yearsAgo(count: yearsAgo);
  }
}
