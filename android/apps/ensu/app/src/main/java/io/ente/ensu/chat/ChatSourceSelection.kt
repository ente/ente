package io.ente.ensu.chat

data class ChatSourceSelection(
    val selectedPackIds: Set<String> = emptySet(),
    val selectedFolderIds: Set<String> = emptySet(),
) {
    fun isPackEnabled(id: String): Boolean = id in selectedPackIds

    fun isFolderEnabled(id: String): Boolean = id in selectedFolderIds
}
