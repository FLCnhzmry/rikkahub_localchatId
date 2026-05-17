param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir
)

$ErrorActionPreference = "Stop"

$basePackagePath = "app/src/main/java/me/rerere/rikkahub"
$generationHandlerPath = Join-Path $WorkDir "$basePackagePath/data/ai/GenerationHandler.kt"
$chatServicePath = Join-Path $WorkDir "$basePackagePath/service/ChatService.kt"
$clientConversationHeaderPath = Join-Path $WorkDir "$basePackagePath/data/ai/ClientConversationHeader.kt"

function Assert-FileExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path $Path)) {
        throw "Target file not found: $Description ($Path)"
    }
}

function Assert-ContentContains {
    param([string]$Content, [string]$Pattern, [string]$Description)
    if ($Content -notmatch [regex]::Escape($Pattern)) {
        throw "Verification failed: '$Description' not found after injection."
    }
}

# --- Step 1: Create ClientConversationHeader.kt ---

Write-Host "Creating ClientConversationHeader.kt..."

$headerDir = Split-Path -Parent $clientConversationHeaderPath
if (-not (Test-Path $headerDir)) {
    New-Item -ItemType Directory -Force -Path $headerDir | Out-Null
}

$clientConversationHeaderContent = @'
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
'@

[System.IO.File]::WriteAllLines($clientConversationHeaderPath, $clientConversationHeaderContent.Split("`n"))
Write-Host "  Created: $clientConversationHeaderPath"

# --- Step 2: Modify GenerationHandler.kt ---

Write-Host "Modifying GenerationHandler.kt..."
Assert-FileExists $generationHandlerPath "GenerationHandler.kt"

$ghContent = [System.IO.File]::ReadAllText($generationHandlerPath)

# 2a) Add clientConversationId param to generateText signature
#     Anchor: "messages: List<UIMessage>," inside "fun generateText("
$pattern2a = '(?m)(fun generateText\(\s*\n(?:.*\n)*?.*messages:\s*List<UIMessage>,\s*\n)'
if ($ghContent -notmatch $pattern2a) {
    throw "Injection point 2a not found: generateText signature with messages param"
}
$ghContent = $ghContent -replace $pattern2a, '${1}        clientConversationId: String,
'

# 2b) Add clientConversationId arg to generateInternal call
#     Anchor: "generateInternal(" block, "messages = messages," line
$pattern2b = '(?m)(generateInternal\(\s*\n\s*assistant = assistant,\s*\n\s*settings = settings,\s*\n\s*messages = messages,\s*\n)'
if ($ghContent -notmatch $pattern2b) {
    throw "Injection point 2b not found: generateInternal call with messages = messages"
}
$ghContent = $ghContent -replace $pattern2b, '${1}                    clientConversationId = clientConversationId,
'

# 2c) Add clientConversationId param to generateInternal signature
#     Anchor: "private suspend fun generateInternal(" + "messages: List<UIMessage>,"
$pattern2c = '(?m)(private suspend fun generateInternal\(\s*\n(?:.*\n)*?.*messages:\s*List<UIMessage>,\s*\n)'
if ($ghContent -notmatch $pattern2c) {
    throw "Injection point 2c not found: generateInternal signature with messages param"
}
$ghContent = $ghContent -replace $pattern2c, '${1}        clientConversationId: String,
'

# 2d) Replace customHeaders block with buildClientConversationHeaders wrapper
$pattern2d = '(?m)(\s*)customHeaders = buildList \{\s*\n\s*addAll\(assistant\.customHeaders\)\s*\n\s*addAll\(model\.customHeaders\)\s*\n\s*\},'
if ($ghContent -notmatch $pattern2d) {
    throw "Injection point 2d not found: customHeaders = buildList block"
}
$replacement2d = '${1}customHeaders = buildClientConversationHeaders(
${1}    customHeaders = buildList {
${1}        addAll(assistant.customHeaders)
${1}        addAll(model.customHeaders)
${1}    },
${1}    conversationId = clientConversationId
${1}),'
$ghContent = $ghContent -replace $pattern2d, $replacement2d

[System.IO.File]::WriteAllText($generationHandlerPath, $ghContent)
Write-Host "  Modified: $generationHandlerPath"

# --- Step 3: Modify ChatService.kt ---

Write-Host "Modifying ChatService.kt..."
Assert-FileExists $chatServicePath "ChatService.kt"

$csContent = [System.IO.File]::ReadAllText($chatServicePath)

# Insert "clientConversationId = conversation.id.toString()," before "assistant = assistant,"
# within the generationHandler.generateText( block
$pattern3 = '(?m)(generationHandler\.generateText\((?:.*\n)*?)((\s*)assistant = assistant,)'
if ($csContent -notmatch $pattern3) {
    throw "Injection point 3 not found: generationHandler.generateText call with assistant = assistant"
}
$csContent = $csContent -replace $pattern3, '${1}${3}clientConversationId = conversation.id.toString(),
${2}'

[System.IO.File]::WriteAllText($chatServicePath, $csContent)
Write-Host "  Modified: $chatServicePath"

# --- Step 4: Verification ---

Write-Host "Verifying injections..."

$ghVerify = [System.IO.File]::ReadAllText($generationHandlerPath)
$csVerify = [System.IO.File]::ReadAllText($chatServicePath)

Assert-ContentContains $ghVerify "clientConversationId: String," "generateText param"
Assert-ContentContains $ghVerify "clientConversationId = clientConversationId," "generateInternal arg"
Assert-ContentContains $ghVerify "buildClientConversationHeaders(" "customHeaders wrapper"
Assert-ContentContains $csVerify "clientConversationId = conversation.id.toString()," "ChatService arg"

if (-not (Test-Path $clientConversationHeaderPath)) {
    throw "Verification failed: ClientConversationHeader.kt not created"
}

Write-Host "All injections verified successfully."
