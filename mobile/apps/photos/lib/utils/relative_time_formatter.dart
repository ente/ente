import "package:intl/intl.dart";

String formatCompactRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inMinutes < 1) {
    return "just now";
  } else if (difference.inMinutes < 60) {
    return "${difference.inMinutes}m ago";
  } else if (difference.inHours < 24) {
    return "${difference.inHours}hr ago";
  } else if (difference.inDays < 7) {
    return "${difference.inDays}d ago";
  } else {
    final sameYear = dateTime.year == now.year;
    return DateFormat(sameYear ? "MMM d" : "MMM d, yyyy").format(dateTime);
  }
}

String formatTimeAgo(DateTime dateTime) {
  final elapsedMilliseconds =
      DateTime.now().millisecondsSinceEpoch - dateTime.millisecondsSinceEpoch;
  final seconds = elapsedMilliseconds / Duration.millisecondsPerSecond;
  final minutes = seconds / Duration.secondsPerMinute;
  final hours = minutes / Duration.minutesPerHour;
  final days = hours / Duration.hoursPerDay;
  final months = days / 30;
  final years = days / 365;

  final String value;
  if (seconds < 45) {
    value = "a moment";
  } else if (seconds < 90) {
    value = "a minute";
  } else if (minutes < 45) {
    value = "${minutes.round()} minutes";
  } else if (minutes < 90) {
    value = "about an hour";
  } else if (hours < 24) {
    value = "${hours.round()} hours";
  } else if (hours < 48) {
    value = "a day";
  } else if (days < 30) {
    value = "${days.round()} days";
  } else if (days < 60) {
    value = "about a month";
  } else if (days < 365) {
    value = "${months.round()} months";
  } else if (years < 2) {
    value = "about a year";
  } else {
    value = "${years.round()} years";
  }

  return "$value ago";
}
