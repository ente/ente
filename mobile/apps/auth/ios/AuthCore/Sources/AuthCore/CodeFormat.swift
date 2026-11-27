public func formatCode(_ code: String) -> String {
  let sizes: [Int]
  switch code.count {
  case 6: sizes = [3, 3]
  case 7: sizes = [3, 1, 3]
  case 8: sizes = [3, 2, 3]
  case 9: sizes = [3, 3, 3]
  default: return code
  }
  var remaining = code[...]
  return sizes.map { size in
    let group = String(remaining.prefix(size))
    remaining = remaining.dropFirst(size)
    return group
  }.joined(separator: " ")
}
