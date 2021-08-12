TF_DEFAULT_DIR="${REPO_ROOT}/terraform"
TF_DIR="${TF_DIR:-$TF_DEFAULT_DIR}"
TF_BACKEND_LOCK_RETRY_DURATION="${TF_BACKEND_LOCK_RETRY_DURATION:-30s}"

download_libs(){
    if [[ -z "${OGL_PATH:-}" ]]; then
        echo >&2 "OGL_PATH is not set. Quitting..."
        return 1
    fi
    if [[ ! -d "$OGL_PATH" ]]; then
        local __OGL_VERSION

        __OGL_VERSION=${OGL_VERSION:-$(curl --silent --header "Accept: application/vnd.github.v3+json" https://api.github.com/repos/opsgang/libs/releases/latest | jq -r .tag_name)}
        curl --silent --location --output /tmp/habitual.tgz \
            "https://github.com/opsgang/libs/releases/download/$__OGL_VERSION/habitual.tgz"
        mkdir -p "$OGL_PATH"
        tar -zxf /tmp/habitual.tgz -C "$OGL_PATH" >&2 || return 1
    fi
}

required_files(){
    local -a __file_list
    local __rc=0
    local f

    d >&2 "Checking required files"
    read -r -a __file_list <<< "${@}"

    for f in "${__file_list[@]}"; do
        if [[ ! -f "$f" ]]; then
            e >&2 "File is not exist: $f"
            __rc=1
        elif [[ ! -r "$f" ]]; then
            e >&2 "Insufficient permission: $f"
            __rc=1
        else
            d >&2 "Found: $f"
        fi
    done
    return $__rc
}

required_dirs(){
    local -a __dir_list
    local __rc=0
    local dir

    d >&2 "Checking required files"
    read -r -a __dir_list <<< "${@}"

    for dir in "${__dir_list[@]}"; do
        if [[ ! -d "$dir" ]]; then
            e >&2 "Directory is not exist: $dir"
            __rc=1
        else
            d >&2 "Found: $dir"
        fi
    done
    return $__rc
}

pre_run_checks(){
    i >&2 "Running pre-run checks"
    required_vars "AWS_SECRET_ACCESS_KEY
    AWS_ACCESS_KEY_ID
    " \
    || required_vars "AWS_SHARED_CREDENTIALS_FILE
    AWS_PROFILE
    " \
    || required_vars "AWS_DEFAULT_PROFILE" \
    || return 1

    required_vars "CLOUDFLARE_EMAIL
    CLOUDFLARE_API_KEY
    " \
    || required_vars "CLOUDFLARE_EMAIL
    CLOUDFLARE_API_TOKEN" \
    || return 1

    required_vars "ENV
    TF_BACKEND_BUCKET
    TF_BACKEND_KEY
    TF_BACKEND_REGION
    TF_BACKEND_LOCK_RETRY_DURATION
    GIT_USER
    GIT_INFO
    " || return 1
}

cleanup(){
    if [[ -n "${PRESERVE_FILES:-}" ]]; then
        yellow_i >&2 "Skipping clean up. PRESERVE_FILES is set"
        return 0
    fi
    i >&2 "Cleaning up"
    # remove dynamically created files eg .tfplan and .backend.tfvars
    [[ -n "${DEBUG:-}" ]] && set -x
    # Terraform files
    find "$REPO_ROOT" -type f \( -name '*.tfplan' -o -name "*.backend.tfvars" \) -delete
    # Terraform directory
    find "$REPO_ROOT" -type d -name '.terraform' -prune -exec rm -rf {} \;
    # Files required by Hugo
    find "$REPO_ROOT" -type f -name '.credentials' -delete
    # Files changed by Hugo
    if [[ -n "${HUGO_DIR:-}" ]]; then
        if [[ -f "$HUGO_DIR/config.toml.bak" ]]; then
            mv "$HUGO_DIR/config.toml.bak" "$HUGO_DIR/config.toml"
        fi
    fi
    [[ -n "${DEBUG:-}" ]] && set +x

    return 0
}

create_backend_config() {
    local __backend_config="${TF_DIR}/${ENV}.backend.tfvars"
    cat <<EOF > "$__backend_config"
bucket="$TF_BACKEND_BUCKET"
key="$TF_BACKEND_KEY"
region="$TF_BACKEND_REGION"
EOF
    required_files "$__backend_config" || return 1
}

tf_init() {
    i >&2 "Initialising terraform"
    required_dirs "$TF_DIR" || return 1
    create_backend_config || return 1
    cd "$TF_DIR" || return 1
    if [[ -n "${DEBUG:-}" ]]; then
        set -x
        # If terraform is running locally for any reason and plugin cache dir is not set
        # better to remind. So, that init won't need to download plugins every single time.
        [[ -z "${TF_PLUGIN_CACHE_DIR:-}" ]] \
            && [[ -z "${CI:-}" ]] \
            && red_i >&2 "Terraform plugin cache directory is not set. Consider it (wink)"
    fi
    terraform init \
        -upgrade=true \
        -backend-config="${TF_DIR}/${ENV}.backend.tfvars" \
    || return 1
    terraform validate
    [[ -n "${DEBUG:-}" ]] && set +x
    cd "$REPO_ROOT" || return 1
}

aws_generate_creds_file() {
    local __json_output
    local __aws_session_token
    local __aws_secret_access_key
    local __aws_session_token
    local __aws_region

    __json_output="/tmp/__tmp_aws-session-$(date +"%Y%m%d%H%M%S")"

    aws --output=json \
        sts get-session-token \
            --query 'Credentials.{aws_access_key_id:AccessKeyId, aws_secret_access_key:SecretAccessKey, aws_session_token:SessionToken}' \
    > "$__json_output" || return 1
    __aws_region=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')

    __aws_access_key_id=$(jq -r '.aws_access_key_id' "$__json_output")
    __aws_secret_access_key=$(jq -r '.aws_secret_access_key' "$__json_output")
    __aws_session_token=$(jq -r '.aws_session_token' "$__json_output")
    rm -f "$__json_output" >/dev/null 2>&1
    required_vars "__aws_region
    __aws_access_key_id
    __aws_secret_access_key
    __aws_session_token" \
    || return 1

    echo "[default]
aws_access_key_id=$__aws_access_key_id
aws_secret_access_key=$__aws_secret_access_key
aws_session_token=$__aws_session_token
region=$__aws_region"
}
