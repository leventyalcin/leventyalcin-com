#!/usr/bin/env bash

BINNAME=$0
BINPATH=$(realpath -s "$BINNAME")
REPO_ROOT=$(dirname "$BINPATH")
LIBS_PATH="${REPO_ROOT}/libs"
OGL_PATH="${LIBS_PATH}/opsgang"

# shellcheck disable=SC1090,SC1091
source "$REPO_ROOT/libs/local.bash" || exit 1

pre(){
    [[ -z "${TF_LOG:-}" ]] && [[ "${DEBUG:-}" =~ ^(TRACE|DEBUG|INFO|WARN|ERROR)$ ]] \
        && export TF_LOG="$DEBUG"

    download_libs || return 1
}

post(){
    i >&2 "Post hook"
    cleanup || return 1
    i >&2 "Done"
}

tf_apply(){
    local __plan_file="${TF_DIR}/${ENV}.tfplan"
    local __var_file="${TF_DIR}/${ENV}.tfvars"

    i >&2 "Running terraform plan"
    required_files "$__var_file" || return 1

    cd "$TF_DIR" || return 1
    [[ -n "${DEBUG:-}" ]] && set -x
    terraform plan \
        -compact-warnings \
        -input=false \
        -lock=true \
        -lock-timeout="$TF_BACKEND_LOCK_RETRY_DURATION" \
        -out="$__plan_file" \
        -var-file="$__var_file" \
        -var="git_user=$GIT_USER" \
        -var="git_info=$GIT_INFO" \
    || return 1
    [[ -n "${DEBUG:-}" ]] && set +x
    required_files "$__plan_file" || return 1
    if [[ "${FORCE_TO_APPLY_TF_WITHOUT_PUSHING_CHANGES:-}" = "iswearitisfordevelopmentreasons" ]]; then
        yellow_i >&2 "Please do not use flag unless there is a desperate need for DEBUG or development difficulties"
        yellow_i >&2 "If there is something which makes development harder, find a better solution for that and implement"
        yellow_i >&2 "Better that way!"
    else
        no_unpushed_changes || return 1
    fi
    terraform apply "$__plan_file" || return 1
    cd "$REPO_ROOT" || return 1
}

build(){
    pre || return 1

    # shellcheck disable=SC1090,SC1091
    source "$OGL_PATH/opsgang.sourcelibs" || return 1
    git_vars
    pre_run_checks || return 1
    tf_init || return 1
    tf_apply || return 1
}
trap post EXIT

build || exit 1
