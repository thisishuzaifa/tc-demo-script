#!/bin/bash

# USAGE: ./install_macos_software.sh <RoleProfile>
#        <RoleProfile> (e.g., 'Analyst', 'Developer') is REQUIRED.
#        Requires 'software_config.json' in the same directory.
# EXAMPLE: ./install_macos_software.sh Analyst
# NOTES: Used Claude to do regex check and also figure out how to read a json file. Because I wanted to make the script extensible should we add more roles or software in the future.
#        Checks Malwarebytes and Mac Gatekeeper status.

# Role profile argument (REQUIRED)
ROLE_PROFILE=$1
# Configuration file (expected in the same directory as the script)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
CONFIG_FILE="${SCRIPT_DIR}/software_config.json"

# Log file (REQUIRED - placed in user's home directory with timestamp)
LOG_FILE="${HOME}/SoftwareInstallLog_$(date +%Y%m%d_%H%M%S).log" # Changed from Desktop to Home


# Check if Role Profile argument is provided
if [[ -z "$ROLE_PROFILE" ]]; then
  # Log initial error to console only, as log file might not be set up yet
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] Usage: $0 <RoleProfile>. RoleProfile (e.g., Analyst, Developer) is required."
  exit 1
fi

# Attempt to create the log file to ensure writability
echo "Attempting to initialize log file at: $LOG_FILE"
touch "$LOG_FILE"
if [[ $? -ne 0 ]]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] Cannot write to log file location: $LOG_FILE. Check permissions."
    exit 1
fi
echo "Log file initialized successfully."

# Function to log messages to console AND required file
log_message() {
  local level="$1"
  local message="$2"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local log_entry="[$timestamp] [$level] $message"

  # Write to Console
  echo "$log_entry"
  # Append to Log File (now mandatory)
  echo "$log_entry" >> "$LOG_FILE"
  # Basic check if file write failed (though initial check should prevent most issues)
  if [[ $? -ne 0 ]]; then
      echo "[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] Failed writing to log file $LOG_FILE during script execution!"
      # Optionally exit if logging failure is critical
      # exit 1
  fi
}

# Function to check for and install Homebrew
install_homebrew() {
  log_message "INFO" "Checking for Homebrew..."
  if command -v brew &>/dev/null; then
    log_message "INFO" "Homebrew is already installed. Updating..."
    brew update || log_message "WARNING" "Homebrew update failed."
  else
    log_message "INFO" "Homebrew not found. Attempting installation..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ $? -ne 0 ]]; then
      log_message "ERROR" "Homebrew installation failed. Please check the output above."
      exit 1
    fi
    log_message "INFO" "Homebrew installed successfully."
    # Attempt to add brew to PATH for the current script execution
    if [[ -x "/opt/homebrew/bin/brew" ]]; then # Apple Silicon
        export PATH="/opt/homebrew/bin:$PATH"
    elif [[ -x "/usr/local/bin/brew" ]]; then # Intel
        export PATH="/usr/local/bin:$PATH"
    fi
     if ! command -v brew &>/dev/null; then
         log_message "ERROR" "Failed to add Homebrew to PATH automatically. Please add it manually or restart your terminal."
         exit 1
     fi
  fi
}

# Function to check for and install jq (JSON processor)
install_jq() {
    log_message "INFO" "Checking for jq (JSON processor)..."
    if command -v jq &>/dev/null; then
        log_message "INFO" "jq is already installed."
    else
        log_message "INFO" "jq not found. Attempting installation via Homebrew..."
        brew install jq
        if [[ $? -ne 0 ]]; then
            log_message "ERROR" "jq installation failed. Please check brew output."
            exit 1
        fi
        log_message "INFO" "jq installed successfully."
    fi
}

