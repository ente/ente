package io.ente.auth.watch

fun formatCode(code: String): String = when (code.length) {
    6 -> "${code.take(3)} ${code.drop(3)}"
    7 -> "${code.take(3)} ${code.substring(3, 4)} ${code.drop(4)}"
    8 -> "${code.take(3)} ${code.substring(3, 5)} ${code.drop(5)}"
    9 -> "${code.take(3)} ${code.substring(3, 6)} ${code.drop(6)}"
    else -> code
}
