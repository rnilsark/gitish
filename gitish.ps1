param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$UserCommand
)

# Function to read .env file
function Read-EnvFile {
    if (Test-Path .env) {
        Get-Content .env | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2]
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
}

# Read .env file
Read-EnvFile

# Check for OpenAI API key in environment variables
if (-not $env:OPENAI_API_KEY) {
    $apiKey = Read-Host "Please enter your OpenAI API key"
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $apiKey, "User")
    $env:OPENAI_API_KEY = $apiKey
    Write-Host "API key has been set as an environment variable."
}

# Function to call OpenAI API
function Get-OpenAICompletion {
    param (
        [string]$Prompt,
        [string]$Model = "gpt-3.5-turbo",
        [int]$MaxTokens = 50
    )

    $headers = @{
        "Authorization" = "Bearer $env:OPENAI_API_KEY"
        "Content-Type" = "application/json"
    }

    $body = @{
        "model" = $Model
        "messages" = @(
            @{
                "role" = "user"
                "content" = $Prompt
            }
        )
        "max_tokens" = $MaxTokens
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $body
    return $response.choices[0].message.content
}

# Combine user input into a single string
$userInput = $UserCommand -join " "

# Prepare the prompt for OpenAI
$prompt = @"
Convert the following user input to a regular git command:
User input: $userInput

Respond with only the git command, nothing else.
"@

# Get the interpreted git command from OpenAI
$response = Get-OpenAICompletion -Prompt $prompt -Model "gpt-3.5-turbo" -MaxTokens 50

# Extract the git command from the response
$gitCommand = $response.Trim()

# Compare user input with the interpreted git command
if ($userInput -ne $gitCommand -and $userInput -ne $gitCommand.Replace("git", "gitish")) {
    Write-Host "I think you mean: $gitCommand"
    Write-Host "This command does the following:"
    
    # Get an explanation of the git command from OpenAI
    $explanationPrompt = @"
Explain what the following git command does in a short, concise manner:
$gitCommand
"@
    
    $explanation = Get-OpenAICompletion -Prompt $explanationPrompt -Model "gpt-3.5-turbo" -MaxTokens 100
    Write-Host $explanation.Trim()
    Write-Host ""

    # Ask for user confirmation with default "Yes"
    $confirmation = Read-Host "Do you want to execute this command? (Y/n)"
    if ($confirmation -eq "" -or $confirmation -eq "Y" -or $confirmation -eq "y") {
        Write-Host "Executing the command..."
    } else {
        Write-Host "Command execution cancelled."
        return
    }
}

# Execute the git command
Invoke-Expression $gitCommand