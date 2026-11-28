public enum WatchError: String, Error, Equatable, Sendable {
  case invalidData
  case wrongEnrollment
  case payloadTooLarge
  case phoneLocked
  case staleVault
}