# Function to install Homebrew Formulae (command-line tools)
install_formulae() {
  local formulae=("$@") # Accept array of formulae
  if [[ ${#formulae[@]} -eq 0 ]]; then
    log_message "INFO" "No formulae provided to install in this list."
    return
  fi

  log_message "INFO" "Processing formulae: ${formulae[*]}"
  for formula in "${formulae[@]}"; do
    # Skip empty elements just in case
    [[ -z "$formula" ]] && continue
    log_message "INFO" "Checking formula: $formula..."
    if brew list --formula | grep -q "^${formula}\$"; then
      log_message "INFO" "$formula is already installed. Skipping."
    else
      log_message "INFO" "Installing formula: $formula..."
      brew install "$formula"
      if [[ $? -ne 0 ]]; then
        log_message "WARNING" "Failed to install formula: $formula. Check brew output."
      else
        log_message "INFO" "Successfully installed formula: $formula."
      fi
    fi
  done
}

# Function to install Homebrew Casks (GUI applications)
install_casks() {
  local casks=("$@") # Accept array of casks
  if [[ ${#casks[@]} -eq 0 ]]; then
    log_message "INFO" "No casks provided to install in this list."
    return
  fi

  log_message "INFO" "Processing casks: ${casks[*]}"
  for cask in "${casks[@]}"; do
    # Skip empty elements just in case
    [[ -z "$cask" ]] && continue
    log_message "INFO" "Checking cask: $cask..."
    if brew list --cask | grep -q "^${cask}\$"; then
      log_message "INFO" "$cask is already installed. Skipping."
    else
      log_message "INFO" "Installing cask: $cask..."
      brew install --cask "$cask"
      if [[ $? -ne 0 ]]; then
        log_message "WARNING" "Failed to install cask: $cask. Check brew output."
      else
        log_message "INFO" "Successfully installed cask: $cask."
      fi
    fi
  done
}

# Function to check Malwarebytes status (basic checks)
check_malwarebytes_status() {
  log_message "INFO" "Checking Malwarebytes status (basic checks)..."
  local app_path="/Applications/Malwarebytes.app"
  local process_name="Malwarebytes" # Check actual process name if needed

  if [[ -d "$app_path" ]]; then
    log_message "INFO" "Malwarebytes application found at $app_path."

    # Check if a process containing the name is running (simple check)
    if pgrep -f "$process_name" > /dev/null; then
      log_message "INFO" "Malwarebytes process appears to be running."
    else
      log_message "WARNING" "Malwarebytes process does not appear to be running."
    fi
  else
    log_message "WARNING" "Malwarebytes application not found at $app_path. Ensure it was installed correctly (should be in shared casks)."
  fi
  # Note: This only checks if the process is running.
}

# Function to check Gatekeeper status
check_gatekeeper_status() {
  log_message "INFO" "Checking Gatekeeper status..."
  local status
  # Execute spctl command and capture output
  status=$(spctl --status)
  if [[ $? -eq 0 ]]; then
    log_message "INFO" "Gatekeeper status reported as: '$status'"
    # Check if the status string indicates it's enabled
    if [[ "$status" == "assessments enabled" ]]; then
        log_message "INFO" "Gatekeeper appears active."
    else
        log_message "WARNING" "Gatekeeper does not appear to be fully enabled ('$status')."
    fi
  else
    log_message "WARNING" "Could not determine Gatekeeper status using spctl command."
  fi
}


# --- Main Script Logic ---

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "ERROR" "Configuration file not found at $CONFIG_FILE"
    exit 1
fi

log_message "INFO" "======================================================================"
log_message "INFO" "Starting macOS software installation for RoleProfile: '$ROLE_PROFILE'"
log_message "INFO" "Using configuration file: $CONFIG_FILE"
log_message "INFO" "Logging to file: $LOG_FILE"
log_message "INFO" "======================================================================"

# Step 1: Ensure Homebrew and jq are installed
log_message "INFO" "[Step 1] --- Ensuring Prerequisites (Homebrew, jq) are Installed ---"
install_homebrew
install_jq

# Step 2: Read Software Packages from JSON config
log_message "INFO" "[Step 2] --- Reading Software Packages from $CONFIG_FILE ---"

# Validate JSON structure (basic check)
if ! jq empty "$CONFIG_FILE" > /dev/null 2>&1; then
    log_message "ERROR" "Invalid JSON structure in $CONFIG_FILE"
    exit 1
fi

# Read shared packages using jq and a while read loop (Bash 3+ compatible)
shared_formulae=()
while IFS= read -r line; do
    [[ -n "$line" ]] && shared_formulae+=("$line") # Add non-empty lines
done < <(jq -r '.shared.formulae // [] | .[]' "$CONFIG_FILE")

shared_casks=()
while IFS= read -r line; do
    [[ -n "$line" ]] && shared_casks+=("$line") # Add non-empty lines
done < <(jq -r '.shared.casks // [] | .[]' "$CONFIG_FILE")

log_message "INFO" "Shared formulae defined: ${shared_formulae[*]}"
log_message "INFO" "Shared casks defined: ${shared_casks[*]}"

# Read role-specific packages using jq and a while read loop
role_formulae=()
role_casks=()
if jq -e --arg ROLE "$ROLE_PROFILE" '.roles | has($ROLE)' "$CONFIG_FILE" > /dev/null; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && role_formulae+=("$line") # Add non-empty lines
    done < <(jq -r --arg ROLE "$ROLE_PROFILE" '.roles[$ROLE].formulae // [] | .[]' "$CONFIG_FILE")

    while IFS= read -r line; do
        [[ -n "$line" ]] && role_casks+=("$line") # Add non-empty lines
    done < <(jq -r --arg ROLE "$ROLE_PROFILE" '.roles[$ROLE].casks // [] | .[]' "$CONFIG_FILE")

    log_message "INFO" "Role-specific formulae for $ROLE_PROFILE: ${role_formulae[*]}"
    log_message "INFO" "Role-specific casks for $ROLE_PROFILE: ${role_casks[*]}"
else
    log_message "WARNING" "Role '$ROLE_PROFILE' not found in configuration file $CONFIG_FILE. No role-specific packages will be installed."
fi

# Step 3: Install Shared Packages
log_message "INFO" "[Step 3] --- Installing Shared Packages ---"
install_formulae "${shared_formulae[@]}"
install_casks "${shared_casks[@]}"

# Step 4: Install Role-Specific Packages
log_message "INFO" "[Step 4] --- Installing Role-Specific Packages for '$ROLE_PROFILE' ---"
install_formulae "${role_formulae[@]}"
install_casks "${role_casks[@]}"

# Step 5: Check Security Status (Malwarebytes & Gatekeeper)
log_message "INFO" "[Step 5] --- Checking Security Status (Malwarebytes & Gatekeeper) ---"
check_malwarebytes_status # Malwarebytes should have been installed as a shared cask
check_gatekeeper_status   # Check built-in Gatekeeper status

log_message "INFO" "======================================================================"
log_message "INFO" "macOS software installation and check process finished for role '$ROLE_PROFILE'."
log_message "INFO" "Review log file at: $LOG_FILE"
log_message "INFO" "======================================================================"

exit 0
