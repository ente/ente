import "package:hugeicons/hugeicons.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";

class ContactsFilter extends HierarchicalSearchFilter {
  final User user;
  final int occurrence;

  ContactsFilter({
    required this.user,
    required this.occurrence,
    super.filterTypeName = "contactsFilter",
    super.matchedUploadedIDs,
  });

  @override
  String name() {
    return resolveDisplayName(user);
  }

  @override
  int relevance() {
    return occurrence;
  }

  @override
  bool isMatch(EnteFile file) {
    return file.ownerID == user.id;
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is ContactsFilter) {
      return other.user.id == user.id;
    }
    return false;
  }

  @override
  SearchFilterIcon icon() {
    return HugeIcons.strokeRoundedUser;
  }
}
