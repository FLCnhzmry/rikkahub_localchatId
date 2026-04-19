package me.rerere.rikkahub.data.ai

import me.rerere.ai.provider.CustomHeader

const val CLIENT_CONVERSATION_HEADER = "X-Client-Conversation-Id"

fun buildClientConversationHeaders(
    customHeaders: List<CustomHeader>,
    conversationId: String,
): List<CustomHeader> {
    return buildList {
        addAll(
            customHeaders.filterNot {
                it.name.equals(CLIENT_CONVERSATION_HEADER, ignoreCase = true)
            }
        )
        add(CustomHeader(CLIENT_CONVERSATION_HEADER, conversationId))
    }
}
