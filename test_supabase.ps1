$headers = @{
  "apikey" = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9teGdvbWZzZGdmaWR6ZnlkdGpkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxNTcwMDQsImV4cCI6MjA5MDczMzAwNH0.xtranl425vM_Nc2EZLRXgQuoFODPmXEAFPJGazBYu4E"
  "Authorization" = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9teGdvbWZzZGdmaWR6ZnlkdGpkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxNTcwMDQsImV4cCI6MjA5MDczMzAwNH0.xtranl425vM_Nc2EZLRXgQuoFODPmXEAFPJGazBYu4E"
}
$response = Invoke-RestMethod -Uri "https://omxgomfsdgfidzfydtjd.supabase.co/rest/v1/" -Headers $headers
$response | ConvertTo-Json -Depth 2