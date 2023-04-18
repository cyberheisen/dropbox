# Set the MID Server endpoint URL
$url = "http://<mid_server_host>:<mid_server_port>/ecc_queue.do"

# Set the MID Server credentials
$username = "<mid_server_username>"
$password = "<mid_server_password>"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($username, $securePassword)

# Set the ServiceNow API endpoint URL
$apiUrl = "https://<your_instance_name>.service-now.com/api/now/table/sys_user"

# Set the ServiceNow API headers
$headers = @{
    "Content-Type" = "application/json"
    "Accept" = "application/json"
}

# Set the ServiceNow API query parameters
$queryParams = @{
    "sysparm_fields" = "sys_id,name,email"
    "sysparm_query" = "active=true"
}

# Define the MID Server request payload
$payload = @{
    "agent" = "<mid_server_name>"
    "topic" = "ServiceNowV2"
    "name" = "GET"
    "source" = "PowerShell"
    "payload" = @{
        "url" = $apiUrl
        "headers" = $headers
        "query_params" = $queryParams
        "method" = "GET"
        "username" = "<your_service_account_username>"
        "password" = "<your_service_account_password>"
    }
}

# Convert the payload to JSON format
$jsonPayload = $payload | ConvertTo-Json -Depth 4

# Send the MID Server request and capture the response
$response = Invoke-RestMethod -Uri $url -Method Post -Credential $credentials -Body $jsonPayload

# Extract the list of users from the ServiceNow API response
$users = $response.result.records
$users
